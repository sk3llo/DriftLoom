// SPDX-License-Identifier: GPL-3.0-or-later
import Combine
import Foundation
import Network
import XCTest
@testable import DriftLoomPlayback

private final class ForbiddenServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "DriftLoom.ForbiddenStreamTest")

    private let statusCode: Int
    private let lock = NSLock()
    private var completionClaimed = false

    init(statusCode: Int) throws {
        self.statusCode = statusCode
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    private func claimCompletion() -> Bool {
        lock.withLock {
            guard !completionClaimed else { return false }
            completionClaimed = true
            return true
        }
    }
    deinit { listener.cancel() }

    func start() async throws -> URL {
        let statusCode = self.statusCode
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { _, _, _, _ in
                let response = Data("HTTP/1.1 \(statusCode) Rejected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port, self.claimCompletion() else { return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/stream.m3u8")!)
                case let .failed(error):
                    guard self.claimCompletion() else { return }
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }
}

private actor ForbiddenResolver: StreamResolving {
    let url: URL
    private(set) var count = 0
    init(url: URL) { self.url = url }
    func resolve(_ request: VideoRequest) async throws -> ResolvedVideo {
        count += 1
        return ResolvedVideo(title: "Forbidden test", streamURL: url, usesHLS: true)
    }
}

@MainActor
final class ForbiddenStreamTests: XCTestCase {
    func testRealHTTP403RefreshesOnceAndThenStops() async throws {
        try await checkStatus(403, expectedResolutions: 2)
    }

    func testRealHTTP404DoesNotRefresh() async throws {
        try await checkStatus(404, expectedResolutions: 1)
    }

    private func checkStatus(_ status: Int, expectedResolutions: Int) async throws {
        let server = try ForbiddenServer(statusCode: status)
        let resolver = ForbiddenResolver(url: try await server.start())
        let session = PlaybackSession(resolver: resolver)
        let failed = expectation(description: "A second forbidden response ends recovery")
        var receivedFailure = false
        let observation = session.$phase.sink { phase in
            if case .failed = phase, !receivedFailure {
                receivedFailure = true
                failed.fulfill()
            }
        }
        session.open("11-9ZaYiTPE")
        await fulfillment(of: [failed], timeout: 15)
        let resolutions = await resolver.count
        XCTAssertEqual(resolutions, expectedResolutions)
        XCTAssertEqual(session.didRecover, status == 403)
        session.stop()
        observation.cancel()
        server.listener.cancel()
    }
}
