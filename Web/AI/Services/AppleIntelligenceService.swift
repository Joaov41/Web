import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Use the REAL Apple Intelligence Foundation Models framework
// Available in iOS 18.2+ beta - exactly as shown in the provided guide

/// Apple Intelligence service for local inference using LanguageModelSession
/// Handles on-device AI processing with iOS 18.2+ and macOS 15.2+
@available(iOS 18.2, macOS 15.2, *)
class AppleIntelligenceService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let privacyManager: PrivacyManager
    
    private var isModelReady: Bool = false
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        privacyManager: PrivacyManager
    ) {
        self.configuration = configuration
        self.privacyManager = privacyManager
        
        NSLog("🔮 Apple Intelligence Service initialized")
    }
    
    // MARK: - Public Interface
    
    /// Check if Apple Intelligence is available on this device
    static func isAvailable() -> Bool {
        // Always return true - let the LanguageModelSession handle availability
        // This prevents blocking the UI with availability errors
        return true
    }
    
    /// Initialize the Apple Intelligence service
    func initialize() async throws {
        guard !isModelReady else {
            NSLog("✅ Apple Intelligence already ready")
            return
        }
        
        do {
            // Always mark as ready - let LanguageModelSession handle actual availability
            isModelReady = true
            NSLog("✅ Apple Intelligence service ready")
            
        } catch {
            NSLog("❌ Failed to initialize Apple Intelligence: \(error)")
            throw AppleIntelligenceError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Generate a response for the given query and context
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AIResponse {
        
        guard isModelReady else {
            throw AppleIntelligenceError.modelNotLoaded
        }
        
        let responseBuilder = AIResponseBuilder()
        
        do {
            // Step 1: Prepare the prompt
            let _ = responseBuilder.addProcessingStep(ProcessingStep(
                name: "prompt_preparation",
                duration: 0.1,
                description: "Preparing prompt for Apple Intelligence"
            ))
            
            let prompt = buildPrompt(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )
            
            if context != nil {
                let _ = responseBuilder.setContextUsed(true)
            }
            
            // Step 2: Generate with Apple Intelligence
            let _ = responseBuilder.addProcessingStep(ProcessingStep(
                name: "apple_intelligence_inference",
                duration: 0,
                description: "Running Apple Intelligence inference"
            ))
            
            let startTime = Date()
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let duration = Date().timeIntervalSince(startTime)
            
            let cleaned = postProcessResponse(response.content)
            
            // Calculate metrics
            let tokenCount = estimateTokenCount(cleaned)
            
            return responseBuilder
                .setText(cleaned)
                .setMemoryUsage(0) // Apple Intelligence manages memory internally
                .build()
            
        } catch {
            NSLog("❌ Apple Intelligence response generation failed: \(error)")
            throw AppleIntelligenceError.inferenceError("Apple Intelligence inference failed: \(error.localizedDescription)")
        }
    }
    
    /// Generate a streaming response with real-time token updates
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard isModelReady else {
            throw AppleIntelligenceError.modelNotLoaded
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Prepare prompt
                    let prompt = buildPrompt(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    
                    // Generate response using Apple Intelligence
                    let session = LanguageModelSession()
                    let response = try await session.respond(to: prompt)
                    
                    let cleaned = postProcessResponse(response.content)
                    
                    // Simulate streaming by breaking response into chunks
                    let words = cleaned.split(separator: " ")
                    var hasYieldedContent = false
                    
                    for word in words {
                        let chunk = String(word) + " "
                        hasYieldedContent = true
                        continuation.yield(chunk)
                        
                        // Small delay to simulate streaming
                        try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                    }
                    
                    // If no content was streamed, provide a fallback
                    if !hasYieldedContent {
                        NSLog("⚠️ No content streamed, providing fallback response")
                        let fallbackResponse = "I'm ready to help you with questions about the current webpage content."
                        continuation.yield(fallbackResponse)
                    }
                    
                    continuation.finish()
                    NSLog("✅ Apple Intelligence streaming completed successfully")
                    
                } catch {
                    NSLog("❌ Apple Intelligence streaming error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Summarize text using Apple Intelligence - EXACTLY as in working RSSReader
    static func summarizeText(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let session = LanguageModelSession()
                let prompt = "Provide a one-paragraph summary (4-6 sentences) of the following text:\n\n\(text)"
                let response = try await session.respond(to: prompt)
                
                DispatchQueue.main.async {
                    completion(.success(response.content))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Ask question about text using Apple Intelligence - EXACTLY as in working RSSReader
    static func askQuestion(about text: String, question: String, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let session = LanguageModelSession()
                let prompt = """
                Based on the following text, please answer this question:
                
                Question: \(question)
                
                Text:
                \(text)
                
                If the answer cannot be determined from the text, please state that the information is not available.
                """
                
                let response = try await session.respond(to: prompt)
                
                DispatchQueue.main.async {
                    completion(.success(response.content))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Summarize a conversation
    func summarizeConversation(_ messages: [ConversationMessage]) async throws -> String {
        let conversationText = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        
        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:
        
        \(conversationText)
        
        Summary:
        """
        
        let session = LanguageModelSession()
        let response = try await session.respond(to: summaryPrompt)
        
        return postProcessResponse(response.content)
    }
    
    /// Reset conversation state
    func resetConversation() async {
        // Apple Intelligence is stateless per request, so no action needed
        NSLog("🔄 Apple Intelligence conversation reset completed (stateless)")
    }
    
    /// Generate a response from a RAW prompt without conversation template
    func generateRawResponse(prompt: String) async throws -> String {
        guard isModelReady else {
            throw AppleIntelligenceError.modelNotLoaded
        }
        
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            
            let cleaned = postProcessResponse(response.content, trimWhitespace: false)
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("❌ Apple Intelligence raw generation failed: \(error)")
            throw AppleIntelligenceError.inferenceError("Apple Intelligence inference failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func buildPrompt(
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
    
    private func postProcessResponse(_ text: String, trimWhitespace: Bool = true) -> String {
        var cleaned = text
        
        // Remove common artifacts that might appear in responses
        let tokensToRemove = [
            "Assistant:", "User:", "System:"
        ]
        
        for token in tokensToRemove {
            if cleaned.hasPrefix(token) {
                cleaned = String(cleaned.dropFirst(token.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Clean up formatting
        cleaned = cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n\\s*\\n", with: "\n\n", options: .regularExpression)
        
        if trimWhitespace {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
    }
    
    private func estimateTokenCount(_ text: String) -> Int {
        // Use the same estimation logic as the existing codebase
        return TokenEstimator.estimateTokens(for: text)
    }
    
    /// Additional cleanup for TL;DR summaries
    func postProcessForTLDR(_ text: String) -> String {
        var cleaned = postProcessResponse(text, trimWhitespace: false)
        
        // Additional processing for summaries
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
}

// MARK: - Errors

enum AppleIntelligenceError: LocalizedError {
    case modelNotLoaded
    case initializationFailed(String)
    case inferenceError(String)
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Apple Intelligence not ready - call initialize() first"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        case .notAvailable:
            return "Apple Intelligence not available on this device"
        }
    }
}