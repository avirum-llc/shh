import Foundation
import Network

extension NWConnection {
    /// Await the next chunk of bytes. Returns an empty `Data` when the
    /// peer closed cleanly.
    func receiveAsync(min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            self.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: data ?? Data())
                }
            }
        }
    }

    /// Write `data`. Pass `isComplete: true` to signal end-of-stream.
    func sendAsync(_ data: Data, isComplete: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: isComplete,
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            )
        }
    }
}
