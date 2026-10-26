// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class DownloadProgressTests: XCTestCase {
    private func record(_ title: String, _ state: DownloadRecord.State, progress: Double = 0, waiting: Bool? = nil) -> DownloadRecord {
        var record = DownloadRecord(item: BrowseItem(contentID: "dQw4w9WgXcQ", kind: .video, title: title),
                                    choice: DownloadChoice(id: "hls", name: "HLS", kind: .hls))
        record.state = state; record.progress = progress; record.waitingForNetwork = waiting
        return record
    }
    func testSummaryCoversOnlyRunningJobsAndAveragesProgress() throws {
        XCTAssertNil(DownloadSummary.of([record("Done", .completed, progress: 1), record("Gone", .cancelled), record("Bad", .failed)]))
        let one = try XCTUnwrap(DownloadSummary.of([record("Song", .downloading, progress: 0.426)]))
        XCTAssertEqual(one.title, "Song"); XCTAssertEqual(one.detail, "42%"); XCTAssertEqual(one.progress ?? 0, 0.426, accuracy: 0.0001)
        XCTAssertEqual(one.state, .active)
        let two = try XCTUnwrap(DownloadSummary.of([record("A", .downloading, progress: 0.5), record("B", .preparing), record("C", .completed, progress: 1)]))
        XCTAssertEqual(two.count, 2); XCTAssertEqual(two.detail, "50% · 1 more"); XCTAssertEqual(two.progress ?? 0, 0.25, accuracy: 0.0001)
    }
    func testWaitingAndPreparingHaveNoProgressYet() throws {
        let waiting = try XCTUnwrap(DownloadSummary.of([record("A", .preparing, waiting: true)]))
        XCTAssertEqual(waiting.detail, "Waiting for network"); XCTAssertNil(waiting.progress)
        XCTAssertEqual(DownloadSummary.of([record("A", .preparing)])?.detail, "Preparing")
        XCTAssertEqual(ActiveDownload(id: UUID(), title: "x", progress: .nan, phase: .downloading).progress, 0)
        XCTAssertEqual(ActiveDownload(id: UUID(), title: "x", progress: 3, phase: .downloading).progress, 1)
    }
    func testFinishedStatesAndCodableRoundTrip() throws {
        let done = DownloadSummary.finished("Song", failed: false)
        XCTAssertEqual(done.state, .finished); XCTAssertEqual(done.progress, 1)
        XCTAssertEqual(DownloadSummary.finished("Song", failed: true).detail, "Download failed")
        XCTAssertEqual(try JSONDecoder().decode(DownloadSummary.self, from: JSONEncoder().encode(done)), done)
    }
}
