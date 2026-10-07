import QuoteFileLogic
import XCTest

final class NoteFileTests: XCTestCase {
    func testQuoteAndNote() {
        let out = NoteFile.format(quote: "line one\nline two", note: "my note")
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
        let out = NoteFile.format(quote: nil, note: "standalone")
        XCTAssertEqual(
            out,
            """
            standalone

            ---

            """
        )
    }

    func testQuoteOnly() {
        let out = NoteFile.format(quote: "quoted", note: "   ")
        XCTAssertEqual(
            out,
            """
            > quoted

            ---

            """
        )
    }

    func testMultilineQuoteWithBlankLine() {
        let out = NoteFile.format(quote: "a\n\nb", note: "n")
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
        let entry = NoteFile.format(quote: nil, note: "x")
        let merged = NoteFile.append(entry: entry, toExisting: "")
        XCTAssertEqual(merged, entry)
    }

    func testAppendToExisting() {
        let existing = "old\n\n---\n\n"
        let entry = NoteFile.format(quote: "q", note: "n")
        let merged = NoteFile.append(entry: entry, toExisting: existing)
        XCTAssertTrue(merged.hasPrefix("old"))
        XCTAssertTrue(merged.hasSuffix(entry))
    }
}
