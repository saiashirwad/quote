@testable import quote
import XCTest

final class NoteFileTests: XCTestCase {
    func testQuoteAndNote() {
        let out = Notes.entry(quote: "line one\nline two", note: "my note")
        XCTAssertEqual(
            out,
            """
            > line one
            > line two

            my note

            ---

            """
        )
    }

    func testNoteOnly() {
        let out = Notes.entry(quote: nil, note: "standalone")
        XCTAssertEqual(
            out,
            """
            standalone

            ---

            """
        )
    }

    func testQuoteOnly() {
        let out = Notes.entry(quote: "quoted", note: "   ")
        XCTAssertEqual(
            out,
            """
            > quoted

            ---

            """
        )
    }

    func testBothEmpty() {
        XCTAssertNil(Notes.entry(quote: nil, note: "   "))
        XCTAssertNil(Notes.entry(quote: "  ", note: ""))
    }

    func testMultilineQuoteWithBlankLine() {
        let out = Notes.entry(quote: "a\n\nb", note: "n")
        XCTAssertEqual(
            out,
            """
            > a
            >
            > b

            n

            ---

            """
        )
    }

    func testAppendToEmpty() {
        let entry = Notes.entry(quote: nil, note: "x")!
        let merged = Notes.append(entry, to: "")
        XCTAssertEqual(merged, entry)
    }

    func testAppendToExisting() {
        let existing = "old\n\n---\n\n"
        let entry = Notes.entry(quote: "q", note: "n")!
        let merged = Notes.append(entry, to: existing)
        XCTAssertTrue(merged.hasPrefix("old"))
        XCTAssertTrue(merged.hasSuffix(entry))
    }
}
