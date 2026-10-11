import XCTest
@testable import Keyveil

/// Exercises the Common-group split and the folding rules against menus captured
/// from real applications, because both features are easy to get subtly wrong:
/// a whitelist that is too eager steals a command from the menu the user would
/// look in, and folding that is too eager hides what they came for.
final class SystemShortcutCatalogTests: XCTestCase {
    func testCommonBlockIsIdenticalAcrossEveryCapturedApp() throws {
        // The whole premise of the Common group: the same inherited shortcuts show
        // up in every app. If this ever stops holding, the group is noise.
        var perApp: [String: [String]] = [:]
        for app in CapturedAppMenus.all {
            let (_, system) = SystemShortcutCatalog.partition(CapturedAppMenus.groups(for: app))
            perApp[app.name] = system.flatMap { $0.shortcuts.map(\.title) }.sorted()
        }

        let reference = try XCTUnwrap(perApp.values.first)
        XCTAssertFalse(reference.isEmpty)
        for (name, titles) in perApp {
            XCTAssertEqual(
                titles,
                reference,
                "\(name) does not expose the same inherited shortcut block as the others"
            )
        }

        // Measured on macOS: 22 identical items in all five apps.
        XCTAssertEqual(reference.count, 22, "The inherited block changed size: \(reference)")
    }

    func testPartitionLosesNothing() {
        for app in CapturedAppMenus.all {
            let groups = CapturedAppMenus.groups(for: app)
            let before = groups.flatMap { $0.shortcuts.map(\.id) }.sorted()
            let (appGroups, systemGroups) = SystemShortcutCatalog.partition(groups)
            let after = (appGroups + systemGroups).flatMap { $0.shortcuts.map(\.id) }.sorted()

            XCTAssertEqual(before, after, "\(app.name) lost or duplicated shortcuts in the split")
        }
    }

    func testTextAlignmentIsNotMistakenForWindowTiling() throws {
        // TextEdit's Format menu contains "Centre" with ⌘|, which is text alignment.
        // The window arrangement block has a "Centre" too, so the name alone must
        // never be enough: it only counts inside the Window menu.
        XCTAssertFalse(
            SystemShortcutCatalog.isSystemShortcut(groupTitle: "Format", itemTitle: "Centre")
        )
        XCTAssertTrue(
            SystemShortcutCatalog.isSystemShortcut(groupTitle: "Window", itemTitle: "Centre")
        )

        let groups = try XCTUnwrap(
            CapturedAppMenus.app(named: "Textedit").map(CapturedAppMenus.groups(for:))
        )
        let (appGroups, systemGroups) = SystemShortcutCatalog.partition(groups)

        let formatInApp = appGroups.first { $0.title == "Format" }
        XCTAssertTrue(
            formatInApp?.shortcuts.contains { $0.title == "Centre" } == true,
            "TextEdit's text-alignment Centre was pulled into the Common group"
        )
        XCTAssertFalse(
            systemGroups.contains { $0.title == "Format" },
            "No Format item should ever be classified as inherited"
        )
    }

    func testEverydayEditingCommandsStayInTheirMenu() throws {
        // Cut/Copy/Paste are universal but they are also what people look for, so
        // they are deliberately left in place.
        let groups = try XCTUnwrap(
            CapturedAppMenus.app(named: "Safari").map(CapturedAppMenus.groups(for:))
        )
        let (appGroups, _) = SystemShortcutCatalog.partition(groups)

        let editTitles = appGroups.first { $0.title == "Edit" }?.shortcuts.map(\.title) ?? []
        for expected in ["Cut", "Copy", "Paste", "Select All", "Undo Close Tab"] {
            XCTAssertTrue(editTitles.contains(expected), "\(expected) left the Edit menu")
        }
    }

