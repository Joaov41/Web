import Foundation

/// LM Studio AI service for local inference via HTTP API
/// Handles model communication and response streaming using LM Studio's OpenAI-compatible API
class LMStudioService {
    
    // MARK: - Properties
    
    private let configuration: AIConfiguration
    private let privacyManager: PrivacyManager
    private let baseURL = "http://localhost:1234/v1"
    private let modelName = "gemma-3n-e4b-it-text"
    
    private var isModelReady: Bool = false
    
    // MARK: - Initialization
    
    init(
        configuration: AIConfiguration,
        privacyManager: PrivacyManager
    ) {
        self.configuration = configuration
        self.privacyManager = privacyManager
        
        NSLog("🔮 LM Studio Service initialized with model: \(modelName)")
    }
    
    // MARK: - Public Interface
    
    /// Initialize the LM Studio connection
    func initialize() async throws {
        guard !isModelReady else {
            NSLog("✅ LM Studio model already ready")
            return
        }
        
        do {
            // Check if LM Studio is available and the model is loaded
            try await checkModelAvailability()
            
            isModelReady = true
            NSLog("✅ LM Studio model ready successfully")
            
        } catch {
            NSLog("❌ Failed to initialize LM Studio model: \(error)")
            throw LMStudioError.initializationFailed(error.localizedDescription)
        }
    }
    
    /// Generate a response for the given query and context
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AIResponse {
        
        guard isModelReady else {
            throw LMStudioError.modelNotLoaded
        }
        
        let responseBuilder = AIResponseBuilder()
        
        do {
            // Step 1: Prepare the messages
            let _ = responseBuilder.addProcessingStep(ProcessingStep(
                name: "message_preparation",
                duration: 0.1,
                description: "Preparing chat messages with context"
            ))
            
            let messages = try buildMessages(
                query: query,
                context: context,
                conversationHistory: conversationHistory
            )
            
            if context != nil {
                let _ = responseBuilder.setContextUsed(true)
            }
            
            // Use LM Studio API for inference
            let _ = responseBuilder.addProcessingStep(ProcessingStep(name: "lm_studio_inference", duration: 0, description: "Running LM Studio API inference"))

            do {
                let generatedText = try await performChatCompletion(messages: messages)
                let cleaned = postProcessResponse(generatedText)
                // Estimate token count for metrics
                let estimatedTokens = Int(Double(generatedText.count) / 3.5)
                return responseBuilder.setText(cleaned).setMemoryUsage(0).build()
            } catch {
                NSLog("❌ LM Studio inference failed: \(error)")
                throw LMStudioError.inferenceError("LM Studio inference failed: \(error.localizedDescription)")
            }
            
        } catch {
            NSLog("❌ Response generation failed: \(error)")
            throw error
        }
    }
    
