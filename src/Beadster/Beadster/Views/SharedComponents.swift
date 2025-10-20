//
//  SharedComponents.swift
//  Beadster
//
//  Created by Anton Podviaznikov on 10/19/25.
//

import SwiftUI

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeViews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeViews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeViews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let proposalWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > proposalWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - App State Enums

enum AppTab: String, CaseIterable {
    case projects = "Projects"
    case openIssues = "Open"
    case allIssues = "All"
    case closedIssues = "Closed"
}

enum ViewMode: String, CaseIterable, RawRepresentable {
    case simple = "simple"
    case extended = "extended"
    case tree = "tree"

    var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .extended: return "Extended"
        case .tree: return "Tree"
        }
    }

    var symbolName: String {
        switch self {
        case .simple: return "list.bullet"
        case .tree: return "list.bullet.indent"
        case .extended: return "list.bullet.below.rectangle"
        }
    }
}

enum ContentMode: Equatable {
    case onboarding
    case projectsList
    case issuesList
    case issueDetail(Issue)
    case settings
}

// MARK: - Tree Node

struct IssueTreeNode: Identifiable {
    let id: String
    let issue: Issue
    let children: [IssueTreeNode]
    let depth: Int

    init(issue: Issue, children: [IssueTreeNode] = [], depth: Int = 0) {
        self.id = issue.id
        self.issue = issue
        self.children = children
        self.depth = depth
    }
}

// MARK: - Layout Constants

enum LayoutConstants {
    static let appHeaderHeight: CGFloat = 28
    static let contentHeaderHeight: CGFloat = 44
    static let footerHeight: CGFloat = 24
}
