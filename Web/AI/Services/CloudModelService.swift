import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cloud Apple Intelligence service using Shortcuts app integration
/// EXACT implementation from working RSSReader codebase
class CloudModelService: ObservableObject {
    
    // MARK: - Properties
    
    private var currentRequestType: AppleIntelligenceRequestType?
    private var currentRequestCompletion: ((String) -> Void)?
    private var clipboardTimer: Timer?
    private var requestTimeoutTimer: Timer?
    private var clipboardCheckCount = 0
    private let maxClipboardChecks = 24 // 2 minutes at 5-second intervals
    private let requestTimeoutSeconds = 120 // 2 minutes timeout
    private var isRequestInProgress = false // Prevent multiple concurrent requests
    private let requestQueue = DispatchQueue(label: "cloudModelServiceQueue", qos: .userInitiated)
    
    // MARK: - Public Interface
    
    /// Launch cloud request via URL scheme to run shortcut without requiring AppleScript authorization
    func launchCloudRequest(for text: String, type: AppleIntelligenceRequestType, completion: ((String) -> Void)?) {
        // Prevent multiple concurrent requests
        guard !isRequestInProgress else {
            NSLog("⚠️ CloudModelService: Request already in progress, ignoring new request")
            completion?("Cloud AI service is busy processing another request. Please wait.")
            return
        }
        
        isRequestInProgress = true
        
        // Store the request type and completion handler
        self.currentRequestType = type
        self.currentRequestCompletion = { [weak self] response in
            // Reset request in progress flag when completion is called
            self?.isRequestInProgress = false
            completion?(response)
        }
        
        #if os(macOS)
        // Use shortcuts CLI to run the shortcut without opening the app
        NSLog("📱 CloudModelService: Using shortcuts CLI to run shortcut in background")
        NSLog("📱 CloudModelService: Text length: \(text.count) chars")
        
        // Create a temporary file for input
        let tempDir = FileManager.default.temporaryDirectory
        let inputFile = tempDir.appendingPathComponent("shortcut_input_\(UUID().uuidString).txt")
        let outputFile = tempDir.appendingPathComponent("shortcut_output_\(UUID().uuidString).txt")
        
        do {
            // Write input text to temporary file
            try text.write(to: inputFile, atomically: true, encoding: .utf8)
            NSLog("📱 CloudModelService: Wrote input to temp file: \(inputFile.path)")
            
            // Create a Process to run the shortcuts CLI
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = [
                "run",
                "RSS Reader Cloud Summary",
                "--input-path", inputFile.path,
                "--output-path", outputFile.path,
                "--output-type", "public.plain-text"
            ]
            
            // Set up pipes for capturing any errors
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            NSLog("📱 CloudModelService: Running shortcuts CLI command...")
            
            // Run the shortcut command asynchronously
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // Clean up input file
                    try? FileManager.default.removeItem(at: inputFile)
                    
                    if process.terminationStatus == 0 {
                        // Success - read the output
                        if let output = try? String(contentsOf: outputFile, encoding: .utf8), !output.isEmpty {
                            NSLog("✅ CloudModelService: Shortcut executed successfully via CLI")
                            NSLog("📋 CloudModelService: Output length: \(output.count) chars")
                            
                            // Clean up output file
                            try? FileManager.default.removeItem(at: outputFile)
                            
                            DispatchQueue.main.async {
                                self?.isRequestInProgress = false
                                self?.currentRequestCompletion?(output)
                                self?.currentRequestCompletion = nil
                                self?.currentRequestType = nil
                            }
                        } else {
                            // No output or empty output - fall back to clipboard monitoring
                            NSLog("⚠️ CloudModelService: No output from CLI, falling back to clipboard monitoring")
                            DispatchQueue.main.async {
                                self?.startClipboardMonitoring(for: type)
                            }
                        }
                    } else {
                        // Error running shortcut
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        NSLog("❌ CloudModelService: Shortcut CLI failed with status \(process.terminationStatus): \(errorString)")
                        
                        // Clean up files
                        try? FileManager.default.removeItem(at: outputFile)
                        
                        DispatchQueue.main.async {
                            self?.isRequestInProgress = false
                            self?.currentRequestCompletion?("Cloud AI service encountered an error: \(errorString)")
                            self?.currentRequestCompletion = nil
                            self?.currentRequestType = nil
                        }
                    }
                } catch {
                    NSLog("❌ CloudModelService: Failed to run shortcuts CLI: \(error)")
                    
                    // Clean up files
                    try? FileManager.default.removeItem(at: inputFile)
                    try? FileManager.default.removeItem(at: outputFile)
                    
                    DispatchQueue.main.async {
                        self?.isRequestInProgress = false
                        self?.currentRequestCompletion?("Failed to run Cloud AI service: \(error.localizedDescription)")
                        self?.currentRequestCompletion = nil
                        self?.currentRequestType = nil
                    }
                }
            }
        } catch {
            NSLog("❌ CloudModelService: Failed to write input file: \(error)")
            currentRequestCompletion?("Failed to prepare input for Cloud AI service: \(error.localizedDescription)")
            isRequestInProgress = false
        }
        
        #elseif os(iOS)
        // On iOS, we still need to use URL scheme, but we'll use a more targeted approach
        let callbackURL = "shortcuts://x-callback-url/run-shortcut"
        var components = URLComponents(string: callbackURL)!
        
        components.queryItems = [
            URLQueryItem(name: "name", value: "RSS Reader Cloud Summary"),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "x-source", value: "Web Browser"),
            URLQueryItem(name: "x-success", value: "webbrowser://success"),
            URLQueryItem(name: "x-error", value: "webbrowser://error")
        ]
        
        guard let url = components.url else {
            NSLog("⚠️ CloudModelService: Could not create x-callback URL")
            currentRequestCompletion?("Cloud AI service temporarily unavailable. Please check Shortcuts app.")
            isRequestInProgress = false
            return
        }
        
        NSLog("📱 CloudModelService: Using x-callback-url on iOS")
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                NSLog("✅ CloudModelService: Successfully launched shortcut via x-callback-url")
                // On iOS, we'll use clipboard monitoring for the response
                self.startClipboardMonitoring(for: type)
            } else {
                NSLog("⚠️ CloudModelService: x-callback-url failed")
                self.currentRequestCompletion?("Could not launch Shortcuts app. Please check if Shortcuts is installed.")
                self.isRequestInProgress = false
            }
        }
        #endif
    }
    
    // MARK: - Private Methods
    
    private func fallbackToRegularURL(text: String, type: AppleIntelligenceRequestType) {
        // Fallback to regular shortcuts URL if x-callback-url fails
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let shortcutURL = "shortcuts://run-shortcut?name=RSS%20Reader%20Cloud%20Summary&input=text&text=\(encodedText)"
        
        NSLog("📱 CloudModelService: Fallback URL text length: \(text.count) chars, encoded: \(encodedText.count) chars")
        
        guard let url = URL(string: shortcutURL) else {
            NSLog("❌ CloudModelService: Could not create fallback URL")
            currentRequestCompletion?("Cloud AI service temporarily unavailable. Please check Shortcuts app.")
            return
        }
        
        #if os(iOS)
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                NSLog("✅ CloudModelService: Fallback URL launched successfully")
                // Start monitoring clipboard for result AFTER launch succeeds
                self.startClipboardMonitoring(for: type)
            } else {
                self.isRequestInProgress = false // Reset request in progress flag on error
                self.currentRequestCompletion?("Could not launch Shortcuts app. Please check if Shortcuts is installed.")
            }
        }
        #elseif os(macOS)
        NSLog("📱 CloudModelService: Opening fallback URL: \(url.absoluteString)")
        
        // FIX: Use NSWorkspace.openURLs instead of NSWorkspace.open to prevent new app instances
        // This method reuses existing app instances when possible
        NSWorkspace.shared.open([url], withAppBundleIdentifier: "com.apple.shortcuts", options: [], additionalEventParamDescriptor: nil, launchIdentifiers: nil)
        
        // Start monitoring clipboard immediately since we can't get a completion handler
        self.startClipboardMonitoring(for: type)
        #endif
    }
    
    private func startClipboardMonitoring(for type: AppleIntelligenceRequestType) {
        // CLIPBOARD FIX: Ensure proper timer cleanup and creation
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        clipboardCheckCount = 0
        
        // Cancel any existing timeout timer
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        
        // Store the original clipboard content
        #if os(iOS)
        let originalClipboard = UIPasteboard.general.string ?? ""
        #elseif os(macOS)
        let originalClipboard = NSPasteboard.general.string(forType: .string) ?? ""
        #endif
        
        NSLog("📋 CloudModelService: Starting clipboard monitoring for Apple Intelligence response (\(type))...")
        NSLog("📋 CLIPBOARD DEBUG: Original clipboard content: '\(String(originalClipboard.prefix(100)))...' (length: \(originalClipboard.count))")
        
        // Start timeout timer
        requestTimeoutTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(requestTimeoutSeconds), repeats: false) { [weak self] timer in
            guard let self = self else { return }
            
            NSLog("⏱️ CloudModelService: Request timeout after \(self.requestTimeoutSeconds) seconds")
            
            DispatchQueue.main.async {
                // Clean up state
                self.clipboardTimer?.invalidate()
                self.clipboardTimer = nil
                self.clipboardCheckCount = 0
                self.requestTimeoutTimer?.invalidate()
                self.requestTimeoutTimer = nil
                self.isRequestInProgress = false
                
                // Call completion with timeout message
                self.currentRequestCompletion?("Apple Intelligence processing took longer than expected. Please try again.")
                self.currentRequestCompletion = nil
                self.currentRequestType = nil
            }
        }
        
        // CLIPBOARD FIX: Always create timer on main thread - use async to prevent deadlock
        if Thread.isMainThread {
            self.createClipboardTimer(originalClipboard: originalClipboard, type: type)
        } else {
            DispatchQueue.main.async {
                self.createClipboardTimer(originalClipboard: originalClipboard, type: type)
            }
        }
    }
    
    private func createClipboardTimer(originalClipboard: String, type: AppleIntelligenceRequestType) {
        NSLog("📋 CLIPBOARD DEBUG: Creating timer on main thread: \(Thread.isMainThread)")
        
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            // DEADLOCK FIX: Move timer callback to background thread to prevent main thread blocking
            DispatchQueue.global(qos: .background).async {
                guard let self = self else {
                    DispatchQueue.main.async {
                        NSLog("📋 CLIPBOARD DEBUG: Self deallocated, invalidating timer")
                        timer.invalidate()
                    }
                    return
                }
                
                self.clipboardCheckCount += 1
                let elapsedTime = self.clipboardCheckCount * 5
                let totalTime = self.maxClipboardChecks * 5
                
                #if os(iOS)
                let currentClipboard = UIPasteboard.general.string ?? ""
                #elseif os(macOS)
                let currentClipboard = NSPasteboard.general.string(forType: .string) ?? ""
                #endif
                
                NSLog("📋 CloudModelService: Timer fired! Checking clipboard for \(type)... (attempt \(self.clipboardCheckCount)/\(self.maxClipboardChecks))")
                NSLog("📋 CLIPBOARD DEBUG: Original length: \(originalClipboard.count), Current length: \(currentClipboard.count)")
                NSLog("📋 CLIPBOARD DEBUG: Current clipboard preview: '\(String(currentClipboard.prefix(100)))...'")
                NSLog("📋 CLIPBOARD DEBUG: Are they different? \(currentClipboard != originalClipboard)")
                
                // If clipboard changed and contains meaningful content
                if currentClipboard != originalClipboard && !currentClipboard.isEmpty {
                    // Additional validation: Check if this looks like an AI response
                    // AI responses typically have sentences, not just random clipboard data
                    let hasValidContent = currentClipboard.count > 10 && 
                                        (currentClipboard.contains(" ") || currentClipboard.contains("."))
                    
                    if hasValidContent {
                        NSLog("✅ CloudModelService: Found \(type) response in clipboard after \(elapsedTime) seconds!")
                        NSLog("📋 CLIPBOARD DEBUG: Response preview: '\(String(currentClipboard.prefix(200)))...'")
                        
                        // Return to main thread for completion handler and cleanup
                        DispatchQueue.main.async {
                            // FIX: Store completion handler before clearing it
                            let completionHandler = self.currentRequestCompletion
                            
                            // Clean up state BEFORE calling completion handler to prevent race conditions
                            self.currentRequestCompletion = nil
                            self.currentRequestType = nil
                            self.isRequestInProgress = false // Reset request in progress flag on success
                            
                            // Stop monitoring
                            timer.invalidate()
                            self.clipboardTimer = nil
                            self.clipboardCheckCount = 0
                            NSLog("📋 CLIPBOARD DEBUG: Timer invalidated and cleanup completed")
                            
                            // Return the response AFTER cleanup
                            NSLog("📋 CLIPBOARD DEBUG: About to call completion handler with response")
                            completionHandler?(currentClipboard)
                            NSLog("📋 CLIPBOARD DEBUG: Completion handler called successfully")
                        }
                        return
                    } else {
                        NSLog("📋 CLIPBOARD DEBUG: Clipboard changed but content doesn't look like AI response (length: \(currentClipboard.count))")
                    }
                }
                
                // Check if we've exceeded the maximum attempts
                if self.clipboardCheckCount >= self.maxClipboardChecks {
                    NSLog("⏱️ CloudModelService: Clipboard monitoring timed out after \(totalTime) seconds for \(type)")
                    
                    // Return to main thread for completion handler and cleanup
                    DispatchQueue.main.async {
                        // FIX: Store completion handler before clearing it
                        let completionHandler = self.currentRequestCompletion
                        
                        // Clean up state BEFORE calling completion handler
                        self.currentRequestCompletion = nil
                        self.currentRequestType = nil
                        self.isRequestInProgress = false // Reset request in progress flag on timeout
                        
                        timer.invalidate()
                        self.clipboardTimer = nil
                        self.clipboardCheckCount = 0
                        
                        // Call completion handler AFTER cleanup
                        let timeoutMessage = "Apple Intelligence processing took longer than expected. Please check your clipboard manually or try again."
                        completionHandler?(timeoutMessage)
                    }
                }
            }
        }
        
        NSLog("📋 CLIPBOARD DEBUG: Timer created successfully: \(clipboardTimer != nil)")
    }
}

// MARK: - URL Callback Handling

extension CloudModelService {
    /// Handle URL callbacks from x-callback-url
    func handleURLCallback(_ url: URL) {
        NSLog("🔗 CloudModelService: Received URL callback: \(url.absoluteString)")
        
        // Handle success callback from x-callback-url
        if url.scheme == "webbrowser" && url.host == "success" {
            NSLog("✅ CloudModelService: Shortcut executed successfully via x-callback-url")
            isRequestInProgress = false // Reset request in progress flag on success
            return
        }
        
        // Handle error callback from x-callback-url
        if url.scheme == "webbrowser" && url.host == "error" {
            NSLog("❌ CloudModelService: Shortcut execution failed via x-callback-url")
            isRequestInProgress = false // Reset request in progress flag on error
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                
                if let errorMessage = queryItems.first(where: { $0.name == "errorMessage" })?.value {
                    NSLog("❌ CloudModelService: Error details: \(errorMessage)")
                    currentRequestCompletion?("Cloud AI error: \(errorMessage)")
                } else {
                    currentRequestCompletion?("Cloud AI service encountered an error.")
                }
            } else {
                currentRequestCompletion?("Cloud AI service encountered an unknown error.")
            }
            return
        }
    }
}
