import XCTest
@testable import Keyveil

final class ShortcutLayoutTests: XCTestCase {
    func testResponsiveColumnCounts() {
        XCTAssertEqual(ShortcutColumnLayout.columnCount(forWidth: 700, groupCount: 8), 2)
        XCTAssertEqual(ShortcutColumnLayout.columnCount(forWidth: 999, groupCount: 8), 2)
        XCTAssertEqual(ShortcutColumnLayout.columnCount(forWidth: 1_000, groupCount: 8), 3)
        XCTAssertEqual(ShortcutColumnLayout.columnCount(forWidth: 1_200, groupCount: 1), 1)
        XCTAssertEqual(ShortcutColumnLayout.columnCount(forWidth: 1_200, groupCount: 0), 0)
    }

    func testBalancingPreservesGroupsAndMenuOrder() {
        let groups = [
            group("File", itemCount: 12),
            group("Edit", itemCount: 8),
            group("View", itemCount: 7),
            group("Window", itemCount: 4),
            group("Help", itemCount: 2)
        ]

        let columns = ShortcutColumnLayout.balanced(groups, columnCount: 3)
        XCTAssertEqual(columns.count, 3)
        XCTAssertTrue(columns.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(columns.flatMap { $0.map(\.id) }, groups.map(\.id))
    }

    func testBalancingClampsExcessColumnsAndHandlesEmptyInput() {
        let groups = [group("File", itemCount: 2), group("Edit", itemCount: 2)]
        let columns = ShortcutColumnLayout.balanced(groups, columnCount: 10)

        XCTAssertEqual(columns.count, 2)
        XCTAssertTrue(columns.allSatisfy { $0.count == 1 })
        XCTAssertTrue(ShortcutColumnLayout.balanced([], columnCount: 3).isEmpty)
    }

    func testLocalizedMenuSymbols() {
        XCTAssertEqual(group("文件", itemCount: 1).symbol, "doc")
        XCTAssertEqual(group("编辑", itemCount: 1).symbol, "slider.horizontal.3")
        XCTAssertEqual(group("窗口", itemCount: 1).symbol, "macwindow")
        XCTAssertEqual(group("未知", itemCount: 1).symbol, "command")
    }

    func testVisibleRowBudgetKeepsTheFoldControlOnScreen() {
        // Measured from a rendered panel: 43-45 pt per row, 468 pt of content band
        // at the standard size. The budget has to leave room for the fold control,
        // or folding would hide shortcuts instead of offering to reveal them.
        let standard = ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 468)
        XCTAssertGreaterThanOrEqual(standard, 8)
        XCTAssertLessThanOrEqual(standard, 11)

        // A shorter panel shows fewer rows rather than pushing the control off.
        XCTAssertLessThan(
            ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 260),
            standard
        )
        XCTAssertGreaterThanOrEqual(ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 260), 1)

        // Degenerate sizes must not produce a zero or negative budget.
        XCTAssertGreaterThanOrEqual(ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 0), 1)
        XCTAssertGreaterThanOrEqual(ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 10), 1)
        XCTAssertLessThanOrEqual(ShortcutColumnLayout.visibleRowBudget(forColumnHeight: 100_000), 400)
    }

    func testFoldDisclosureFitsInsideTheFirstScreen() {
        // The bug this guards: the fold control was drawn after the visible rows, so
        // for any group long enough to fold it landed below the visible area. The
        // group was folded and the way to unfold it was invisible.
        //
        // A group's height is its header plus its rows. It has to fit in one column
        // for the control — which now sits in that header — to be reachable.
        let columnHeight: CGFloat = 468          // measured at the standard panel size
        let budget = ShortcutColumnLayout.visibleRowBudget(forColumnHeight: columnHeight)
        let headerHeight = ShortcutColumnLayout.groupHeaderHeight

        let groupHeight = headerHeight + CGFloat(budget) * ShortcutColumnLayout.rowHeight
        XCTAssertLessThanOrEqual(
            groupHeight,
            columnHeight,
            "A folded group is taller than the column, so its disclosure is off screen"
        )

        // Folding must actually reduce the height, or it buys nothing.
        let unfoldedHeight = headerHeight + 27 * ShortcutColumnLayout.rowHeight
        XCTAssertLessThan(groupHeight, unfoldedHeight)
    }

    func testSearchMatchesTitlesKeysAndCombinedTerms() {
        let groups = [
            ShortcutGroup(title: "File", shortcuts: [
                ShortcutItem(title: "New Tab", keys: ["⌘", "T"], path: "File"),
                ShortcutItem(title: "Close Window", keys: ["⇧", "⌘", "W"], path: "File")
            ]),
            ShortcutGroup(title: "Edit", shortcuts: [
                ShortcutItem(title: "Find…", keys: ["⌘", "F"], path: "Edit"),
                ShortcutItem(title: "Émoji & Symbols", keys: ["⌃", "⌘", "Space"], path: "Edit")
            ])
        ]

        // Case and diacritics are ignored.
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "close window")),
            1
        )
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "emoji")),
            1
        )

        // Key symbols are searchable, with or without spaces.
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "⇧⌘W")),
            1
        )
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "⇧ ⌘ W")),
            1
        )

        // All whitespace-separated terms must match somewhere in title or keys.
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "tab ⌘")),
            1
        )
        XCTAssertEqual(
            ShortcutQuery.count(in: ShortcutQuery.filter(groups, matching: "tab ⇧")),
            0
        )
    }

    func testSearchDropsEmptyGroupsAndPassesThroughBlankQueries() {
        let groups = [
            ShortcutGroup(title: "File", shortcuts: [
                ShortcutItem(title: "New Tab", keys: ["⌘", "T"], path: "File")
            ]),
            ShortcutGroup(title: "Window", shortcuts: [
                ShortcutItem(title: "Minimize", keys: ["⌘", "M"], path: "Window")
            ])
        ]

        // Blank and whitespace-only queries keep the whole wall, including groups.
        XCTAssertEqual(ShortcutQuery.filter(groups, matching: ""), groups)
        XCTAssertEqual(ShortcutQuery.filter(groups, matching: "   "), groups)
        XCTAssertEqual(ShortcutQuery.filter(groups, matching: "\n\t"), groups)

        // A group survives only if it still has a matching shortcut, so the wall
        // never renders an empty section header.
        let filtered = ShortcutQuery.filter(groups, matching: "minimize")
        XCTAssertEqual(filtered.map(\.title), ["Window"])
        XCTAssertEqual(ShortcutQuery.count(in: filtered), 1)

        XCTAssertTrue(ShortcutQuery.filter(groups, matching: "zzz").isEmpty)
        XCTAssertEqual(ShortcutQuery.count(in: []), 0)
    }

    private func group(_ title: String, itemCount: Int) -> ShortcutGroup {
        ShortcutGroup(
            title: title,
            shortcuts: (0..<itemCount).map { index in
                ShortcutItem(title: "Item \(index)", keys: ["⌘", "\(index)"], path: title)
            }
        )
    }
}
