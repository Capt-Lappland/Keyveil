import XCTest
@testable import Keyveil

@MainActor
final class AppStateLoadingTests: XCTestCase {
    func testSwitchingToUncachedAppClearsStaleShortcutsImmediately() async {
        let newGroups = [group("New App", itemCount: 3)]
        let provider = SequenceShortcutProvider([.success(newGroups)])
        let state = makeState(provider: provider)
        state.groups = [group("Old App", itemCount: 2)]
        state.updateApplication(name: "New App", icon: nil, processID: 22, bundleIdentifier: "test.new")

        state.loadShortcuts()

        XCTAssertTrue(state.groups.isEmpty)
        XCTAssertTrue(state.isLoading)
        await waitUntil { !state.isLoading }
        XCTAssertEqual(state.groups, newGroups)
    }

    func testFreshCacheAvoidsDuplicateScanAndForceRefreshReplacesIt() async {
        let firstGroups = [group("File", itemCount: 2)]
        let refreshedGroups = [group("File", itemCount: 4)]
        let provider = SequenceShortcutProvider([.success(firstGroups), .success(refreshedGroups)])
        let state = makeState(provider: provider)
        state.updateApplication(name: "App", icon: nil, processID: 30, bundleIdentifier: "test.cache")

        state.loadShortcuts()
        await waitUntil { provider.callCount == 1 && state.groups == firstGroups }

        state.loadShortcuts()
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(state.groups, firstGroups)

        state.loadShortcuts(forceRefresh: true)
        await waitUntil { provider.callCount == 2 && state.groups == refreshedGroups }
        XCTAssertEqual(state.groups, refreshedGroups)
    }

    func testTransientFailureIsNotCached() async {
        let recoveredGroups = [group("Recovered", itemCount: 1)]
        let provider = SequenceShortcutProvider([.failure, .success(recoveredGroups)])
        let state = makeState(provider: provider)
        state.updateApplication(name: "App", icon: nil, processID: 40, bundleIdentifier: "test.retry")

        state.loadShortcuts()
        await waitUntil { provider.callCount == 1 && !state.isLoading }
        XCTAssertTrue(state.groups.isEmpty)

        state.loadShortcuts()
        await waitUntil { provider.callCount == 2 && state.groups == recoveredGroups }
        XCTAssertEqual(state.groups, recoveredGroups)
    }

    func testCancelledLateScanCannotOverwriteNewApplication() async {
        let oldGroups = [group("Old Result", itemCount: 8)]
        let newGroups = [group("New Result", itemCount: 2)]
        let provider = BlockingShortcutProvider(blockedPID: 50, blockedResult: oldGroups, otherResult: newGroups)
        let state = makeState(provider: provider)
        defer { provider.releaseBlockedScan() }

        state.updateApplication(name: "Old", icon: nil, processID: 50, bundleIdentifier: "test.old")
        state.loadShortcuts()
        await waitUntil { provider.blockedScanStarted }

        state.updateApplication(name: "New", icon: nil, processID: 51, bundleIdentifier: "test.new")
        state.loadShortcuts()
        await waitUntil { state.groups == newGroups && !state.isLoading }

        provider.releaseBlockedScan()
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.applicationName, "New")
        XCTAssertEqual(state.groups, newGroups)
    }

    func testCacheEvictsOldestApplicationAfterLimit() async {
        let provider = PIDShortcutProvider()
        let state = makeState(provider: provider)

        for pid in 1...25 {
            state.updateApplication(
                name: "App \(pid)",
                icon: nil,
                processID: pid_t(pid),
                bundleIdentifier: "test.cache.\(pid)"
            )
            state.loadShortcuts()
            await waitUntil { provider.callCount == pid && !state.isLoading }
        }

        state.updateApplication(
            name: "App 1",
            icon: nil,
            processID: 1,
            bundleIdentifier: "test.cache.1"
        )
        state.loadShortcuts()

        XCTAssertTrue(state.groups.isEmpty)
        await waitUntil { provider.callCount == 26 && !state.isLoading }
        XCTAssertEqual(state.groups.first?.title, "PID 1")
    }

    private func makeState(provider: any ShortcutProviding) -> AppState {
        AppState(
            shortcutProvider: provider,
            accessibilityCheck: { true },
            inputMonitoringCheck: { true }
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous state", file: file, line: line)
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

private final class SequenceShortcutProvider: ShortcutProviding, @unchecked Sendable {
    enum Response {
        case success([ShortcutGroup])
        case failure
    }

    private let lock = NSLock()
    private var responses: [Response]
    private var storedCallCount = 0

    init(_ responses: [Response]) {
        self.responses = responses
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    func shortcuts(for processID: pid_t) -> [ShortcutGroup]? {
        lock.lock()
        storedCallCount += 1
        let response = responses.isEmpty ? .failure : responses.removeFirst()
        lock.unlock()

        switch response {
        case let .success(groups): return groups
        case .failure: return nil
        }
    }
}

private final class BlockingShortcutProvider: ShortcutProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let blockedPID: pid_t
    private let blockedResult: [ShortcutGroup]
    private let otherResult: [ShortcutGroup]
    private var storedBlockedScanStarted = false

    init(blockedPID: pid_t, blockedResult: [ShortcutGroup], otherResult: [ShortcutGroup]) {
        self.blockedPID = blockedPID
        self.blockedResult = blockedResult
        self.otherResult = otherResult
    }

    var blockedScanStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedBlockedScanStarted
    }

    func shortcuts(for processID: pid_t) -> [ShortcutGroup]? {
        guard processID == blockedPID else { return otherResult }

        lock.lock()
        storedBlockedScanStarted = true
        lock.unlock()
        _ = semaphore.wait(timeout: .now() + 2)
        return blockedResult
    }

    func releaseBlockedScan() {
        semaphore.signal()
    }
}

private final class PIDShortcutProvider: ShortcutProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    func shortcuts(for processID: pid_t) -> [ShortcutGroup]? {
        lock.lock()
        storedCallCount += 1
        lock.unlock()

        let title = "PID \(processID)"
        return [
            ShortcutGroup(
                title: title,
                shortcuts: [ShortcutItem(title: "Action", keys: ["⌘", "A"], path: title)]
            )
        ]
    }
}
