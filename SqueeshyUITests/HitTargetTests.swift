import XCTest

/// Where inside a control does a tap actually register?
///
/// The complaint was that tiles and buttons sometimes need tapping two or three times.
/// `.buttonStyle(.plain)` hit-tests only the pixels a label draws, so padding, the gap a
/// `Spacer` opens and the ring of a fixed frame around a small glyph are all dead. Which
/// meant whether a tap worked came down to whether a finger landed on a word.
///
/// These probe the corners and the empty middles, not the obvious centre — a test that
/// taps where XCUITest aims by default would have passed throughout.
final class HitTargetTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSeed"]
    }

    private func launchToCollections() {
        app.launch()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Everything").firstMatch
            .waitForExistence(timeout: 20), "collections never loaded")
    }

    private func tap(_ element: XCUIElement, dx: CGFloat, dy: CGFloat) {
        element.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    /// A shelf row: an icon, two labels, a `Spacer`, a chevron. The `Spacer` was dead.
    func testShelfRowRespondsAcrossItsWholeWidth() {
        var dead: [String] = []
        for (dx, label) in [(0.06, "left edge"), (0.10, "thumbnail"), (0.30, "title"),
                            (0.50, "middle"), (0.70, "empty right half"),
                            (0.85, "before the chevron"), (0.96, "right edge")] {
            launchToCollections()
            let row = app.buttons.containing(.staticText, identifier: "Everything").firstMatch
            tap(row, dx: CGFloat(dx), dy: 0.5)
            if !app.buttons["Colour"].waitForExistence(timeout: 4) {
                dead.append("\(label) (dx=\(dx))")
            }
            app.terminate()
        }
        XCTAssertTrue(dead.isEmpty, "dead points in a shelf row: \(dead.joined(separator: ", "))")
    }

    // Two other probes lived here — one on the header's 38pt circular buttons, one on
    // the trait tabs. Both passed against the broken build as well as the fixed one, so
    // they were asserting nothing: a `.frame` around a glyph and a `.frame` around a
    // `Text` both already take touches across their whole area. Only a `Spacer` is dead.
    // Deleted rather than left in place looking like coverage.
}
