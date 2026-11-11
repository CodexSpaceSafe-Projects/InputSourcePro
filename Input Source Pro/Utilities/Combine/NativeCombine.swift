import Combine
import Foundation

extension AnyPublisher {
    /// Adapts a callback API, retaining its cleanup until completion or cancellation.
    static func create(
        _ build: @escaping (NativePublisherEmitter<Output, Failure>) -> AnyCancellable
    ) -> AnyPublisher<Output, Failure> {
        NativeCallbackPublisher(build: build).eraseToAnyPublisher()
    }
}

struct NativePublisherEmitter<Output, Failure: Error> {
    fileprivate let receiveValue: (Output) -> Void
    fileprivate let receiveCompletion: (Subscribers.Completion<Failure>) -> Void

    func send(_ value: Output) { receiveValue(value) }
    func send(completion: Subscribers.Completion<Failure>) { receiveCompletion(completion) }
}

private struct NativeCallbackPublisher<Output, Failure: Error>: Publisher {
    let build: (NativePublisherEmitter<Output, Failure>) -> AnyCancellable

    func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
        let lifetime = NativeCallbackLifetime()
        let subscription = NativeReplaySubscription(
            downstream: AnySubscriber(subscriber), buffer: [], capacity: Int.max,
            completion: nil, waitsForBufferedDemand: true, onEnd: { lifetime.cancel() }
        )
        subscriber.receive(subscription: subscription)
        subscription.activate()
        guard subscription.isActive else { return }
        let emitter = NativePublisherEmitter<Output, Failure>(receiveValue: { [weak subscription] value in
            subscription?.enqueue(value)
            subscription?.drain()
        }, receiveCompletion: { [weak subscription] completion in
            subscription?.enqueue(completion: completion)
            lifetime.cancel()
            subscription?.drain()
        })
        // A synchronous emission may already have completed or cancelled (.first()).
        // In that case setCleanup immediately cancels the newly returned resource.
        lifetime.setCleanup(build(emitter))
    }
}

private final class NativeCallbackLifetime {
    private let lock = NSLock()
    private var cleanup: AnyCancellable?
    private var ended = false

    func setCleanup(_ cleanup: AnyCancellable) {
        lock.lock()
        if ended {
            lock.unlock()
            cleanup.cancel()
        } else {
            self.cleanup = cleanup
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        ended = true
        let cleanup = self.cleanup
        self.cleanup = nil
        lock.unlock()
        cleanup?.cancel()
    }
}

extension Publisher {
    func mapToVoid() -> AnyPublisher<Void, Failure> {
        map { _ in () }.eraseToAnyPublisher()
    }

    func ignoreFailure() -> AnyPublisher<Output, Never> {
        self.catch { _ in Empty<Output, Never>() }.eraseToAnyPublisher()
    }

    /// Switching to the new publisher cancels the previous publisher immediately.
    func flatMapLatest<P: Publisher>(_ transform: @escaping (Output) -> P) -> AnyPublisher<P.Output, Failure>
        where P.Failure == Failure {
        map(transform).switchToLatest().eraseToAnyPublisher()
    }

    /// Shares one upstream connection and replays at most `count` recent values.
    func share(replay count: Int) -> AnyPublisher<Output, Failure> {
        precondition(count >= 0)
        return multicast(subject: NativeReplaySubject<Output, Failure>(capacity: count))
            .autoconnect()
            .eraseToAnyPublisher()
    }

    /// Only this publisher triggers output. Changes from `other` update the sample.
    /// The sampled publishers used by this application cannot fail.
    func withLatestFrom<P: Publisher>(_ other: P) -> AnyPublisher<P.Output, Failure> where P.Failure == Never {
        withLatestFrom(other) { _, latest in latest }
    }

