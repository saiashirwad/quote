# quote

Background macOS hotkey utility: a floating note box and a Markdown file of stacked notes.

| Shortcut | Action |
|----------|--------|
| ⌘G | Open the note box |
| ⌘↩ | Save |
| Esc / click away | Cancel |
| ⌃⌘V | Copy all notes to the pasteboard and clear the file |

On ⌘G, Quote reads the front app’s selection via Accessibility (grant once in **System Settings → Privacy & Security → Accessibility**) — browsers, PDFs, and most native apps. If nothing is selected, it uses the clipboard when it changed since your last saved note. Terminals rarely expose selection; use copy-on-select (Ghostty: `copy-on-select = clipboard`).

Notes live at `QUOTE_FILE` or `~/notes/quote.md`. Send writes the previous contents to `quote.last.md` in the same folder, then clears the notes file.

```bash
make dev          # build Quote.app, run with logs in .build/dev.log
make install      # ~/Applications + LaunchAgent
make uninstall
```

Installed logs: `~/Library/Logs/quote.log`. macOS Dictation (fn-fn) works in the box when Quote runs as `Quote.app`.
