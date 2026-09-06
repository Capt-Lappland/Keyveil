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

    private func group(_ title: String, itemCount: Int) -> ShortcutGroup {
        ShortcutGroup(
            title: title,
            shortcuts: (0..<itemCount).map { index in
                ShortcutItem(title: "Item \(index)", keys: ["⌘", "\(index)"], path: title)
            }
        )
    }
}