    func withLatestFrom<P: Publisher, Result>(
        _ other: P,
        resultSelector: @escaping (Output, P.Output) -> Result
    ) -> AnyPublisher<Result, Failure> where P.Failure == Never {
        Deferred {
            let sample = NativeLatestSample<P.Output>()
            return self
                .handleEvents(receiveSubscription: { _ in sample.subscribe(to: other) })
                .compactMap { value in sample.read().map { resultSelector(value, $0) } }
                .handleEvents(receiveCompletion: { _ in sample.cancel() }, receiveCancel: { sample.cancel() })
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

private final class NativeLatestSample<Value> {
    private let lock = NSLock()
    // The outer optional distinguishes "not received" from a received Optional.none.
    private var latest: Value?
    private var subscription: AnyCancellable?
    private var cancelled = false

    func subscribe<P: Publisher>(to publisher: P) where P.Output == Value, P.Failure == Never {
        let token = publisher.sink { [weak self] value in
            guard let self else { return }
            self.lock.lock()
            if !self.cancelled { self.latest = .some(value) }
            self.lock.unlock()
        }
        lock.lock()
        if cancelled {
            lock.unlock()
            token.cancel()
        } else {
            subscription = token
            lock.unlock()
        }
    }

    func read() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let token = subscription
        subscription = nil
        latest = nil
        lock.unlock()
        token?.cancel()
    }
}

/// Small replaying subject for the application's shared notification streams.
/// Subscriber callbacks run outside the subject lock and respect downstream demand.
private final class NativeReplaySubject<Value, Failure: Error>: Subject {
    typealias Output = Value

    private let lock = NSLock()
    private let capacity: Int
    private var buffer: [Value] = []
    private var completion: Subscribers.Completion<Failure>?
    private var subscriptions: [UUID: NativeReplaySubscription<Value, Failure>] = [:]

    init(capacity: Int) {
        self.capacity = capacity
    }

    func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Failure {
        let id = UUID()
        lock.lock()
        let subscription = NativeReplaySubscription(
            downstream: AnySubscriber(subscriber), buffer: buffer, capacity: capacity,
            completion: completion, onEnd: { [weak self] in self?.remove(id) }
        )
        if completion == nil { subscriptions[id] = subscription }
        lock.unlock()
        subscriber.receive(subscription: subscription)
        subscription.activate()
    }

    func send(subscription: Subscription) {
        subscription.request(.unlimited)
    }

    func send(_ value: Value) {
        lock.lock()
        guard completion == nil else { lock.unlock(); return }
        if capacity > 0 {
            buffer.append(value)
            if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        }
        let active = Array(subscriptions.values)
        // Enqueue under the common lock so all subscribers see the same event order.
        active.forEach { $0.enqueue(value) }
        lock.unlock()
        active.forEach { $0.drain() }
    }

    func send(completion: Subscribers.Completion<Failure>) {
        lock.lock()
        guard self.completion == nil else { lock.unlock(); return }
        self.completion = completion
        let active = Array(subscriptions.values)
        subscriptions.removeAll()
        active.forEach { $0.enqueue(completion: completion) }
        lock.unlock()
        active.forEach { $0.drain() }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        subscriptions.removeValue(forKey: id)
        lock.unlock()
    }
}

private final class NativeReplaySubscription<Value, Failure: Error>: Subscription {
    private let lock = NSLock()
    private let capacity: Int
    private let waitsForBufferedDemand: Bool
    private var downstream: AnySubscriber<Value, Failure>?
    private var buffer: [Value]
    private var completion: Subscribers.Completion<Failure>?
    private var demand: Subscribers.Demand = .none
    private var isReady = false
    private var isDraining = false
    private var onEnd: (() -> Void)?

    init(downstream: AnySubscriber<Value, Failure>, buffer: [Value], capacity: Int,
         completion: Subscribers.Completion<Failure>?, waitsForBufferedDemand: Bool = false,
         onEnd: @escaping () -> Void) {
        self.downstream = downstream
        self.buffer = buffer
        self.capacity = capacity
        self.waitsForBufferedDemand = waitsForBufferedDemand
        self.completion = completion
        self.onEnd = onEnd
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return downstream != nil && completion == nil
    }

    func activate() {
        lock.lock()
        isReady = true
        lock.unlock()
        drain()
    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > .none else { return }
        lock.lock()
        self.demand += demand
        lock.unlock()
        drain()
    }

    func cancel() {
        lock.lock()
        downstream = nil
        buffer.removeAll()
        completion = nil
        let onEnd = self.onEnd
        self.onEnd = nil
        lock.unlock()
        onEnd?()
    }

    func enqueue(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        guard downstream != nil, completion == nil else { return }
        buffer.append(value)
        if let requested = demand.max {
            // A slow subscriber retains only its outstanding demand plus replay.
            let limit = requested > Int.max - capacity ? Int.max : requested + capacity
            if buffer.count > limit { buffer.removeFirst(buffer.count - limit) }
        }
    }

    func enqueue(completion: Subscribers.Completion<Failure>) {
        lock.lock()
        self.completion = completion
        lock.unlock()
    }

    func drain() {
        lock.lock()
        guard isReady, !isDraining else { lock.unlock(); return }
        isDraining = true
        while let downstream {
            if demand > .none, !buffer.isEmpty {
                let value = buffer.removeFirst()
                demand -= 1
                lock.unlock()
                let additionalDemand = downstream.receive(value)
                lock.lock()
                demand += additionalDemand
            } else if let completion, buffer.isEmpty || (!waitsForBufferedDemand && demand == .none) {
                self.downstream = nil
                // A terminal event does not require demand. Pending replay is
                // delivered first only when the subscriber has requested it.
                buffer.removeAll()
                self.completion = nil
                let onEnd = self.onEnd
                self.onEnd = nil
                isDraining = false
                lock.unlock()
                onEnd?()
                downstream.receive(completion: completion)
                return
            } else {
                break
            }
        }
        isDraining = false
        lock.unlock()
    }
}