    /// Generate a streaming response with real-time token updates
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) async throws -> AsyncThrowingStream<String, Error> {
        
        guard isModelReady else {
            throw LMStudioError.modelNotLoaded
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Prepare messages
                    let messages = try buildMessages(
                        query: query,
                        context: context,
                        conversationHistory: conversationHistory
                    )
                    
                    // Use LM Studio API for streaming
                    let textStream = try await performStreamingChatCompletion(messages: messages)
                    
                    var hasYieldedContent = false
                    var accumulatedResponse = ""
                    
                    do {
                        for try await textChunk in textStream {
                            // Clean the chunk minimally for streaming
                            var cleanedChunk = textChunk
                            
                            // Only remove obvious control tokens, preserve whitespace
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<|endoftext|>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<start_of_turn>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<end_of_turn>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<bos>", with: "")
                            cleanedChunk = cleanedChunk.replacingOccurrences(of: "<eos>", with: "")
                            
                            // Always yield the chunk even if it's just whitespace/line breaks
                            accumulatedResponse += cleanedChunk
                            hasYieldedContent = true
                            continuation.yield(cleanedChunk)
                        }
                        
                        // If no content was streamed, provide a helpful fallback
                        if !hasYieldedContent {
                            NSLog("⚠️ No content streamed, providing fallback response")
                            let fallbackResponse = "I'm ready to help you with questions about the current webpage content."
                            continuation.yield(fallbackResponse)
                        }
                        
                        continuation.finish()
                        NSLog("✅ Streaming completed successfully: \(accumulatedResponse.count) characters")
                        
                    } catch {
                        NSLog("❌ Streaming error: \(error)")
                        
                        // Provide error recovery with helpful message
                        if !hasYieldedContent {
                            let recoveryMessage: String
                            if error.localizedDescription.contains("connection") {
                                recoveryMessage = "Cannot connect to LM Studio. Please ensure LM Studio is running on localhost:1234."
                            } else if error.localizedDescription.contains("timeout") {
                                recoveryMessage = "AI response timed out. Please try a more specific question."
                            } else {
                                recoveryMessage = "AI service temporarily unavailable. Please check LM Studio connection."
                            }
                            continuation.yield(recoveryMessage)
                        }
                        
                        continuation.finish()
                    }
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Summarize a conversation
    func summarizeConversation(_ messages: [ConversationMessage]) async throws -> String {
        let conversationText = messages.map { "\($0.role.description): \($0.content)" }.joined(separator: "\n")
        
        let summaryPrompt = """
        Summarize the following conversation in 2-3 sentences, focusing on the main topics and outcomes:
        
        \(conversationText)
        
        Summary:
        """
        
        let response = try await generateResponse(
            query: summaryPrompt,
            context: nil,
            conversationHistory: []
        )
        
        return response.text
    }
    
    /// Reset conversation state
    func resetConversation() async {
        // LM Studio is stateless, so no action needed
        NSLog("🔄 LM Studio conversation reset completed (stateless)")
    }
    
    /// Generate a response from a RAW prompt without adding the conversation chat template
    func generateRawResponse(prompt: String) async throws -> String {
        guard isModelReady else {
            throw LMStudioError.modelNotLoaded
        }

        do {
            // Create a simple system message with the raw prompt
            let messages = [
                ["role": "user", "content": prompt]
            ]
            
            let generated = try await performChatCompletion(messages: messages)
            let cleaned = postProcessResponse(generated, trimWhitespace: false)
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("❌ LM Studio raw generation failed: \(error)")
            throw LMStudioError.inferenceError("LM Studio inference failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func checkModelAvailability() async throws {
        let url = URL(string: "\(baseURL)/models")!
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw LMStudioError.connectionFailed("LM Studio not responding on \(baseURL)")
            }
            
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            
            // Check if our target model is available
            let availableModels = modelsResponse.data.map { $0.id }
            if !availableModels.contains(modelName) {
                NSLog("⚠️ Model \(modelName) not found. Available models: \(availableModels)")
                // Continue anyway - LM Studio might still work with the loaded model
            }
            
            NSLog("✅ LM Studio connection verified. Available models: \(availableModels)")
            
        } catch {
            throw LMStudioError.connectionFailed("Failed to connect to LM Studio: \(error.localizedDescription)")
        }
    }
    
    private func buildMessages(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage]
    ) throws -> [[String: String]] {
        
        // CRITICAL FIX: Limit conversation history to prevent exponential memory growth
        let maxHistoryMessages = 6 // Only include last 3 exchanges (6 messages)
        let recentHistory = Array(conversationHistory.suffix(maxHistoryMessages))
        
        // Validate conversation history
        let validatedHistory = recentHistory.filter { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let isValid = !content.isEmpty && content.count > 2 && content.count < 10000 // Also limit message size
            
            if !isValid {
                NSLog("⚠️ Filtered out invalid/oversized message: '\(message.content.prefix(50))...'")
            }
            
            return isValid
        }
        
        NSLog("📝 Conversation validation: \(conversationHistory.count) → \(recentHistory.count) → \(validatedHistory.count) messages")
        
        var messages: [[String: String]] = []
        
        // System prompt
        messages.append([
            "role": "system",
            "content": "You are a helpful assistant. Answer questions based on provided webpage content."
        ])
        
        // Add recent conversation history for continuity (already limited above)
        for message in validatedHistory {
            if message.role == .user {
                messages.append([
                    "role": "user",
                    "content": message.content
                ])
            } else if message.role == .assistant {
                messages.append([
                    "role": "assistant",
                    "content": message.content
                ])
            }
        }
        
        // Dynamic context limit: more content for first question, less for subsequent questions
        let contextLimit = validatedHistory.isEmpty ? 15000 : 6000
        NSLog("📝 Using context limit: \(contextLimit) chars (first question: \(validatedHistory.isEmpty))")
        
        // Current user message with context
        var userMessage = query
        if let context = context, !context.isEmpty {
            let cleanContext = String(context.prefix(contextLimit))
                .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            NSLog("📝 Context truncated: \(context.count) → \(cleanContext.count) chars")
            userMessage = "WEBPAGE CONTENT:\n\(cleanContext)\n\n---\n\nBased on the above webpage content, please answer: \(query)"
        }
        
        messages.append([
            "role": "user",
            "content": userMessage
        ])
        
        NSLog("📝 Built LM Studio messages (\(messages.count) total) with context: \(context != nil ? "YES (\(context!.count) chars)" : "NO")")
        
        return messages
    }
    
    private func performChatCompletion(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("lm-studio", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0 // 30 second timeout
        
        let payload: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 512,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LMStudioError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        
        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let choice = completionResponse.choices.first,
              let content = choice.message.content else {
            throw LMStudioError.invalidResponse("No content in response")
        }
        
        return content
    }
    
    private func performStreamingChatCompletion(messages: [[String: String]]) async throws -> AsyncThrowingStream<String, Error> {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("lm-studio", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60.0 // 60 second timeout for streaming
        
        let payload: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 512,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Create a custom URLSession with timeout configuration
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 60.0
                    config.timeoutIntervalForResource = 120.0
                    let session = URLSession(configuration: config)
                    
                    let (asyncBytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LMStudioError.apiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                        return
                    }
                    
                    var chunkCount = 0
                    let maxChunks = 1000 // Prevent infinite loops
                    
                    for try await line in asyncBytes.lines {
                        chunkCount += 1
                        if chunkCount > maxChunks {
                            NSLog("⚠️ LM Studio streaming exceeded max chunks, terminating")
                            break
                        }
                        
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            
                            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                                break
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let streamResponse = try? JSONDecoder().decode(ChatCompletionStreamResponse.self, from: data),
                               let choice = streamResponse.choices.first,
                               let content = choice.delta.content {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func postProcessResponse(_ text: String, trimWhitespace: Bool = true) -> String {
        // Clean up the response
        var cleaned = text
        
        // Remove common artifacts and control tokens
        cleaned = cleaned.replacingOccurrences(of: "<|endoftext|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|user|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<|assistant|>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<start_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<end_of_turn>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<bos>", with: "")
        cleaned = cleaned.replacingOccurrences(of: "<eos>", with: "")
        
        // Stop generation at repetitive patterns
        if cleaned.contains("I am sorry, I do not have access") {
            if let range = cleaned.range(of: "I am sorry, I do not have access") {
                let beforeRepetition = cleaned[..<range.lowerBound]
                if !beforeRepetition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleaned = String(beforeRepetition)
                } else {
                    cleaned = "I can help you with questions about the current webpage content."
                }
            }
        }
        
        // Remove excessive repetition by looking for identical sentences
        let sentences = cleaned.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var uniqueSentences: [String] = []
        var seenSentences = Set<String>()
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !seenSentences.contains(trimmed) {
                uniqueSentences.append(sentence)
                seenSentences.insert(trimmed)
            }
        }
        
        if uniqueSentences.count < sentences.count {
            cleaned = uniqueSentences.joined(separator: ".\n")
        }

        // Collapse repeated adjacent words
        do {
            let pattern = "\\b(\\w+)(?:\\s+\\1)+\\b"
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "$1")
        } catch {
            NSLog("⚠️ Regex error while collapsing repeated words: \(error)")
        }

        // Collapse repeated adjacent words without spaces
        do {
            let patternNoSpace = "\\b(\\w{1,20}?)\\1+\\b"
            let regexNoSpace = try NSRegularExpression(pattern: patternNoSpace, options: [.caseInsensitive])
            let rangeNoSpace = NSRange(location: 0, length: cleaned.utf16.count)
            cleaned = regexNoSpace.stringByReplacingMatches(in: cleaned, options: [], range: rangeNoSpace, withTemplate: "$1 ")
        } catch {
            NSLog("⚠️ Regex error while collapsing repeated words without space: \(error)")
        }

        // Ensure proper Markdown formatting
        cleaned = cleaned
            .replacingOccurrences(of: "(?<=:)\\s*\\*", with: "\n* ", options: .regularExpression)
            .replacingOccurrences(of: "(?<![\\n])([*+-]\\s+)", with: "\n$1", options: .regularExpression)
            .replacingOccurrences(of: "(?<![\\n])(#+\\s+)", with: "\n$1", options: .regularExpression)
            .replacingOccurrences(of: "(?<![\\n])(```)", with: "\n$1", options: .regularExpression)
 
        // Dynamic response length based on memory availability
        let memoryPressure = ProcessInfo.processInfo.thermalState
        let maxResponseLength: Int
        
        switch memoryPressure {
        case .critical:
            maxResponseLength = 1000
        case .serious:
            maxResponseLength = 2500
        case .fair:
            maxResponseLength = 4000
        case .nominal:
            maxResponseLength = 6000
        @unknown default:
            maxResponseLength = 2500
        }
        
        // Only limit if significantly over the threshold
        if cleaned.count > Int(Double(maxResponseLength) * 1.25) {
            if let range = cleaned.range(of: ".", range: cleaned.startIndex..<cleaned.index(cleaned.startIndex, offsetBy: min(maxResponseLength, cleaned.count))) {
                cleaned = String(cleaned[..<range.upperBound])
            } else {
                cleaned = String(cleaned.prefix(maxResponseLength)) + "..."
            }
            NSLog("📏 Response truncated to \(cleaned.count) chars due to \(memoryPressure) memory pressure")
        }
        
        if trimWhitespace {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return cleaned
    }

    /// Additional cleanup pass for TL;DR summaries
    func postProcessForTLDR(_ text: String) -> String {
        var cleaned = text

        cleaned = postProcessResponse(cleaned, trimWhitespace: false)

        let phrasePattern = "(\\b(?:[A-Za-z0-9]+\\s+){2,5}[A-Za-z0-9]+\\b)(?:\\s+\\1)+"

        do {
            let regex = try NSRegularExpression(pattern: phrasePattern, options: [.caseInsensitive])
            var previous: String
            repeat {
                previous = cleaned
                let range = NSRange(location: 0, length: cleaned.utf16.count)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "$1")
            } while previous != cleaned
        } catch {
            NSLog("⚠️ Regex error while collapsing repeated phrases: \(error)")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Types

struct ModelsResponse: Codable {
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let id: String
    let object: String
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String?
    let role: String
}

struct ChatCompletionStreamResponse: Codable {
    let choices: [StreamChoice]
}

struct StreamChoice: Codable {
    let delta: Delta
}

struct Delta: Codable {
    let content: String?
}

// MARK: - Errors

enum LMStudioError: LocalizedError {
    case modelNotLoaded
    case connectionFailed(String)
    case initializationFailed(String)
    case apiError(String)
    case invalidResponse(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "LM Studio model not loaded - call initialize() first"
        case .connectionFailed(let message):
            return "Connection Failed: \(message)"
        case .initializationFailed(let message):
            return "Initialization Failed: \(message)"
        case .apiError(let message):
            return "API Error: \(message)"
        case .invalidResponse(let message):
            return "Invalid Response: \(message)"
        case .inferenceError(let message):
            return "Inference Error: \(message)"
        }
    }
}