    func testAppSpecificCommandsAreNeverCaptured() {
        // The commands that make an app itself must survive the split untouched.
        let expectations: [String: [String]] = [
            "Safari": ["New Tab", "Reopen Last Closed Tab", "Show All History"],
            "Finder": ["New Finder Window", "Empty Bin…", "AirDrop"],
            "Preview": ["Actual Size", "Rotate Left", "Show Markup Toolbar"]
        ]

        for (appName, titles) in expectations {
            guard let app = CapturedAppMenus.app(named: appName) else {
                return XCTFail("Missing capture for \(appName)")
            }
            let (appGroups, systemGroups) = SystemShortcutCatalog.partition(
                CapturedAppMenus.groups(for: app)
            )
            let appTitles = Set(appGroups.flatMap { $0.shortcuts.map(\.title) })
            let systemTitles = Set(systemGroups.flatMap { $0.shortcuts.map(\.title) })

            for title in titles {
                XCTAssertTrue(appTitles.contains(title), "\(appName): \(title) vanished from the app")
                XCTAssertFalse(systemTitles.contains(title), "\(appName): \(title) was called inherited")
            }
        }
    }

    func testWallPlanIsCheapEnoughToRunPerFrame() {
        // The panel rebuilds the plan on every body evaluation, which during a
        // scroll is every frame, so it must cost far less than a frame (16.7 ms).
        let groups = (0..<12).map { groupIndex in
            ShortcutGroup(
                title: "Group \(groupIndex)",
                shortcuts: (0..<40).map { itemIndex in
                    ShortcutItem(title: "Command title \(itemIndex)",
                                 keys: ["⌃", "⌥", "⇧", "⌘", "Space"],
                                 path: "S/\(groupIndex)", ordinal: groupIndex * 40 + itemIndex)
                }
            )
        }

        // Warm up so a cold first call does not skew the average.
        _ = ShortcutWallPlan.makePlan(groups: groups, expandedIDs: [], commonGroupTitle: "Common")
        let iterations = 50
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            _ = ShortcutWallPlan.makePlan(groups: groups, expandedIDs: [], commonGroupTitle: "Common")
        }
        let perCall = (ProcessInfo.processInfo.systemUptime - start) / Double(iterations)

