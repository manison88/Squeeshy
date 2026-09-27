import XCTest

/// Guards the thing that keeps breaking: a control is wired up and compiles, and the
/// sheet it opens never appears because SwiftUI kept only the first `.sheet` on that
/// view and silently dropped the rest. Nothing but a tap can see that.
final class PresentationTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Reset first: these tests rename squeeshies and pin shelves, and without a
        // clean store each one would inherit the last one's mess.
        app.launchArguments = ["-uiTestReset", "-uiTestSeed"]
    }

    // MARK: Helpers

    /// Reaches a squeeshy's detail view by searching for it and tapping the result —
    /// the same route a person takes. Deliberately not the `-openItem` deep link: that
    /// posts its selection on a timer and drops it if the push has not settled, so a
    /// test built on it fails for reasons that have nothing to do with the assertion.
    private func openMochi(file: StaticString = #filePath, line: UInt = #line) {
        app.launch()
        let search = app.textFields["Search your shelf"]
        tap(search, "the search field", file: file, line: line)
        search.typeText("Mochi")
        tap(app.buttons.containing(.staticText, identifier: "Mochi").firstMatch,
            "the Mochi search result", file: file, line: line)

        // MetaLabel uppercases its text, so that is what accessibility reports.
        XCTAssertTrue(app.staticTexts["CARD 1 OF 3"].waitForExistence(timeout: 20),
                      "never reached a squeeshy's detail view", file: file, line: line)
    }

    private func tap(_ element: XCUIElement, _ what: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10),
                      "\(what) never appeared", file: file, line: line)
        element.tap()
    }

    // MARK: Tests

    /// The reported bug: both menu items flashed and did nothing.
    func testAddToCollectionOpensFromItemMenu() {
        openMochi()
        tap(app.buttons["itemMenu"], "the item ··· menu")
        tap(app.buttons["Add to collection"], "the Add to collection menu item")

        XCTAssertTrue(app.staticTexts["Add to"].waitForExistence(timeout: 10),
                      "Add to collection was tapped but no sheet opened")
    }

    func testDeleteSqueeshyAsksForConfirmation() {
        openMochi()
        tap(app.buttons["itemMenu"], "the item ··· menu")
        tap(app.buttons["Delete squeeshy"], "the Delete squeeshy menu item")

        XCTAssertTrue(app.staticTexts["Delete this squeeshy?"].waitForExistence(timeout: 10),
                      "Delete was tapped but no confirmation appeared")
    }

    /// Declared after the share sheet, so it was dropped by the same bug even though
    /// nobody had reported it yet.
    func testRatingSheetOpens() {
        openMochi()
        tap(app.buttons.containing(.staticText, identifier: "Squeeshiness").firstMatch,
            "the Squeeshiness button")

        XCTAssertTrue(app.staticTexts["SQUEESHINESS"].waitForExistence(timeout: 10),
                      "the rating sheet did not open")
    }

    /// Same again for the trait chips.
    func testTraitChipOpensEditor() {
        openMochi()
        tap(app.buttons["Medium"], "the size chip")

        XCTAssertTrue(app.staticTexts["SIZE"].waitForExistence(timeout: 10),
                      "the trait editor did not open")
    }

    /// Play mode is opened by a tap on the hero, which sits under a drag gesture for
    /// squeezing — exactly the arrangement where one gesture swallows the other.
    func testTappingHeroOpensPlayMode() {
        openMochi()
        // By identifier, not `app.images.firstMatch`: a drawn squeeshy is a Canvas
        // rather than an Image, so the loose query matched something else entirely.
        let hero = app.descendants(matching: .any)["hero"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 10), "no hero squeeshy to tap")
        hero.tap()

        // Play mode shows the squeeshy's name and a Done button and nothing else.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10),
                      "tapping the squeeshy did not open play mode")

        // And it must be squeezable: press and drag across it without anything crashing
        // or dismissing.
        let toy = app.descendants(matching: .any)["playToy"].firstMatch
        XCTAssertTrue(toy.waitForExistence(timeout: 10), "no squeeshy to squeeze")
        toy.press(forDuration: 0.4, thenDragTo: toy)
        XCTAssertTrue(app.buttons["Done"].exists, "squeezing dismissed play mode")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["CARD 1 OF 3"].waitForExistence(timeout: 10),
                      "Done did not return to the detail screen")
    }

    /// Renaming in place. The name is a Button for the same reason the hero is.
    func testTappingNameRenamesSqueeshy() {
        openMochi()
        tap(app.buttons["heroName"], "the squeeshy's name")

        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "tapping the name did not open an editable field")
        // Clear first: typeText appends, so this would otherwise produce "MochiRennamed".
        // Deletes are more dependable here than the Select All edit menu.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        field.typeText("Rennamed")
        app.keyboards.buttons["done"].firstMatch.tap()

        XCTAssertTrue(app.buttons["heroName"].waitForExistence(timeout: 10),
                      "the field never committed back to a label")
        // The Button carries an accessibilityLabel, which replaces the inner Text, so
        // there is no separate staticText to look for — assert on the button's label.
        XCTAssertEqual(app.buttons["heroName"].label, "Rennamed, tap to rename",
                       "the new name was not saved")
    }

    /// Pinning moves a collection into its own section above Smart shelves. Driven from
    /// the menu inside the collection, not a long press on the row: a long press on a
    /// NavigationLink activates the link instead of opening its context menu.
    func testPinningAShelfMovesItToPinned() {
        app.launch()
        tap(app.buttons.containing(.staticText, identifier: "Test shelf").firstMatch,
            "the hand-made shelf row")
        tap(app.buttons["shelfMenu"], "the collection ··· menu")
        tap(app.buttons["Pin to top"], "the Pin to top menu item")

        // Back out to the list, where a Pinned section should now exist.
        tap(app.buttons["Back"], "the back button")
        XCTAssertTrue(app.staticTexts["PINNED"].waitForExistence(timeout: 10),
                      "pinning did not produce a Pinned section")
    }

    /// One button, three states, in order. Worth pinning because the icon is the only
    /// thing telling you which mode you are in.
    func testThemeTogglesCycle() {
        app.launch()
        let toggle = app.buttons["themeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "no theme toggle in the header")

        // Starts on Dark; the accessibility label is what names the current mode.
        XCTAssertEqual(toggle.label, "Appearance: Dark")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Appearance: Light")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Appearance: Auto")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Appearance: Dark")
    }

    /// The collection menu had the identical collision.
    func testCollectionMenuOpensContentsPicker() {
        app.launch()
        tap(app.buttons.containing(.staticText, identifier: "Test shelf").firstMatch,
            "the hand-made shelf row")
        tap(app.buttons["shelfMenu"], "the collection ··· menu")
        tap(app.buttons["Choose squeeshies"], "the Choose squeeshies menu item")

        XCTAssertTrue(app.staticTexts["on this shelf"].waitForExistence(timeout: 10)
                      || app.staticTexts["Test shelf"].waitForExistence(timeout: 10),
                      "the contents picker did not open")
    }
}
