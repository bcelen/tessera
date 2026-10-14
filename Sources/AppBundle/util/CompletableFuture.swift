import Dispatch

final class CompletableFuture<T>: Sendable {
    nonisolated(unsafe) private var value: T?
    private let semaphore = DispatchSemaphore(value: 0)

    func complete(_ t: T) {
        unsafe value = t
        semaphore.signal()
    }

    /// nil if nothing completed the future in time
    func blockingGet(timeout: DispatchTimeInterval) -> T? {
        switch semaphore.wait(timeout: .now() + timeout) {
            case .success: unsafe value
            case .timedOut: nil
        }
    }
}
