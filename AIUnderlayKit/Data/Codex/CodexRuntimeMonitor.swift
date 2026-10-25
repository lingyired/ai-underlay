import Foundation

/// Owns one read-only Desktop subscription and a bounded reconnect delay.
/// Raw decoding and socket I/O stay on the collector's utility queue.
@MainActor
final class CodexRuntimeMonitor {
    private let home: URL
    private let onUpdate: (CodexRuntimeSnapshot) -> Void
    private var collector: NativeDesktopCollector?
    private var retryTask: Task<Void, Never>?
    private enum Event: Sendable { case frame(Data), closed }
    private var eventTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<Event>.Continuation?
    private var state = CodexRuntimeState()
    private var generation = 0
    private var running = false

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        onUpdate: @escaping (CodexRuntimeSnapshot) -> Void
    ) {
        self.home = home
        self.onUpdate = onUpdate
    }

    func start() {
        guard !running else { return }
        running = true
        connect()
    }

    func stop() {
        running = false
        generation += 1
        retryTask?.cancel()
        retryTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        eventTask?.cancel()
        eventTask = nil
        collector?.stop()
        collector = nil
        state.disconnected()
    }

    func snapshot() -> CodexRuntimeSnapshot { state.snapshot() }

    private func connect() {
        guard running else { return }
        generation += 1
        let currentGeneration = generation
        state.connecting()
        onUpdate(state.snapshot())
        let (events, continuation) = AsyncStream<Event>.makeStream()
        eventContinuation = continuation
        // One consumer preserves the collector's frame order, including closure.
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, self.running, self.generation == currentGeneration else { return }
                switch event {
                case .frame(let data):
                    self.state.consume(data)
                    self.onUpdate(self.state.snapshot())
                case .closed:
                    self.closed(generation: currentGeneration)
                    return
                }
            }
        }
        let collector = NativeDesktopCollector(
            home: home, hosts: ["local"], batchInterval: 0.25,
            onFrame: { continuation.yield(.frame($0)) },
            onClosed: { continuation.yield(.closed) }
        )
        self.collector = collector
        // Socket discovery/connect has a timeout and never blocks AppKit.
        Task.detached(priority: .utility) {
            do { try collector.start() }
            catch { continuation.yield(.closed) }
        }
    }

    private func closed(generation: Int) {
        guard running, self.generation == generation, retryTask == nil else { return }
        collector?.stop()
        collector = nil
        eventContinuation?.finish()
        eventContinuation = nil
        state.disconnected()
        onUpdate(state.snapshot())
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
            guard let self, self.running, self.generation == generation else { return }
            self.retryTask = nil
            self.connect()
        }
    }
}
