/// One group as it should appear on the wall.
struct WallSection: Identifiable, Equatable {
    let id: String
    let group: ShortcutGroup
    /// True when the group is showing only its first `revealLimit` shortcuts.
    let isCollapsed: Bool
    /// True when folding is something the user may choose. Long groups and the
    /// aggregated Common group qualify; a short app menu does not.
    let canCollapse: Bool
    /// Rows a folded section shows. Carried on the section so the view truncates at
    /// exactly the limit the plan folded at — when the two disagreed, a group folded
    /// at one number but drew another and the fold control left the screen.
    let revealLimit: Int
    /// Original menu for each shortcut, keyed by group and title rather than by
    /// identity, because a title can repeat inside one menu. Used by the
    /// aggregated Common group so a tiling command still says it lives under Window.
    let originHints: [String: String]

    /// The hint key for one shortcut. Shared with the plan so the two cannot drift.
    static func originKey(groupTitle: String, itemTitle: String) -> String {
        "\(groupTitle)\u{1}\(itemTitle)"
    }

    /// How many shortcuts the fold is hiding.
    var hiddenCount: Int {
        isCollapsed ? max(0, group.shortcuts.count - revealLimit) : 0
    }

    /// Rows to draw for this section.
    var visibleShortcuts: [ShortcutItem] {
        isCollapsed ? Array(group.shortcuts.prefix(revealLimit)) : group.shortcuts
    }
}

/// The wall after the Common group has been pulled out and long groups folded.
struct WallPlan: Equatable {
    let sections: [WallSection]
    /// Titles that start folded because they are simply long, so the view knows
    /// which groups to reset between presentations.
    let autoCollapsedIDs: Set<String>
}

/// Turns a raw scan into what the wall shows.
///
/// Two separate problems are solved here, and both are about the *first screen*
/// rather than about hiding anything: real apps publish 62–112 shortcuts, with
/// single menu groups running to 27 items, and a fifth to two fifths of those
/// shortcuts are inherited from AppKit and identical in every app.
enum ShortcutWallPlan {
    /// Fallback row budget, used before a panel size is known. Measured rather than
    /// guessed: a shortcut row occupies about 43–45 pt and the content band is
    /// 468 pt at the standard 1180×720 panel, so about nine rows fit on screen.
    static let revealLimit = 9

    /// Longest a folded group may be, whatever the panel height allows. Keeps a
    /// folded menu to roughly one screen of rows.
    static let maximumReveal = 12

    /// How short the compact preference folds a menu.
    static let compactReveal = 5

    /// Stable identifier for the aggregated inherited-shortcuts group. Deliberately
    /// not the localised display title, so that expanding it survives a language
    /// change.
    static let commonGroupID = "__keyveil.common"

    /// - Parameter revealLimit: how many rows a folded group shows. The default
    ///   matches `FoldBehaviour.automatic`, so a caller that says nothing gets the
    ///   shipped behaviour. `nil` is the explicit "show everything" request and must
    ///   be passed deliberately.
    static func makePlan(
        groups: [ShortcutGroup],
        expandedIDs: Set<String>,
        commonGroupTitle: String,
        revealLimit: Int? = maximumReveal
    ) -> WallPlan {
        let partitioned = SystemShortcutCatalog.partition(groups)

        var sections: [WallSection] = []
        var autoCollapsed: Set<String> = []

        for group in partitioned.app {
            let autoCollapse = revealLimit.map { group.shortcuts.count > $0 } ?? false
            if autoCollapse { autoCollapsed.insert(group.id) }
            sections.append(
                section(
                    id: group.id,
                    group: group,
                    expandedIDs: expandedIDs,
                    autoCollapse: autoCollapse,
                    revealLimit: revealLimit,
                    originHints: [:]
                )
            )
        }

        // The inherited shortcuts keep their originating menu as a hint, and the
        // aggregated group is folded by default: the first screen should be the
        // app's own features.
        if let common = makeCommonGroup(from: partitioned.system, title: commonGroupTitle) {
            sections.append(
                section(
                    id: commonGroupID,
                    group: common.group,
                    expandedIDs: expandedIDs,
                    autoCollapse: revealLimit != nil,
                    revealLimit: revealLimit,
                    originHints: common.hints
                )
            )
        }

        return WallPlan(sections: sections, autoCollapsedIDs: autoCollapsed)
    }

    /// One section as it should be folded. Both callers differ only in how they
    /// decide `autoCollapse`, so the folding itself lives here and the two cannot
    /// drift apart.
    private static func section(
        id: String,
        group: ShortcutGroup,
        expandedIDs: Set<String>,
        autoCollapse: Bool,
        revealLimit: Int?,
        originHints: [String: String]
    ) -> WallSection {
        WallSection(
            id: id,
            group: group,
            isCollapsed: autoCollapse && !expandedIDs.contains(id),
            canCollapse: autoCollapse,
            revealLimit: revealLimit ?? group.shortcuts.count,
            originHints: originHints
        )
    }

    private static func makeCommonGroup(
        from systemGroups: [ShortcutGroup],
        title: String
    ) -> (group: ShortcutGroup, hints: [String: String])? {
        var items: [ShortcutItem] = []
        var hints: [String: String] = [:]

        for group in systemGroups {
            for item in group.shortcuts {
                items.append(item)
                hints[WallSection.originKey(groupTitle: group.title, itemTitle: item.title)] = group.title
            }
        }

        guard !items.isEmpty else { return nil }
        return (
            ShortcutGroup(title: title, shortcuts: items, symbol: commonGroupSymbol()),
            hints
        )
    }

    /// The title and symbol for the aggregated group. Computed rather than stored
    /// so it does not need to be persisted alongside the scan.
    static func commonGroupSymbol() -> String {
        "gearshape.2"
    }
}
