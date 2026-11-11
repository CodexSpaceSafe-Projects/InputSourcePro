import Combine
import XCTest
@testable import Input_Source_Pro

final class NativeCombineTests: XCTestCase {
    func testCallbackFactoryCleansUpAfterSynchronousFirstCancelsDuringSetup() {
        var cleanups = 0
        var values: [Int] = []
        let source = AnyPublisher<Int, Never>.create { emitter in
            emitter.send(1)
            emitter.send(2)
            return AnyCancellable { cleanups += 1 }
        }
        let subscription = source.first().sink { values.append($0) }
        XCTAssertEqual(values, [1])
        XCTAssertEqual(cleanups, 1)
        subscription.cancel()
        XCTAssertEqual(cleanups, 1)
    }

    func testCallbackFactoryStopsDeliveryAndRunsCleanupOnceAfterCancellation() {
        var callback: NativePublisherEmitter<Int, Never>?
        var cleanups = 0
        var values: [Int] = []
        let source = AnyPublisher<Int, Never>.create { emitter in
            callback = emitter
            return AnyCancellable { cleanups += 1 }
        }
        let subscription = source.sink { values.append($0) }
        callback?.send(1)
        subscription.cancel()
        callback?.send(2)
        callback?.send(completion: .finished)
        subscription.cancel()
        XCTAssertEqual(values, [1])
        XCTAssertEqual(cleanups, 1)
    }

    func testCallbackFactoryBuffersSynchronousValuesUntilDemandThenFinishes() {
        var cleanups = 0
        let source = AnyPublisher<Int, Never>.create { emitter in
            emitter.send(1)
            emitter.send(2)
            emitter.send(completion: .finished)
            return AnyCancellable { cleanups += 1 }
        }
        let subscriber = LimitedSubscriber<Int>()
        source.subscribe(subscriber)
        XCTAssertTrue(subscriber.values.isEmpty)
        XCTAssertEqual(subscriber.events, ["subscription-start", "subscription-end"])
        XCTAssertEqual(cleanups, 1)
        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(subscriber.values, [1])
        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(subscriber.values, [1, 2])
        XCTAssertEqual(subscriber.events.last, "completion")
        XCTAssertEqual(cleanups, 1)
    }

    func testCallbackFactoryDoesNotStartAfterCancellationDuringSubscription() {
        var starts = 0
        let source = AnyPublisher<Int, Never>.create { _ in
            starts += 1
            return AnyCancellable {}
        }
        let subscriber = LimitedSubscriber<Int>()
        subscriber.onSubscription = { [weak subscriber] in subscriber?.subscription?.cancel() }
        source.subscribe(subscriber)
        XCTAssertEqual(starts, 0)
    }

    func testReplaySharesOneConnectionAndCancelsAfterLastSubscriber() {
        let source = PassthroughSubject<Int, Never>()
        var connections = 0
        var cancellations = 0
        let shared = source
            .handleEvents(receiveSubscription: { _ in connections += 1 }, receiveCancel: { cancellations += 1 })
            .share(replay: 1)
        var first: [Int] = []
        var second: [Int] = []
        let a = shared.sink { first.append($0) }
        source.send(1)
        source.send(2)
        let b = shared.sink { second.append($0) }

        XCTAssertEqual(connections, 1)
        XCTAssertEqual(first, [1, 2])
        XCTAssertEqual(second, [2])
        a.cancel()
        XCTAssertEqual(cancellations, 0)
        source.send(3)
        XCTAssertEqual(second, [2, 3])
        b.cancel()
        XCTAssertEqual(cancellations, 1)
    }

    func testReplayRespectsDemandAndKeepsTheMostRecentPendingValue() {
        let source = PassthroughSubject<Int, Never>()
        let shared = source.share(replay: 1)
        let keeper = shared.sink { _ in }
        source.send(1)
        source.send(2)
        let subscriber = LimitedSubscriber<Int>()
        shared.subscribe(subscriber)
        XCTAssertEqual(subscriber.values, [])
        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(subscriber.values, [2])
        source.send(3)
        source.send(4)
        XCTAssertEqual(subscriber.values, [2])
        subscriber.subscription?.request(.max(1))
        XCTAssertEqual(subscriber.values, [2, 4])
        subscriber.subscription?.cancel()
        keeper.cancel()
    }

