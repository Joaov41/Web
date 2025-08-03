import Foundation
import Combine

/// Main AI Assistant coordinator managing local AI capabilities
/// Integrates Apple Intelligence with context management and conversation handling
class AIAssistant: ObservableObject {
    
    // MARK: - Published Properties (Main Actor for UI Updates)
    
    @MainActor @Published var isInitialized: Bool = false
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var initializationStatus: String = "Not initialized"
    @MainActor @Published var lastError: String?
    
    // UNIFIED ANIMATION STATE - prevents conflicts between typing/streaming indicators
    @MainActor @Published var animationState: AIAnimationState = .idle
    @MainActor @Published var streamingText: String = ""
    
    // MARK: - Dependencies
    
    private let privacyManager: PrivacyManager
    private let conversationHistory: ConversationHistory
    private let gemmaService: GemmaService
    private let contextManager: ContextManager
    private let memoryMonitor: SystemMemoryMonitor
    private weak var tabManager: TabManager?
    
    // MARK: - Configuration
    
    private let aiConfiguration: AIConfiguration
    private var cancellables = Set<AnyCancellable>()
    
    
    // MARK: - Initialization
    
    init(tabManager: TabManager? = nil) {
        // Initialize dependencies
        self.privacyManager = PrivacyManager()
        self.conversationHistory = ConversationHistory()
        self.contextManager = ContextManager.shared
        self.memoryMonitor = SystemMemoryMonitor.shared
        self.tabManager = tabManager
        
        // Get optimal configuration for current hardware
        self.aiConfiguration = HardwareDetector.getOptimalAIConfiguration()
        
        // Initialize Gemma service with Apple Intelligence
        self.gemmaService = GemmaService(
            configuration: aiConfiguration,
            privacyManager: privacyManager
        )
        
        // Set up bindings - will be called async in initialize
        NSLog("🤖 AI Assistant initialized with Apple Intelligence")
    }
    
    // MARK: - Public Interface
    
    /// Get current conversation messages for UI display
    var messages: [ConversationMessage] {
        conversationHistory.getRecentMessages()
    }
    
    /// Get message count for UI binding
    var messageCount: Int {
        conversationHistory.messageCount
    }
    
    /// FIXED: Initialize the AI system with safe parallel tasks (race condition fixed)
    func initialize() async {
        updateStatus("Initializing AI system...")
        
        do {
            // Step 1: Validate Apple Intelligence
            updateStatus("Initializing Apple Intelligence...")
            
            NSLog("✅ Apple Intelligence ready")
            
            // Initialize privacy manager
            updateStatus("Setting up privacy protection...")
            try await privacyManager.initialize()
            
            // Initialize Apple Intelligence service
            updateStatus("Starting Apple Intelligence...")
            try await gemmaService.initialize()
            
            // Context processing will be added in Phase 11
            
            // Setup bindings now that everything is initialized
            Task { @MainActor in
                self.setupBindings()
            }
            
            // Mark as initialized
            Task { @MainActor in
                isInitialized = true
                lastError = nil
            }
            updateStatus("AI Assistant ready")
            
            NSLog("✅ AI Assistant initialization completed successfully with Apple Intelligence")
            
        } catch {
            let errorMessage = "AI initialization failed: \(error.localizedDescription)"
            updateStatus("Initialization failed")
            Task { @MainActor in
                lastError = errorMessage
                isInitialized = false
            }
            
            NSLog("❌ \(errorMessage)")
        }
    }
    