        XCTAssertLessThan(
            perCall,
            0.002,
            "Rebuilding the wall plan costs \(perCall * 1000) ms, too much for a per-frame call"
        )
    }

    func testFoldBehaviourIsHonoured() throws {
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let groups = CapturedAppMenus.groups(for: safari)

        func plan(_ behaviour: FoldBehaviour, rowBudget: Int = 9) -> WallPlan {
            ShortcutWallPlan.makePlan(
                groups: groups,
                expandedIDs: [],
                commonGroupTitle: "Common",
                revealLimit: behaviour.revealLimit(rowBudget: rowBudget)
            )
        }

        // Automatic: fold only what does not fit, and never wider than one screen's
        // worth of rows even on a tall panel.
        let automatic = plan(.automatic)
        let folded = automatic.sections.filter(\.isCollapsed)
        XCTAssertFalse(folded.isEmpty)
        for section in automatic.sections where section.isCollapsed {
            XCTAssertLessThanOrEqual(section.revealLimit, ShortcutWallPlan.maximumReveal)
        }
        XCTAssertLessThanOrEqual(
            FoldBehaviour.automatic.revealLimit(rowBudget: 40) ?? 0,
            ShortcutWallPlan.maximumReveal,
            "A tall panel must still not unfold everything"
        )

        // Show everything: nothing folds and no fold control is offered.
        let expanded = plan(.alwaysExpanded)
        XCTAssertTrue(expanded.sections.allSatisfy { !$0.isCollapsed })
        XCTAssertTrue(expanded.sections.allSatisfy { !$0.canCollapse })
        XCTAssertEqual(
            expanded.sections.flatMap { $0.group.shortcuts }.count,
            automatic.sections.flatMap { $0.group.shortcuts }.count,
            "Showing everything must not change how many shortcuts exist"
        )

        // Compact: a shorter fold than automatic.
        let compact = plan(.compact)
        for section in compact.sections where section.isCollapsed {
            XCTAssertLessThanOrEqual(section.revealLimit, ShortcutWallPlan.compactReveal)
        }
    }

    func testFoldLimitDrivesBothThePlanAndTheRowsDrawn() throws {
        // The bug this guards: the plan folded at one number while the view truncated
        // at another, so a group drew more rows than it had folded for and the fold
        // control ended up off screen.
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let plan = ShortcutWallPlan.makePlan(
            groups: CapturedAppMenus.groups(for: safari),
            expandedIDs: [],
            commonGroupTitle: "Common",
            revealLimit: FoldBehaviour.automatic.revealLimit(rowBudget: 9)
        )

        for section in plan.sections where section.isCollapsed {
            XCTAssertEqual(section.visibleShortcuts.count, section.revealLimit)
            XCTAssertEqual(
                section.hiddenCount,
                section.group.shortcuts.count - section.revealLimit
            )
        }
        for section in plan.sections where !section.isCollapsed {
            XCTAssertEqual(section.visibleShortcuts.count, section.group.shortcuts.count)
            XCTAssertEqual(section.hiddenCount, 0)
        }
    }

    func testThemeChoicesResolveToDistinctAccents() {
        XCTAssertNil(PanelTheme.system.accentName, "System must defer to the macOS accent")
        let named = PanelTheme.allCases.compactMap(\.accentName)
        XCTAssertEqual(
            Set(named).count,
            named.count,
            "Two themes resolve to the same accent"
        )
        for theme in PanelTheme.allCases where theme != .system {
            XCTAssertNotNil(theme.accentName)
        }
    }

    func testInheritedShortcutsBecomeOneFoldedGroup() throws {
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let plan = ShortcutWallPlan.makePlan(
            groups: CapturedAppMenus.groups(for: safari),
            expandedIDs: [],
            commonGroupTitle: "Common"
        )

        let common = try XCTUnwrap(plan.sections.first { $0.id == ShortcutWallPlan.commonGroupID })
        XCTAssertTrue(common.isCollapsed, "The Common group should start folded")
        XCTAssertEqual(common.group.shortcuts.count, 22)
        XCTAssertEqual(common.group.title, "Common")

        // Each inherited shortcut remembers the menu it came from.
        XCTAssertEqual(common.originHints.count, 22)
        XCTAssertTrue(common.originHints.values.contains("Window"))

        // The common group is last, so the app's own features own the first screen.
        XCTAssertEqual(plan.sections.last?.id, ShortcutWallPlan.commonGroupID)

        // No app group should still carry an inherited item.
        let appTitles = Set(
            plan.sections
                .filter { $0.id != ShortcutWallPlan.commonGroupID }
                .flatMap { $0.group.shortcuts.map(\.title) }
        )
        XCTAssertFalse(appTitles.contains("Minimise"))
        XCTAssertFalse(appTitles.contains("Emoji & Symbols"))
        XCTAssertFalse(appTitles.contains("Enter Full Screen"))
    }

    func testExpandingTheCommonGroupIsRemembered() throws {
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let groups = CapturedAppMenus.groups(for: safari)

        let folded = ShortcutWallPlan.makePlan(
            groups: groups, expandedIDs: [], commonGroupTitle: "Common"
        )
        XCTAssertTrue(
            folded.sections.first { $0.id == ShortcutWallPlan.commonGroupID }?.isCollapsed == true
        )

        let opened = ShortcutWallPlan.makePlan(
            groups: groups,
            expandedIDs: [ShortcutWallPlan.commonGroupID],
            commonGroupTitle: "Common"
        )
        XCTAssertFalse(
            opened.sections.first { $0.id == ShortcutWallPlan.commonGroupID }?.isCollapsed == true
        )
        // Expanding reveals everything: folding must never drop shortcuts.
        XCTAssertEqual(
            opened.sections.flatMap { $0.group.shortcuts }.count,
            groups.flatMap { $0.shortcuts }.count
        )
    }


    func testReclassifyingAlreadyClassifiedGroupsMovesNothing() throws {
        // The catalog answers "is this inherited?" from the group a shortcut sits
        // in, so it has to be stable: nothing may become inherited only on a second
        // pass, or an item would move under the user's cursor between renders.
        for app in CapturedAppMenus.all {
            let groups = CapturedAppMenus.groups(for: app)
            let (appGroups, systemGroups) = SystemShortcutCatalog.partition(groups)

            let (appAgain, systemAgain) = SystemShortcutCatalog.partition(appGroups)
            XCTAssertEqual(
                appAgain.flatMap { $0.shortcuts.map(\.title) },
                appGroups.flatMap { $0.shortcuts.map(\.title) },
                "\(app.name): an app shortcut was reclassified as inherited on a second pass"
            )
            XCTAssertTrue(
                systemAgain.isEmpty,
                "\(app.name): re-partitioning the app groups produced new inherited items"
            )

            // The Common group lives in the Window and application menus, so it is
            // expected to survive a second pass untouched.
            let (appFromSystem, systemFromSystem) = SystemShortcutCatalog.partition(systemGroups)
            XCTAssertTrue(appFromSystem.isEmpty)
            XCTAssertEqual(
                systemFromSystem.flatMap { $0.shortcuts.map(\.title) },
                systemGroups.flatMap { $0.shortcuts.map(\.title) }
            )
        }
    }

    func testLongGroupsFoldAndShortOnesDoNot() throws {
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let plan = ShortcutWallPlan.makePlan(
            groups: CapturedAppMenus.groups(for: safari),
            expandedIDs: [],
            commonGroupTitle: "Common"
        )

        // Safari's Edit menu has 27 shortcuts and Window has 21; both must fold.
        let edit = try XCTUnwrap(plan.sections.first { $0.id == "Edit" })
        XCTAssertTrue(edit.isCollapsed)
        XCTAssertTrue(edit.canCollapse)
        // Derived from the section's own limit rather than a constant: Edit also
        // donates its inherited items to the Common group, so neither its size nor
        // the fold limit equals the raw menu size any more.
        XCTAssertEqual(edit.hiddenCount, edit.group.shortcuts.count - edit.revealLimit)

        // History has 6 and must not gain a fold control.
        let history = try XCTUnwrap(plan.sections.first { $0.id == "History" })
        XCTAssertFalse(history.isCollapsed)
        XCTAssertFalse(history.canCollapse)
        XCTAssertEqual(history.hiddenCount, 0)

        XCTAssertTrue(plan.autoCollapsedIDs.contains("Edit"))
        XCTAssertFalse(plan.autoCollapsedIDs.contains("History"))
    }

    func testRepeatedMenuTitlesRemainDistinctShortcuts() throws {
        // Finder's File menu offers "Eject" for ⌘E, ⌃⌘E and ⌥⌘E. They are three
        // commands, and an identity built only from path/title/keys collapsed them
        // onto one, so the wall silently dropped two.
        let finder = try XCTUnwrap(CapturedAppMenus.app(named: "Finder"))
        let groups = CapturedAppMenus.groups(for: finder)

        let ids = groups.flatMap { $0.shortcuts.map(\.id) }
        XCTAssertEqual(
            Set(ids).count,
            ids.count,
            "Shortcut identities collided; repeated menu titles would be dropped"
        )

        let fileGroup = try XCTUnwrap(groups.first { $0.title == "File" })
        XCTAssertEqual(
            fileGroup.shortcuts.filter { $0.title == "Eject" }.count,
            3,
            "Finder's three Eject commands must all survive"
        )

        // The same has to hold after the Common group aggregates across menus,
        // where a title can repeat in different groups as well.
        let (_, systemGroups) = SystemShortcutCatalog.partition(groups)
        let systemIDs = systemGroups.flatMap { $0.shortcuts.map(\.id) }
        XCTAssertEqual(Set(systemIDs).count, systemIDs.count)
    }

    func testSearchCanStillFindAShortcutInsideAFoldedGroup() throws {
        // This is the reason folding is suspended while searching: "Minimise" lives
        // in the folded Common group, and it must still be findable.
        let safari = try XCTUnwrap(CapturedAppMenus.app(named: "Safari"))
        let plan = ShortcutWallPlan.makePlan(
            groups: CapturedAppMenus.groups(for: safari),
            expandedIDs: [],
            commonGroupTitle: "Common"
        )

        let common = try XCTUnwrap(plan.sections.first { $0.id == ShortcutWallPlan.commonGroupID })
        XCTAssertTrue(common.isCollapsed)

        let matches = ShortcutQuery.filter([common.group], matching: "Minimise")
        XCTAssertGreaterThanOrEqual(ShortcutQuery.count(in: matches), 1)
        XCTAssertTrue(
            matches.flatMap { $0.shortcuts }.contains { $0.title == "Minimise" },
            "A folded group must still be searchable"
        )
    }
}
