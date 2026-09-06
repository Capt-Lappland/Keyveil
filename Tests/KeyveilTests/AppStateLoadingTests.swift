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
        XCTAssertEqual(state.shortcutLoadIssue, .unavailable)

        state.loadShortcuts()
        await waitUntil { provider.callCount == 2 && state.groups == recoveredGroups }
        XCTAssertEqual(state.groups, recoveredGroups)
        XCTAssertNil(state.shortcutLoadIssue)
    }

    func testTimedOutScanShowsPartialResultsAndRetryRecovers() async {
        let partialGroups = [group("Partial", itemCount: 2)]
        let completeGroups = [group("Complete", itemCount: 5)]
        let provider = SequenceShortcutProvider([
            .timedOut(partialGroups),
            .success(completeGroups)
        ])
        let state = makeState(provider: provider)
        state.updateApplication(name: "App", icon: nil, processID: 41, bundleIdentifier: "test.timeout")

        state.loadShortcuts()
        await waitUntil { provider.callCount == 1 && !state.isLoading }

        XCTAssertEqual(state.groups, partialGroups)
        XCTAssertEqual(state.shortcutLoadIssue, .timedOut)

        state.retryShortcutLoad()
        await waitUntil { provider.callCount == 2 && !state.isLoading }

        XCTAssertEqual(state.groups, completeGroups)
        XCTAssertNil(state.shortcutLoadIssue)
    }

    func testFailedForceRefreshKeepsLastKnownShortcuts() async {
        let cachedGroups = [group("Cached", itemCount: 3)]
        let provider = SequenceShortcutProvider([.success(cachedGroups), .failure])
        let state = makeState(provider: provider)
        state.updateApplication(name: "App", icon: nil, processID: 42, bundleIdentifier: "test.stale")

        state.loadShortcuts()
        await waitUntil { provider.callCount == 1 && !state.isLoading }

        state.loadShortcuts(forceRefresh: true)
        await waitUntil { provider.callCount == 2 && state.shortcutLoadIssue == .unavailable }

        XCTAssertEqual(state.groups, cachedGroups)
        XCTAssertEqual(state.shortcutCount, 3)
    }

    func testMenuChangeInvalidatesOnlyTheMatchingApplicationCache() async {
        let firstGroups = [group("Initial", itemCount: 2)]
        let refreshedGroups = [group("Updated", itemCount: 4)]
        let provider = SequenceShortcutProvider([.success(firstGroups), .success(refreshedGroups)])
        let state = makeState(provider: provider)
        state.updateApplication(name: "App", icon: nil, processID: 43, bundleIdentifier: "test.observe")

        state.loadShortcuts()
        await waitUntil { provider.callCount == 1 && state.groups == firstGroups }

        XCTAssertFalse(state.invalidateShortcutCache(for: 99))
        state.loadShortcuts()
        XCTAssertEqual(provider.callCount, 1)

        XCTAssertTrue(state.invalidateShortcutCache(for: 43))
        state.loadShortcuts()
        await waitUntil { provider.callCount == 2 && state.groups == refreshedGroups }
    }

    func testScrollRequestsArePublishedOnlyWhilePinned() {
        let state = makeState(provider: SequenceShortcutProvider([]))

        state.requestShortcutScroll(.pageDown)
        XCTAssertNil(state.shortcutScrollRequest)

        state.isPinned = true
        state.requestShortcutScroll(.pageDown)
        XCTAssertEqual(
            state.shortcutScrollRequest,
            ShortcutScrollRequest(command: .pageDown, revision: 1)
        )

        state.requestShortcutScroll(.end)
        XCTAssertEqual(
            state.shortcutScrollRequest,
            ShortcutScrollRequest(command: .end, revision: 2)
        )

        state.beginShortcutPresentation()
        XCTAssertNil(state.shortcutScrollRequest)
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
        case timedOut([ShortcutGroup])
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

    func shortcuts(for processID: pid_t) -> ShortcutScanResult {
        lock.lock()
        storedCallCount += 1
        let response = responses.isEmpty ? .failure : responses.removeFirst()
        lock.unlock()

        switch response {
        case let .success(groups): return .success(groups)
        case let .timedOut(groups): return .timedOut(groups)
        case .failure: return .unavailable
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

    func shortcuts(for processID: pid_t) -> ShortcutScanResult {
        guard processID == blockedPID else { return .success(otherResult) }

        lock.lock()
        storedBlockedScanStarted = true
        lock.unlock()
        _ = semaphore.wait(timeout: .now() + 2)
        return .success(blockedResult)
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

    func shortcuts(for processID: pid_t) -> ShortcutScanResult {
        lock.lock()
        storedCallCount += 1
        lock.unlock()

        let title = "PID \(processID)"
        return .success([
            ShortcutGroup(
                title: title,
                shortcuts: [ShortcutItem(title: "Action", keys: ["⌘", "A"], path: title)]
            )
        ])
    }
}