    /// Process a user query with current context and optional history
    func processQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) async throws -> AIResponse {
        guard await isInitialized else {
            throw AIError.notInitialized
        }
        
        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIError.memoryPressure("AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)")
        }
        
        Task { @MainActor in isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }
        
        do {
            // Extract context from current webpage with optional history
            let webpageContext = await extractCurrentContext()
            if let webpageContext = webpageContext {
                NSLog("🔍 AIAssistant extracted webpage context: \(webpageContext.text.count) chars, quality: \(webpageContext.contentQuality)")
            } else {
                NSLog("⚠️ AIAssistant: No webpage context extracted")
            }
            
            let context = contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory && includeContext)
            if let context = context {
                NSLog("🔍 AIAssistant formatted context: \(context.count) characters")
            } else {
                NSLog("⚠️ AIAssistant: No formatted context returned")
            }
            
            // Create conversation entry
            let userMessage = ConversationMessage(
                role: .user,
                content: query,
                timestamp: Date(),
                contextData: context
            )
            
            // Add to conversation history
            conversationHistory.addMessage(userMessage)
            
            // Process with Gemma service (reduced history to prevent memory issues)
            let response = try await gemmaService.generateResponse(
                query: query,
                context: context,
                conversationHistory: conversationHistory.getRecentMessages(limit: 4)
            )
            
            // Create AI response message
            let aiMessage = ConversationMessage(
                role: .assistant,
                content: response.text,
                timestamp: Date(),
                metadata: response.metadata
            )
            
            // Add to conversation history
            conversationHistory.addMessage(aiMessage)
            
            // Return response
            return response
            
        } catch {
            NSLog("❌ Query processing failed: \(error)")
            await handleAIError(error)
            throw error
        }
    }
    
    /// Process a streaming query with real-time responses and optional history
    func processStreamingQuery(_ query: String, includeContext: Bool = true, includeHistory: Bool = true) -> AsyncThrowingStream<String, Error> {
        NSLog("🔍 FIXED DEBUG: ✅ ENTRY POINT - processStreamingQuery called with query: '\(query)', includeContext: \(includeContext), includeHistory: \(includeHistory)")
        NSLog("🔍 FIXED DEBUG: Thread info - Main: \(Thread.isMainThread), Current: \(Thread.current)")
        return AsyncThrowingStream { continuation in
            NSLog("🔍 FIXED DEBUG: ✅ Inside AsyncThrowingStream creation")
            Task {
                NSLog("🔍 FIXED DEBUG: ✅ Inside AsyncThrowingStream Task")
                do {
                    NSLog("🔍 FIXED DEBUG: Checking if initialized")
                    guard await isInitialized else {
                        NSLog("🔍 FIXED DEBUG: Not initialized, throwing error")
                        throw AIError.notInitialized
                    }
                    NSLog("🔍 FIXED DEBUG: Initialized check passed")
                    
                    // RACE CONDITION FIX: Remove isProcessing guard entirely
                    // This allows multiple requests but prevents the blocking issue
                    Task { @MainActor in isProcessing = true }
                    defer { Task { @MainActor in isProcessing = false } }
                    
                    // Extract context from current webpage with optional history
                    let webpageContext = await self.extractCurrentContext()
                    if let webpageContext = webpageContext {
                        NSLog("🔍 FIXED DEBUG: extracted webpage context: \(webpageContext.text.count) chars, quality: \(webpageContext.contentQuality)")
                    } else {
                        NSLog("⚠️ FIXED DEBUG: No webpage context extracted")
                    }
                    
                    let context = self.contextManager.getFormattedContext(from: webpageContext, includeHistory: includeHistory && includeContext)
                    if let context = context {
                        NSLog("🔍 FIXED DEBUG: formatted context: \(context.count) characters")
                    } else {
                        NSLog("⚠️ FIXED DEBUG: No formatted context returned")
                    }
                    
                    // Process with streaming (reduced history to prevent memory issues)
                    NSLog("🔍 FIXED DEBUG: About to call gemmaService.generateStreamingResponse")
                    NSLog("🔍 FIXED DEBUG: Query: '\(query)', Context length: \(context?.count ?? 0), History count: \(conversationHistory.getRecentMessages(limit: 4).count)")
                    let stream = try await gemmaService.generateStreamingResponse(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory.getRecentMessages(limit: 4)
                    )
                    NSLog("🔍 FIXED DEBUG: generateStreamingResponse call completed, got stream")
                    
                    // Add user message first
                    let userMessage = ConversationMessage(
                        role: .user,
                        content: query,
                        timestamp: Date(),
                        contextData: context
                    )
                    conversationHistory.addMessage(userMessage)
                    
                    // CRITICAL FIX: Add empty AI message for UI streaming but will be updated
                    let aiMessage = ConversationMessage(
                        role: .assistant,
                        content: "", // Start empty for streaming
                        timestamp: Date()
                    )
                    conversationHistory.addMessage(aiMessage)
                    
                    // Set up unified streaming animation state
                    await MainActor.run {
                        animationState = .streaming(messageId: aiMessage.id)
                        streamingText = ""
                    }
                    
                    var fullResponse = ""
                    let fullResponseBox = Box("")
                    var chunkCount = 0
                    let maxChunks = 500 // Prevent infinite streaming
                    let startTime = Date()
                    let maxDuration: TimeInterval = 60 // 60 second timeout
                    
                    for try await chunk in stream {
                        chunkCount += 1
                        let elapsed = Date().timeIntervalSince(startTime)
                        
                        // Safety checks to prevent infinite loops/memory issues
                        if chunkCount > maxChunks {
                            NSLog("⚠️ Streaming exceeded max chunks (\(maxChunks)), terminating")
                            break
                        }
                        
                        if elapsed > maxDuration {
                            NSLog("⚠️ Streaming exceeded timeout (\(maxDuration)s), terminating")
                            break
                        }
                        
                        if fullResponseBox.value.count > 20000 {
                            NSLog("⚠️ Response too long (\(fullResponseBox.value.count) chars), truncating")
                            break
                        }
                        
                        fullResponseBox.value += chunk
                        fullResponse = fullResponseBox.value
                        
                        // Update UI streaming text
                        await MainActor.run {
                            streamingText = fullResponseBox.value
                        }
                        
                        continuation.yield(chunk)
                    }
                    
                    // Update the empty message with the final streamed content
                    conversationHistory.updateMessage(id: aiMessage.id, newContent: fullResponse)
                    
                    // Clear unified animation state when done with more aggressive cleanup
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                        // Ensure processing flag resets so UI updates status correctly
                        self.isProcessing = false
                    }
                    
                    // STREAMING FIX: Add small delay to ensure UI state settles
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    
                    // STREAMING FIX: Force cleanup any lingering async operations
                    await Task.yield()
                    
                    // FIX: Double-check animation state is idle before finishing
                    if await animationState != .idle {
                        NSLog("⚠️ STREAMING FIX: Animation state was not idle after streaming, forcing reset")
                        await MainActor.run {
                            animationState = .idle
                            streamingText = ""
                            isProcessing = false
                        }
                    }
                    
                    continuation.finish()
                    
                    NSLog("🔍 HANG DEBUG: ✅ Stream finished and state cleaned up completely")
                    
                } catch {
                    NSLog("❌ Streaming error occurred: \(error)")
                    
                    // Get the message ID before clearing state
                    let messageId = await animationState.streamingMessageId
                    
                    // Clear unified animation state on error with more aggressive cleanup
                    await MainActor.run {
                        animationState = .idle
                        streamingText = ""
                        isProcessing = false // Ensure processing flag is cleared
                    }
                    
                    // STREAMING FIX: Add delay to ensure state settles before error handling
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    
                    // If we have a partially complete message, update it with error info
                    if let messageId = messageId {
                        conversationHistory.updateMessage(
                            id: messageId, 
                            newContent: "Sorry, there was an error generating the response. Please try again."
                        )
                    }
                    
                    await self.handleAIError(error)
                    
                    // STREAMING FIX: Don't throw the error, just finish cleanly to prevent UI hangs
                    continuation.finish()
                }
            }
        }
    }
    
    /// Get conversation summary for the current session
    func getConversationSummary() async throws -> String {
        let messages = conversationHistory.getRecentMessages(limit: 20)
        return try await gemmaService.summarizeConversation(messages)
    }
    
    /// Generate TL;DR summary of current page content without affecting conversation history
    func generatePageTLDR() async throws -> String {
        guard await isInitialized else {
            throw AIError.notInitialized
        }
        
        // CONCURRENCY SAFETY: Check if AI is already processing to avoid conflicts
        let currentlyProcessing = await MainActor.run { isProcessing }
        guard !currentlyProcessing else {
            throw AIError.inferenceError("AI is currently busy with another task")
        }
        
        // MEMORY SAFETY: Check if AI operations are safe to perform
        guard memoryMonitor.isAISafeToRun() else {
            let memoryStatus = memoryMonitor.getCurrentMemoryStatus()
            throw AIError.memoryPressure("AI operations suspended due to \(memoryStatus.pressureLevel.rawValue.lowercased()) memory pressure (\(String(format: "%.1f", memoryStatus.availableMemory))GB available)")
        }
        
        // Extract context from current webpage
        let webpageContext = await extractCurrentContext()
        guard let context = webpageContext, !context.text.isEmpty else {
            NSLog("⚠️ TL;DR: No context available - webpageContext: \(webpageContext != nil ? "exists but empty" : "nil")")
            throw AIError.contextProcessingFailed("No content available to summarize")
        }
        
        NSLog("🔍 TL;DR: Using context with \(context.text.count) characters, quality: \(context.contentQuality)")
        
        // Create improved TL;DR prompt with email detection
        let isEmail = context.title.lowercased().contains("mail") || 
                     context.title.lowercased().contains("inbox") ||
                     context.text.lowercased().contains("from:") ||
                     context.text.lowercased().contains("to:") ||
                     context.text.lowercased().contains("subject:")
        
        let contentText = String(context.text.prefix(8000))
        NSLog("🔍 [TL;DR-AIAssistant] Using context: \(contentText.count) chars - '\(String(contentText.prefix(200)))...'")
        
        let tldrPrompt = """
        Provide a brief, clear summary of the following content. \(isEmail ? "This appears to be an email - focus on the sender, main message, and any action items or deadlines." : "Focus on the main points and key information.")

        Instructions:
        - Write in plain text only (no HTML, markdown, or special formatting)
        - Keep summary to 2-4 sentences maximum
        - Be specific and factual
        \(isEmail ? "- For emails: mention sender, purpose, and any required actions or responses" : "- Highlight the most important or actionable information")
        - Use clear, concise language

        Title: \(context.title)
        Content: \(contentText)
        
        Summary:
        """

        do {
            // Use RAW prompt generation to avoid chat template noise
            let cleanResponse = try await gemmaService.generateRawResponse(prompt: tldrPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // VALIDATION: Check for repetitive or broken output
            if isInvalidTLDRResponse(cleanResponse) {
                NSLog("⚠️ Invalid TL;DR response detected, retrying with simplified prompt")
                
                // Fallback with simpler prompt
                let fallbackPrompt = "Summarize this content in 2-3 clear sentences (plain text only):\n\nTitle: \(context.title)\nContent: \(context.text.prefix(5000))\n\nSummary:"
                let fallbackClean = try await gemmaService.generateRawResponse(prompt: fallbackPrompt).trimmingCharacters(in: .whitespacesAndNewlines)

                // If fallback is still invalid, attempt a final post-processing pass that collapses
                // repeated phrases to salvage the summary before giving up.
                if isInvalidTLDRResponse(fallbackClean) {
                    let salvaged = gemmaService.postProcessForTLDR(fallbackClean)
                    return isInvalidTLDRResponse(salvaged) ? "Unable to generate summary" : salvaged
                }

                return fallbackClean
            }
            
            return cleanResponse

        } catch {
            NSLog("❌ TL;DR generation failed: \(error)")
            throw AIError.inferenceError("Failed to generate TL;DR: \(error.localizedDescription)")
        }
    }
    
    /// Check if TL;DR response contains repetitive or invalid patterns
    private func isInvalidTLDRResponse(_ response: String) -> Bool {
        let lowercased = response.lowercased()
        
        // Check for repetitive patterns that indicate model confusion
        let badPatterns = [
            "understand",
            "i'll help",
            "please provide",
            "let me know",
            "what can i do"
        ]
        
        // If response is too short or contains too many repetitive words
        if response.count < 20 {
            return true
        }
        
        // Detect obvious HTML or code fragments which indicate a bad summary
        if lowercased.contains("<html") || lowercased.contains("<div") || lowercased.contains("<span") {
            return true
        }

        // Detect repeated adjacent words (e.g. "it it", "you you") which are a signal
        // of token duplication errors during generation.
        if lowercased.range(of: "\\b(\\w+)(\\s+\\1)+\\b", options: .regularExpression) != nil {
            return true
        }

        // NEW: Detect **phrase**-level repetition where a 3-6-word chunk is repeated
        // three or more times consecutively (e.g. "The provided text" pattern).
        // This catches progressive prefix repetition that isn't matched by the
        // simple duplicate-word regex above.
        do {
            let phrasePattern = "(\\b(?:\\w+\\s+){2,5}\\w+\\b)(?:\\s+\\1){2,}"
            if lowercased.range(of: phrasePattern, options: [.regularExpression]) != nil {
                return true
            }
        }
        catch {
            NSLog("⚠️ Regex error in phrase repetition detection: \(error)")
        }

        // Check for excessive repetition of bad patterns
        for pattern in badPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Clear conversation history and context
    func clearConversation() {
        conversationHistory.clear()
        
        // Reset Gemma service conversation state
        Task {
            await gemmaService.resetConversation()
        }
        
        NSLog("🗑️ Conversation cleared")
    }
    
    /// Reset AI conversation state to recover from errors
    func resetConversationState() async {
        // Clear conversation history
        conversationHistory.clear()
        
        // Reset LLM conversation state to prevent KV cache issues
        await gemmaService.resetConversation()
        
        await MainActor.run {
            lastError = nil
            isProcessing = false
        }
        
        NSLog("🔄 AI conversation state fully reset for error recovery")
    }
    
    /// Handle AI errors with automatic recovery
    private func handleAIError(_ error: Error) async {
        let errorMessage = error.localizedDescription
        NSLog("❌ AI Error occurred: \(errorMessage)")
        
        await MainActor.run {
            lastError = errorMessage
            isProcessing = false
        }
        
        // Auto-recovery for common errors
        if errorMessage.contains("inconsistent sequence positions") ||
           errorMessage.contains("KV cache") ||
           errorMessage.contains("decode") {
            NSLog("🔄 Detected conversation state error, attempting auto-recovery...")
            await resetConversationState()
        }
    }
    
    /// Check if AI system is in a healthy state
    func performHealthCheck() async -> Bool {
        do {
            // Test if the AI system can handle a simple query
            let testQuery = "Hello"
            let _ = try await processQuery(testQuery, includeContext: false)
            return true
        } catch {
            NSLog("⚠️ AI Health check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Configure history context settings
    func configureHistoryContext(enabled: Bool, scope: HistoryContextScope) {
        contextManager.configureHistoryContext(enabled: enabled, scope: scope)
        NSLog("🔍 AI Assistant history context configured: enabled=\(enabled), scope=\(scope.displayName)")
    }
    
    /// Get current history context status
    func getHistoryContextStatus() -> (enabled: Bool, scope: HistoryContextScope) {
        return (contextManager.isHistoryContextEnabled, contextManager.historyContextScope)
    }
    
    /// Clear history context for privacy
    func clearHistoryContext() {
        contextManager.clearHistoryContextCache()
        NSLog("🗑️ AI Assistant history context cleared")
    }
    
    /// Get current system status
    @MainActor func getSystemStatus() -> AISystemStatus {
        let historyContextInfo = getHistoryContextStatus()
        
        return AISystemStatus(
            isInitialized: isInitialized,
            framework: aiConfiguration.framework,
            modelVariant: aiConfiguration.modelVariant,
            memoryUsage: 0, // Apple Intelligence manages memory internally
            inferenceSpeed: 0.0, // Apple Intelligence manages inference speed
            contextTokenCount: 0, // Context processing will be added in Phase 11
            conversationLength: conversationHistory.messageCount,
            hardwareInfo: HardwareDetector.processorType.description,
            historyContextEnabled: historyContextInfo.enabled,
            historyContextScope: historyContextInfo.scope.displayName
        )
    }
    
    // MARK: - Private Methods
    
    private func extractCurrentContext() async -> WebpageContext? {
        guard let tabManager = tabManager else {
            NSLog("⚠️ TabManager not available for context extraction")
            return nil
        }
        
        return await contextManager.extractCurrentPageContext(from: tabManager)
    }
    
    private func validateHardware() throws {
        // Apple Intelligence requires compatible hardware
        guard HardwareDetector.totalMemoryGB >= 4 else {
            throw AIError.insufficientMemory("Minimum 4GB RAM required for Apple Intelligence")
        }
    }
    
    @MainActor
    private func setupBindings() {
        // Bind conversation history changes - SwiftUI automatically handles UI updates for @Published properties
        conversationHistory.$messageCount
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // SwiftUI automatically triggers UI updates when @Published properties change
                // Removed manual objectWillChange.send() to prevent unnecessary re-renders
            }
            .store(in: &cancellables)
        
        // Apple Intelligence status is handled internally by the system
    }
    
    private func updateStatus(_ status: String) {
        Task { @MainActor in
            initializationStatus = status
        }
        NSLog("🤖 AI Status: \(status)")
    }
}

// MARK: - Supporting Types

/// Unified animation state for AI responses to prevent conflicts
enum AIAnimationState: Equatable {
    case idle
    case typing
    case streaming(messageId: String)
    case processing
    
    var isActive: Bool {
        switch self {
        case .idle:
            return false
        case .typing, .streaming, .processing:
            return true
        }
    }
    
    var isStreaming: Bool {
        if case .streaming = self {
            return true
        }
        return false
    }
    
    var streamingMessageId: String? {
        if case .streaming(let messageId) = self {
            return messageId
        }
        return nil
    }
}

/// AI system status information
struct AISystemStatus {
    let isInitialized: Bool
    let framework: AIConfiguration.Framework
    let modelVariant: AIConfiguration.ModelVariant
    let memoryUsage: Int // MB
    let inferenceSpeed: Double // tokens/second
    let contextTokenCount: Int
    let conversationLength: Int
    let hardwareInfo: String
    let historyContextEnabled: Bool
    let historyContextScope: String
}

/// AI specific errors
enum AIError: LocalizedError {
    case notInitialized
    case unsupportedHardware(String)
    case insufficientMemory(String)
    case memoryPressure(String)
    case modelNotAvailable
    case contextProcessingFailed(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "AI Assistant not initialized"
        case .unsupportedHardware(let message):
            return "Unsupported Hardware: \(message)"
        case .insufficientMemory(let message):
            return "Insufficient Memory: \(message)"
        case .memoryPressure(let message):
            return "Memory Pressure: \(message)"
        case .modelNotAvailable:
            return "AI model not available"
        case .contextProcessingFailed(let message):
            return "Context Processing Failed: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
    
}

/// Conversation message roles
enum ConversationRole: String, Codable {
    case user
    case assistant
    case system
}
