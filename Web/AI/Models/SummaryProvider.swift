import Foundation

/// Summary provider selection enum - matching RSSReader implementation exactly
enum SummaryProvider: String, CaseIterable {
    case gemini = "Gemini"
    case appleLocal = "Apple Local"
    case appleCloud = "Apple Cloud"
    
    var displayName: String {
        switch self {
        case .gemini:
            return "Gemini API"
        case .appleLocal:
            return "Apple Intelligence (Local)"
        case .appleCloud:
            return "Apple Intelligence (Cloud)"
        }
    }
}

/// Request type classification for Apple Intelligence
enum AppleIntelligenceRequestType {
    case summary
    case articleQA
    case redditQA
    case commentSummary
}