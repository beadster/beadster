// Core Spotlight glue over BeadsKit's SpotlightItem: every open bead findable from ⌘Space by
// title, id, project and labels. One domain per project, replaced whole after each change;
// a removed folder takes its projects' domains with it. Opening a result is
// AppModel.reveal (MainWindow's onContinueUserActivity).
import BeadsKit
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum SpotlightIndexer {
    private static var index: CSSearchableIndex { .default() }

    static func replace(domain: String, with items: [SpotlightItem]) async {
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        let searchable = items.map { item in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = item.title
            attrs.contentDescription = item.detail
            attrs.keywords = item.keywords
            attrs.textContent = item.text
            attrs.contentModificationDate = item.modified
            return CSSearchableItem(uniqueIdentifier: item.uniqueID, domainIdentifier: item.domain, attributeSet: attrs)
        }
        do { try await index.indexSearchableItems(searchable) }
        catch { NSLog("beadster spotlight index failed: \(error)") }
    }

    static func remove(domains: [String]) async {
        guard !domains.isEmpty else { return }
        try? await index.deleteSearchableItems(withDomainIdentifiers: domains)
    }
}
