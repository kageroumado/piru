// A model file writes `@Model` under `import SwiftData` alone, as with SwiftData, and the
// macro's expansion names Observation's types.
@_exported import Observation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Android)
    import Android
#elseif canImport(Glibc)
    import Glibc
#endif

/// The registrar a `@Model` class's tracked properties report to: Observation's own, so
/// `withObservationTracking` and SwiftUI see a model change, plus a bridge a UI layer may
/// install for a renderer Observation does not reach.
///
/// Observation hears every read and write on every thread. The bridge is the renderer's,
/// and the renderer reads models on the main thread only, so the bridge is made and called
/// there alone: a model gets one on its first main-thread read outside PortableData's own
/// traversals, and from then on hears that model's main-thread reads and writes.
public struct ModelObservationRegistrar: Sendable {
    private let native = ObservationRegistrar()
    private let slot = BridgeSlot()

    public init() {}

    /// A read inside one of PortableData's own passes reports to neither registrar: a fetch
    /// sorting thousands of models reads each sort key a dozen times, and a reported read is a
    /// call into the bridge (Skip's registrar, over JNI) per comparison. A fetch's result is no
    /// view's dependency; a ``Query`` re-reads on the context's revision instead.
    public func access<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        guard !ModelObservation.isTraversingOnMainThread else { return }
        slot.bridge(making: true)?.access(subject, keyPath: keyPath)
        native.access(subject, keyPath: keyPath)
    }

    public func willSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        slot.bridge(making: false)?.willSet(subject, keyPath: keyPath)
        native.willSet(subject, keyPath: keyPath)
    }

    public func didSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>) {
        slot.bridge(making: false)?.didSet(subject, keyPath: keyPath)
        native.didSet(subject, keyPath: keyPath)
    }

    public func withMutation<Subject: Observable, T>(
        of subject: Subject, keyPath: KeyPath<Subject, some Any>, _ mutation: () throws -> T,
    ) rethrows -> T {
        willSet(subject, keyPath: keyPath)
        defer { didSet(subject, keyPath: keyPath) }
        return try mutation()
    }
}

/// A second registrar each model's main-thread reads and writes also go to. On Android the
/// app installs Skip's, whose registrar is what recomposes the Compose views that read a model.
public protocol ModelObservationBridge: Sendable {
    func access<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
    func willSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
    func didSet<Subject: Observable>(_ subject: Subject, keyPath: KeyPath<Subject, some Any>)
}

public enum ModelObservation {
    /// Makes one bridge per model, the first time the model is read on the main thread after
    /// this is set, so models loaded before the UI layer starts are bridged too. A write
    /// makes none: a model no view has read has no view to recompose.
    public nonisolated(unsafe) static var makeBridge: (@Sendable () -> any ModelObservationBridge)?

    /// How many PortableData traversals are running on the main thread. While any is, a read
    /// makes no bridge, because the reader is PortableData. Read and written on the main
    /// thread only.
    private nonisolated(unsafe) static var traversals = 0

    /// Whether a main-thread read now may make a model's bridge.
    static var makesBridges: Bool {
        traversals == 0
    }

    /// Whether the caller is a PortableData pass on the main thread; other threads never count
    /// one, so their reads keep reporting.
    static var isTraversingOnMainThread: Bool {
        traversals > 0 && isMainThread()
    }

    /// Runs `body`, one of PortableData's own passes over models (loading, merging another
    /// context's save, rebuilding inverses, filtering and sorting a fetch, saving), with
    /// bridge creation held off on the main thread. Models that already have a bridge still
    /// report to it, so a merge into a model a view shows recomposes that view. Nested and
    /// throwing passes leave the count balanced.
    static func traversing<T>(_ body: () throws -> T) rethrows -> T {
        guard isMainThread() else { return try body() }
        traversals += 1
        defer { traversals -= 1 }
        return try body()
    }
}

/// Whether the caller runs on the process's main thread, the one Android's UI and Swift's
/// main actor share. On Linux and Android that is the thread whose id is the process id,
/// the test Swift's main executor makes there.
func isMainThread() -> Bool {
    #if canImport(Darwin)
        pthread_main_np() != 0
    #else
        gettid() == getpid()
    #endif
}

/// One model's bridge, made on its first eligible read. Touched on the main thread only, so
/// the slot needs no lock.
private final class BridgeSlot: @unchecked Sendable {
    private var made: (any ModelObservationBridge)?

    /// The bridge a main-thread report goes to, making it when `making` and nothing holds
    /// creation off; `nil` on any other thread.
    func bridge(making: Bool) -> (any ModelObservationBridge)? {
        guard isMainThread() else { return nil }
        if let made { return made }
        guard making, ModelObservation.makesBridges, let make = ModelObservation.makeBridge else { return nil }
        let bridge = make()
        made = bridge
        return bridge
    }
}
