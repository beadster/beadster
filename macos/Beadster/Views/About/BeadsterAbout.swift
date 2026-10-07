// beadster's composition of the family's shared About card, feedback and Apps list
// (common/swift-packages/AppCatalog), as FlareSync and folder.dev compose theirs. Nothing
// family-wide lives here: the catalog is the one list of apps, never typed by hand.
import AppCatalog
import AppKit
import SwiftUI

enum BeadsterAbout {
    static let site = URL(string: "https://beadster.ai")
    /// The address the 1.x app wrote to.
    static let email = "hi@beadster.ai"

    /// "2.0 (16)": the short version with the build behind it.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "2.0"
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    static var model: AboutCardModel {
        // not the bundle's display name: that is the store listing's "Beadster: Issue Tracking"
        AboutCardModel(appName: "beadster", version: version, site: site)
    }

    static func actions() -> AboutFeedbackActions {
        AboutFeedbackActions(
            rate: { if let url = AppCatalog.app("beadster").flatMap(AppStoreLink.writeReviewURL(for:)) { NSWorkspace.shared.open(url) } },
            issue: { mail("beadster issue") },
            idea: { mail("beadster idea") },
            question: { mail("beadster question") })
    }

    static func mail(_ subject: String) {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = email
        parts.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }
}

/// beadster › About beadster: the shared card in its own small window.
struct AboutWindow: View {
    var body: some View {
        // the card names the app and its version: the window shows no title of its own
        AboutCard(model: BeadsterAbout.model, feedback: BeadsterAbout.actions())
            .padding(20)
            .frame(width: 400)
            .fixedSize(horizontal: false, vertical: true)
            .toolbar(removing: .title)
    }
}

/// Help › More Apps: the rest of the family, with the author over them.
struct MoreAppsWindow: View {
    var body: some View {
        AppsView(source: "beadster") { AuthorRow() }
            .frame(minWidth: 420, minHeight: 480)
    }
}
