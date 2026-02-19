import Foundation

enum DeepLinkRoute: Equatable {
    case open
    case skill(id: String)
}

enum DeepLinkParser {
    static func parse(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme == "skillssync" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.host {
        case "open":
            return .open
        case "skill":
            guard let skillID = components.queryItems?.first(where: { $0.name == "id" })?.value, !skillID.isEmpty else {
                return nil
            }
            return .skill(id: skillID)
        default:
            return nil
        }
    }
}
