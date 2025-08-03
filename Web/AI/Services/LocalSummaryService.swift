import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Local Apple Intelligence service using LanguageModelSession
/// Direct implementation matching the working RSSReader codebase
@available(iOS 18.2, macOS 15.2, *)
class LocalSummaryService {
    
    // Check if Apple Intelligence is available on this device
    static func isAvailable() -> Bool {
        // Always return true - let LanguageModelSession handle availability
        // This prevents blocking functionality with availability errors
        return true
    }
    
    // Summarize text using on-device model - EXACT copy from working RSSReader
    static func summarizeText(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Add timeout handling to prevent hanging - increased to 60 seconds for Apple Intelligence
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 second timeout
            DispatchQueue.main.async {
                completion(.failure(LocalSummaryError.modelNotReady))
            }
        }
        
        Task {
            do {
                let session = LanguageModelSession()
                let prompt = "Provide a one-paragraph summary (4-6 sentences) of the following text:\n\n\(text)"
                let response = try await session.respond(to: prompt)
                
                // Cancel timeout since we got a response
                timeoutTask.cancel()
                
                DispatchQueue.main.async {
                    completion(.success(response.content))
                }
            } catch {
                // Cancel timeout since we got an error
                timeoutTask.cancel()
                
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Ask question about text using on-device model - EXACT copy from working RSSReader
    static func askQuestion(about text: String, question: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Add timeout handling to prevent hanging - increased to 60 seconds for Apple Intelligence
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 second timeout
            DispatchQueue.main.async {
                completion(.failure(LocalSummaryError.modelNotReady))
            }
        }
        
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
                
                // Cancel timeout since we got a response
                timeoutTask.cancel()
                
                DispatchQueue.main.async {
                    completion(.success(response.content))
                }
            } catch {
                // Cancel timeout since we got an error
                timeoutTask.cancel()
                
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

enum LocalSummaryError: LocalizedError {
    case notAvailable
    case notYetImplemented
    case modelNotReady
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device. Please use Cloud or Gemini instead."
        case .notYetImplemented:
            return "On-device AI is coming soon. Please use Cloud or Gemini for now."
        case .modelNotReady:
            return "The on-device model is not ready. Please try again later."
        }
    }
}
