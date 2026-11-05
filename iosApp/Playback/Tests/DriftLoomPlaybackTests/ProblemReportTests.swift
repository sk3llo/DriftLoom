// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import DriftLoomPlayback

final class ProblemReportTests: XCTestCase {
    private let environment = [ProblemReport.Detail("App", "1.0 (42)"), ProblemReport.Detail("iOS", "15.8.2"), ProblemReport.Detail("Device", "iPhone9,3")]

    func testIssueLinkIsPrefilled() throws {
        let report = ProblemReport(area: "Playback", error: "The video can't be played (403).\nTry again.",
                                   context: [.init("Video", "https://youtu.be/dQw4w9WgXcQ")])
        let url = report.issueURL(environment: environment)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/sk3llo/DriftLoom/issues/new")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "[iOS] Playback: The video can't be played (403). Try again.")
        // The repository only takes template issues, so the text goes into the form's fields by id, not `body`.
        XCTAssertEqual(items.first { $0.name == "template" }?.value, "app_report.yml")
        XCTAssertNil(items.first { $0.name == "body" })
        XCTAssertEqual(items.first { $0.name == "error" }?.value, "The video can't be played (403).\nTry again.")
        let details = try XCTUnwrap(items.first { $0.name == "details" }?.value)
        XCTAssertTrue(details.contains("| Video | https://youtu.be/dQw4w9WgXcQ |"))
        XCTAssertTrue(details.contains("| Device | iPhone9,3 |"))
    }

    func testPlusSignsAndPipesSurvive() throws {
        let report = ProblemReport(area: "Search", error: "C++ | tutorials", context: [.init("Query", "a|b")])
        let url = report.issueURL(environment: [])
        XCTAssertTrue(url.absoluteString.contains("C%2B%2B"), "A + would read as a space on GitHub")
        let details = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "details" }?.value)
        XCTAssertTrue(details.contains("| Query | a\\|b |"), "Pipes don't break the table")
    }

    func testLongErrorsAreShortenedToFitALink() {
        let report = ProblemReport(area: "Browsing", error: String(repeating: "é long error ", count: 2000))
        let url = report.issueURL(environment: environment)
        XCTAssertLessThanOrEqual(url.absoluteString.count, ProblemReport.maximumURLLength)
        XCTAssertTrue(report.title.count < 100)
    }

    func testGeneralReportHasNoErrorSection() {
        let body = ProblemReport(area: "General").body(environment: environment)
        XCTAssertFalse(body.contains("### Error"))
        XCTAssertTrue(body.contains("### What happened") && body.contains("| Area | General |"))
        let items = URLComponents(url: ProblemReport(area: "General").issueURL(environment: environment), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertNil(items.first { $0.name == "error" })
        XCTAssertEqual(ProblemReport(area: "General").title, "[iOS] General")
    }
}
