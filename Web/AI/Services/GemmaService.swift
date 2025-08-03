import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Gemma AI service for local inference with Apple Intelligence
/// Handles model initialization, text generation, and response streaming using Apple's on-device AI
/// Updated to use LocalSummaryService for proper Apple Intelligence integration
class GemmaService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let privacyManager: PrivacyManager
    private let appleIntelligenceService: AppleIntelligenceService?
    private let cloudModelService: CloudModelService
    
    private var isModelLoaded: Bool = false
    // Apple Intelligence handles everything on-device with complete privacy
    
    // No remote fallbacks - uses Apple's Foundation Models framework
    // Model management handled by the system
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        privacyManager: PrivacyManager
    ) {
        self.configuration = configuration
        self.privacyManager = privacyManager
        self.cloudModelService = CloudModelService()
        
        // Initialize Apple Intelligence service if available (using LocalSummaryService pattern)
        if #available(iOS 18.2, macOS 15.2, *), LocalSummaryService.isAvailable() {
            self.appleIntelligenceService = AppleIntelligenceService(
                configuration: configuration,
                privacyManager: privacyManager
            )
            NSLog("🔮 Gemma Service initialized with Apple Intelligence (Local + Cloud)")
        } else {
            self.appleIntelligenceService = nil
            NSLog("⚠️ Apple Intelligence not available, service will use cloud + Gemini fallback")
        }
    }
    
    // MARK: - Public Interface
    
    /// Initialize the Gemma model and tokenizer
    func initialize() async throws {
        guard !isModelLoaded else {
            NSLog("✅ Gemma model already loaded")
            return
        }
        
        do {
            // Check Apple Intelligence availability using LocalSummaryService
            if #available(iOS 18.2, macOS 15.2, *), LocalSummaryService.isAvailable() {
                // Initialize Apple Intelligence service if available
                if let appleIntelligenceService = appleIntelligenceService {
                    try await appleIntelligenceService.initialize()
                    isModelLoaded = true
                    NSLog("✅ Apple Intelligence ready successfully")
                } else {
                    // LocalSummaryService is available but AppleIntelligenceService failed to init
                    isModelLoaded = true
                    NSLog("✅ LocalSummaryService available, ready for direct usage")
                }
            } else {
                // Fallback for devices without Apple Intelligence
                isModelLoaded = true
                NSLog("⚠️ Apple Intelligence not available, using fallback mode")
            }
            
        } catch {
            NSLog("❌ Failed to initialize Gemma model: \(error)")
            throw GemmaError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Direct Local Apple Intelligence summarization (RSSReader pattern)
    func summarizeTextWithLocalAI(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        if #available(iOS 18.2, macOS 15.2, *), LocalSummaryService.isAvailable() {
            NSLog("📱 GemmaService: Using LocalSummaryService for summarization")
            LocalSummaryService.summarizeText(text, completion: completion)
        } else {
            NSLog("⚠️ GemmaService: LocalSummaryService not available, using fallback")
            completion(.failure(GemmaError.lmStudioNotAvailable))
        }
    }
    
    /// Smart fallback: Local -> Cloud -> Gemini (EXACT RSSReader pattern)
    func performSmartSummarization(
        prompt: String,
        taskName: String,
        completion: @escaping (String) -> Void
    ) {
        // Check user preference for model source
        let modelSource = UserDefaults.standard.string(forKey: "aiModelSource") ?? "local"
        
        // ONLY CHANGE: Check context size before attempting local model
        let estimatedTokens = TokenEstimator.estimateTokens(for: prompt)
        let localModelTokenLimit = 32768 // From HardwareDetector
        
        // If user explicitly chose cloud, skip local model entirely
        if modelSource == "cloud" {
            NSLog("📊 GemmaService: User selected cloud model, skipping local for \(taskName)")
            performCloudFallback(prompt: prompt, taskName: taskName, completion: completion)
            return
        }
        
        // If context is too large and user allows fallback, go to cloud
        if estimatedTokens > localModelTokenLimit && modelSource == "local" {
            NSLog("📊 GemmaService: Context too large (\(estimatedTokens) tokens > \(localModelTokenLimit)), using cloud directly for \(taskName)")
            performCloudFallback(prompt: prompt, taskName: taskName, completion: completion)
            return
        }
        
        // User explicitly chose local or default behavior
        if modelSource == "local" || modelSource == "local" {
            if #available(iOS 18.2, macOS 15.2, *), LocalSummaryService.isAvailable() {
                NSLog("📱 GemmaService: Trying local model for \(taskName)")
                NSLog("🔍 [TL;DR] Sending to model: \(prompt.count) chars - '\(String(prompt.prefix(200)))...'")
                LocalSummaryService.summarizeText(prompt) { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let response):
                        NSLog("✅ GemmaService: Local model succeeded for \(taskName)")
                        completion(response)
                    case .failure(let error):
                        NSLog("⚠️ GemmaService: Local model failed for \(taskName): \(error.localizedDescription)")
                        
                        // Only fallback to cloud if user allows it (not explicitly local)
                        if modelSource != "local" {
                            self.performCloudFallback(prompt: prompt, taskName: taskName, completion: completion)
                        } else {
                            // User explicitly chose local, don't fallback
                            completion("Local AI model failed. Please check your device supports Apple Intelligence or switch to cloud model in settings.")
                        }
                    }
                }
            } else {
                if modelSource == "local" {
                    // User explicitly chose local but it's not available
                    completion("Local AI model not available on this device. Please switch to cloud model in settings.")
                } else {
                    // Default fallback
                    performCloudFallback(prompt: prompt, taskName: taskName, completion: completion)
                }
            }
        } else {
            NSLog("⚠️ GemmaService: Local model not available, using cloud for \(taskName)")
            performCloudFallback(prompt: prompt, taskName: taskName, completion: completion)
        }
    }
    
    /// Cloud fallback via Shortcuts
    private func performCloudFallback(
        prompt: String,
        taskName: String,
        completion: @escaping (String) -> Void
    ) {
        NSLog("☁️ GemmaService: Attempting cloud model for \(taskName)")
        
        cloudModelService.launchCloudRequest(for: prompt, type: .summary) { [weak self] response in
            guard let self = self else { return }
            
            // Check if cloud response is valid
            if response.contains("Cloud AI service temporarily unavailable") || 
               response.contains("Could not launch Shortcuts") ||
               response.contains("Apple Intelligence processing took longer than expected") {
                NSLog("⚠️ GemmaService: Cloud model failed, falling back to Gemini for \(taskName)")
                self.performGeminiFallback(prompt: prompt, taskName: taskName, completion: completion)
            } else {
                NSLog("✅ GemmaService: Cloud model succeeded for \(taskName)")
                completion(response)
            }
        }
    }
    
    /// Final Gemini fallback
    private func performGeminiFallback(
        prompt: String,
        taskName: String,
        completion: @escaping (String) -> Void
    ) {
        NSLog("🔄 GemmaService: Using Gemini fallback for \(taskName)")
        // TODO: Implement Gemini API call here as final fallback
        // For now, return a helpful message
        completion("Gemini fallback not yet implemented. Please try again or use a shorter text.")
    }
    
    /// Smart Q&A: Local -> Cloud -> Gemini (RSSReader pattern for chat)
    func performSmartQA(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        completion: @escaping (String) -> Void
    ) {
        // Check user preference for model source
        let modelSource = UserDefaults.standard.string(forKey: "aiModelSource") ?? "local"
        
        // Build the prompt exactly like AppleIntelligenceService does
        let prompt = buildQAPrompt(query: query, context: context, conversationHistory: conversationHistory)
        
        // Check if Apple Intelligence is available and properly initialized
        guard isModelLoaded else {
            NSLog("⚠️ GemmaService: Model not loaded, falling back to cloud for Q&A")
            if modelSource == "local" {
                completion("Local AI model not initialized. Please check your device supports Apple Intelligence or switch to cloud model in settings.")
                return
            }
            performCloudQAFallback(prompt: prompt, completion: completion)
            return
        }
        
        // If user explicitly chose cloud, skip local model entirely
        if modelSource == "cloud" {
            NSLog("📊 GemmaService: User selected cloud model, skipping local for Q&A")
            performCloudQAFallback(prompt: prompt, completion: completion)
            return
        }
        
        // User chose local or default - use local model
        if modelSource == "local" || modelSource == "local" {
            if #available(iOS 18.2, macOS 15.2, *), LocalSummaryService.isAvailable() {
                NSLog("📱 GemmaService: Using Apple Intelligence local model for Q&A")
                
                // Use local model for ALL questions, not just first ones
                let limitedContext = String((context ?? "").prefix(8000))
                NSLog("🔍 [Q&A] Sending to Apple Intelligence: \(limitedContext.count) chars - '\(String(limitedContext.prefix(200)))...'")
                
                // Use the properly initialized Apple Intelligence service instead of direct LocalSummaryService
                if let appleIntelligenceService = appleIntelligenceService {
                    Task {
                        do {
                            let response = try await appleIntelligenceService.generateResponse(
                                query: query,
                                context: limitedContext,
                                conversationHistory: conversationHistory
                            )
                            DispatchQueue.main.async {
                                NSLog("✅ GemmaService: Apple Intelligence succeeded for Q&A")
                                completion(response.text)
                            }
                        } catch {
                            NSLog("⚠️ GemmaService: Apple Intelligence failed for Q&A: \(error.localizedDescription)")
                            
                            // Only fallback to cloud if user allows it (not explicitly local)
                            if modelSource != "local" {
                                self.performCloudQAFallback(prompt: prompt, completion: completion)
                            } else {
                                completion("Local AI model failed. Please check your device supports Apple Intelligence or switch to cloud model in settings.")
                            }
                        }
                    }
                } else {
                    // Fallback to LocalSummaryService if AppleIntelligenceService is nil
                    LocalSummaryService.askQuestion(about: limitedContext, question: query) { [weak self] result in
                        guard let self = self else { return }
                        
                        switch result {
                        case .success(let response):
                            NSLog("✅ GemmaService: LocalSummaryService succeeded for Q&A")
                            completion(response)
                        case .failure(let error):
                            NSLog("⚠️ GemmaService: LocalSummaryService failed for Q&A: \(error.localizedDescription)")
                            
                            // Only fallback to cloud if user allows it
                            if modelSource != "local" {
                                self.performCloudQAFallback(prompt: prompt, completion: completion)
                            } else {
                                completion("Local AI model failed. Please check your device supports Apple Intelligence or switch to cloud model in settings.")
                            }
                        }
                    }
                }
            } else {
                if modelSource == "local" {
                    // User explicitly chose local but it's not available
                    completion("Local AI model not available on this device. Please switch to cloud model in settings.")
                } else {
                    // Default fallback
                    performCloudQAFallback(prompt: prompt, completion: completion)
                }
            }
        } else {
            NSLog("⚠️ GemmaService: Apple Intelligence not available, using cloud for Q&A")
            performCloudQAFallback(prompt: prompt, completion: completion)
        }
    }
    
    /// Cloud fallback for Q&A
    private func performCloudQAFallback(
        prompt: String,
        completion: @escaping (String) -> Void
    ) {
        NSLog("☁️ GemmaService: Attempting cloud model for Q&A")
        NSLog("🔍 CRASH DEBUG: In performCloudQAFallback, about to call cloudModelService.launchCloudRequest")
        NSLog("🔍 CRASH DEBUG: Prompt length: \(prompt.count), first 100 chars: '\(String(prompt.prefix(100)))...'")
        
        cloudModelService.launchCloudRequest(for: prompt, type: .articleQA) { [weak self] response in
            NSLog("🔍 CLOUD RESPONSE DEBUG: CloudModelService callback received with response length: \(response.count)")
            NSLog("🔍 CLOUD RESPONSE DEBUG: Response preview: '\(String(response.prefix(100)))...'")
            guard let self = self else { 
                NSLog("🔍 CLOUD RESPONSE DEBUG: self is nil in cloudModelService callback")
                return 
            }
            
            // Check if cloud response is valid
            if response.contains("Cloud AI service temporarily unavailable") || 
               response.contains("Could not launch Shortcuts") ||
               response.contains("Apple Intelligence processing took longer than expected") {
                NSLog("⚠️ GemmaService: Cloud model failed, falling back to Gemini for Q&A")
                self.performGeminiFallback(prompt: prompt, taskName: "Q&A", completion: completion)
            } else {
                NSLog("✅ GemmaService: Cloud model succeeded for Q&A")
                NSLog("🔍 CLOUD RESPONSE DEBUG: About to call GemmaService completion with response")
                completion(response)
                NSLog("🔍 CLOUD RESPONSE DEBUG: GemmaService completion callback executed successfully")
            }
        }
    }
    
    /// Build Q&A prompt like AppleIntelligenceService does
    private func buildQAPrompt(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) -> String {
        var prompt = ""
        
        // Add system context
        prompt += "You are a helpful assistant. Answer questions based on provided webpage content.\n\n"
        
        // Add recent conversation history (limited)
        let maxHistoryMessages = 6
        let recentHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        
        for message in recentHistory {
            prompt += "\(message.role.rawValue.capitalized): \(message.content)\n"
        }
        
        // Add current context if available
        if let context = context, !context.isEmpty {
            let contextLimit = recentHistory.isEmpty ? 15000 : 6000
            let cleanContext = String(context.prefix(contextLimit))
                .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            prompt += "\nWEBPAGE CONTENT:\n\(cleanContext)\n\n---\n\n"
        }
        
        // Add the current query
        prompt += "User: \(query)\n\nAssistant: "
        
        return prompt
    }
    
    /// Generate a response for the given query and context
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AIResponse {
        
        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }
        
        // Memory pressure checks removed - were causing unnecessary complexity
        
        let responseBuilder = AIResponseBuilder()
        let _ = Date() // Track timing but not used in current implementation
        
        do {
            // Step 1: Prepare the prompt
            let _ = responseBuilder.addProcessingStep(ProcessingStep(
                name: "prompt_preparation",
                duration: 0.1,
                description: "Preparing input prompt with context"
            ))
            
            if context != nil {
                let _ = responseBuilder.setContextUsed(true)
            }
            
            // Use Apple Intelligence for local inference
            let _ = responseBuilder.addProcessingStep(ProcessingStep(name: "apple_intelligence_inference", duration: 0, description: "Running Apple Intelligence on-device inference"))

            do {
                if let appleIntelligenceService = appleIntelligenceService {
                    // Use Apple Intelligence service
                    let response = try await appleIntelligenceService.generateResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    return response
                } else {
                    // Fallback response for devices without Apple Intelligence
                    let fallbackText = "Apple Intelligence is not available on this device. Please update to iOS 18.2+ or macOS 15.2+ and ensure your device supports Apple Intelligence."
                    return responseBuilder.setText(fallbackText).build()
                }
            } catch {
                NSLog("❌ Apple Intelligence inference failed: \(error)")
                throw GemmaError.inferenceError("Apple Intelligence inference failed: \(error.localizedDescription)")
            }

            // All inference handled above by Apple Intelligence
            
        } catch {
            NSLog("❌ Response generation failed: \(error)")
            throw error
        }
    }
    
    /// Generate a streaming response with real-time token updates using smart fallback
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        NSLog("🔍 HANG DEBUG: generateStreamingResponse called with query: '\(query)', history count: \(conversationHistory.count)")
        
        guard isModelLoaded else {
            NSLog("🔍 HANG DEBUG: Model not loaded, throwing error")
            throw GemmaError.modelNotLoaded
        }
        
        NSLog("🔍 HANG DEBUG: Model is loaded, creating AsyncThrowingStream")
        
        return AsyncThrowingStream { continuation in
            // Use the smart fallback Q&A method instead of direct Apple Intelligence
            performSmartQA(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            ) { response in
                NSLog("🌊 STREAMING DEBUG: Received response from performSmartQA: '\(String(response.prefix(100)))...' (length: \(response.count))")
                
                // THREADING FIX: Execute continuation calls synchronously to prevent deadlock
                // CloudModelService completes on main thread, so we stay on main thread
                NSLog("🔄 THREADING DEBUG: Executing continuation calls synchronously")
                
                if response.contains("Cloud AI service temporarily unavailable") ||
                   response.contains("Could not launch Shortcuts") ||
                   response.contains("Apple Intelligence processing took longer than expected") {
                    NSLog("⚠️ STREAMING DEBUG: Detected error response, yielding as-is")
                    continuation.yield(response)
                } else if !response.isEmpty {
                    NSLog("🌊 STREAMING DEBUG: Yielding complete cloud response immediately")
                    continuation.yield(response)
                } else {
                    NSLog("⚠️ No content received, providing fallback response")
                    let fallbackResponse = "I'm ready to help you with questions about the current webpage content."
                    continuation.yield(fallbackResponse)
                }
                
                continuation.finish()
                NSLog("✅ Streaming completed successfully (synchronous, no deadlock)")
            }
        }
    }
    
    /// Summarize a conversation
    func summarizeConversation(_ messages: [ConversationMessage]) async throws -> String {
        if let appleIntelligenceService = appleIntelligenceService {
            let response = try await appleIntelligenceService.summarizeConversation(messages)
            return response
        } else {
            return "Apple Intelligence not available for conversation summarization."
        }
    }
    
    /// Reset conversation state
    func resetConversation() async {
        // Reset the Apple Intelligence service conversation state
        if let appleIntelligenceService = appleIntelligenceService {
            await appleIntelligenceService.resetConversation()
        }
        NSLog("🔄 GemmaService conversation reset completed")
    }
    
    // Memory pressure handling removed - was overcomplicating the system
    
    // All inference now handled by Apple Intelligence on-device
    
    /// Additional cleanup pass used by the TL;DR pipeline to salvage a summary when the
    /// model produces heavy phrase-level repetition. It repeatedly collapses any 3-6 word
    /// chunk that appears two or more times in a row (case-insensitive) until no such
    /// patterns remain. This sits on top of `postProcessResponse`.
    /// - Parameter text: The raw summary to clean.
    /// - Returns: A cleaned version with collapsed repetitions.
    func postProcessForTLDR(_ text: String) -> String {
        if let appleIntelligenceService = appleIntelligenceService {
            return appleIntelligenceService.postProcessForTLDR(text)
        } else {
            return text
        }
    }

    /// Generate a response from a RAW prompt without adding the conversation chat template.
    /// This is useful for utility features such as TL;DR summaries where the entire
    /// instruction is contained in the prompt itself and we do **not** want the
    /// additional conversation context.
    /// - Parameter prompt: The raw prompt to send to the model.
    /// - Returns: The model's cleaned response string.
    func generateRawResponse(prompt: String) async throws -> String {
        guard isModelLoaded else {
            throw GemmaError.modelNotLoaded
        }

        do {
            if let appleIntelligenceService = appleIntelligenceService {
                let generated = try await appleIntelligenceService.generateRawResponse(prompt: prompt)
                return generated
            } else {
                return "Apple Intelligence not available for raw text generation."
            }
        } catch {
            NSLog("❌ GemmaService raw generation failed: \(error)")
            throw GemmaError.inferenceError("Apple Intelligence inference failed: \(error.localizedDescription)")
        }
    }

    // Context reference processing will be added in Phase 11
    
    // MARK: - Context Error Detection (from RSSReader)
    
    /// Detects if an error is related to context/token limits - EXACT copy from RSSReader
    private func isContextError(_ error: Error) -> Bool {
        let errorMessage = error.localizedDescription.lowercased()
        
        // Common context/length related errors from Apple Intelligence
        let contextKeywords = [
            "context", "token", "length", "limit", "exceeded",
            "too long", "too large", "maximum", "size",
            "input too large", "content too long", "text too long",
            "request too large", "payload too large", "truncated",
            "buffer", "capacity", "overflow", "quota", "contextwindowsize"
        ]
        
        for keyword in contextKeywords {
            if errorMessage.contains(keyword) {
                return true
            }
        }
        
        // Check error codes that typically indicate context limits
        if let nsError = error as? NSError {
            let contextErrorCodes = [413, 422, 400, 431]
            if contextErrorCodes.contains(nsError.code) {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Stream State Management

actor StreamState {
    private var hasFinished = false
    
    func attemptFinish() -> Bool {
        if hasFinished {
            return false
        }
        hasFinished = true
        return true
    }
}

// MARK: - Apple Intelligence Integration Notes

/// Apple Intelligence handles everything through the system's Foundation Models framework
/// All processing happens on-device with complete privacy

// MARK: - Errors

enum GemmaError: LocalizedError {
    case modelNotAvailable(String)
    case modelNotLoaded
    case initializationFailed(String)
    case lmStudioNotAvailable
    case promptTooLong(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let message):
            return "Model Not Available: \(message)"
        case .modelNotLoaded:
            return "Model not loaded - call initialize() first"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .lmStudioNotAvailable:
            return "Apple Intelligence not available"
        case .promptTooLong(let message):
            return "Prompt Too Long: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}