    func testZeroReplayDoesNotSendAnOldValueToALateSubscriber() {
        let source = PassthroughSubject<Int, Never>()
        let shared = source.share(replay: 0)
        let keeper = shared.sink { _ in }
        source.send(1)
        var values: [Int] = []
        let late = shared.sink { values.append($0) }
        XCTAssertTrue(values.isEmpty)
        source.send(2)
        XCTAssertEqual(values, [2])
        late.cancel()
        keeper.cancel()
    }

    func testReplayDeliversBufferedValueAndTerminalFailureToLateSubscriber() {
        enum Failure: Error { case failed }
        let source = PassthroughSubject<Int, Failure>()
        let shared = source.share(replay: 1)
        let keeper = shared.sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        source.send(7)
        source.send(completion: .failure(.failed))
        var values: [Int] = []
        var failed = false
        let late = shared.sink(receiveCompletion: {
            if case .failure = $0 { failed = true }
        }, receiveValue: { values.append($0) })
        XCTAssertEqual(values, [7])
        XCTAssertTrue(failed)
        late.cancel()
        keeper.cancel()
    }

    func testCompletionDoesNotWaitForDemandOrPrecedeSubscriptionDelivery() {
        let source = PassthroughSubject<Int, Never>()
        let shared = source.share(replay: 1)
        let keeper = shared.sink { _ in }
        source.send(1)
        let subscriber = LimitedSubscriber<Int>()
        subscriber.onSubscription = { source.send(completion: .finished) }
        shared.subscribe(subscriber)

        XCTAssertEqual(subscriber.events, ["subscription-start", "subscription-end", "completion"])
        XCTAssertTrue(subscriber.values.isEmpty)
        keeper.cancel()
    }

    func testSampleChangesDoNotTriggerOutputAndCancellationStopsSampling() {
        let triggers = PassthroughSubject<Int, Never>()
        let sampled = CurrentValueSubject<String, Never>("initial")
        var cancellations = 0
        var values: [String] = []
        let subscription = triggers
            .withLatestFrom(sampled.handleEvents(receiveCancel: { cancellations += 1 })) { "\($0):\($1)" }
            .sink { values.append($0) }
        triggers.send(1)
        sampled.send("updated")
        XCTAssertEqual(values, ["1:initial"])
        triggers.send(2)
        XCTAssertEqual(values, ["1:initial", "2:updated"])
        subscription.cancel()
        XCTAssertEqual(cancellations, 1)
    }

    func testSamplingDistinguishesMissingValueFromOptionalNil() {
        let triggers = PassthroughSubject<Void, Never>()
        let sampled = PassthroughSubject<Int?, Never>()
        var values: [Int?] = []
        let subscription = triggers.withLatestFrom(sampled).sink { values.append($0) }
        triggers.send(())
        XCTAssertEqual(values.count, 0)
        sampled.send(nil)
        triggers.send(())
        XCTAssertEqual(values.count, 1)
        XCTAssertNil(values[0])
        subscription.cancel()
    }

    func testLatestSwitchCancelsOldWorkAndDownstreamCancellationStopsCurrentWork() {
        let requests = PassthroughSubject<PassthroughSubject<Int, Never>, Never>()
        let old = PassthroughSubject<Int, Never>()
        let current = PassthroughSubject<Int, Never>()
        var cancellations = 0
        var values: [Int] = []
        let subscription = requests
            .flatMapLatest { $0.handleEvents(receiveCancel: { cancellations += 1 }) }
            .sink { values.append($0) }
        requests.send(old)
        old.send(1)
        requests.send(current)
        XCTAssertEqual(cancellations, 1)
        old.send(2)
        current.send(3)
        XCTAssertEqual(values, [1, 3])
        subscription.cancel()
        XCTAssertEqual(cancellations, 2)
    }
}

private final class LimitedSubscriber<Value>: Subscriber {
    typealias Input = Value
    typealias Failure = Never
    var subscription: Subscription?
    var values: [Value] = []
    var events: [String] = []
    var onSubscription: (() -> Void)?

    func receive(subscription: Subscription) {
        events.append("subscription-start")
        self.subscription = subscription
        onSubscription?()
        events.append("subscription-end")
    }

    func receive(_ input: Value) -> Subscribers.Demand {
        values.append(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Never>) {
        events.append("completion")
    }
}
