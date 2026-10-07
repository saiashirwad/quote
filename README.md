# quote

Background macOS utility: global hotkeys, a small floating note box, and a Markdown file of stacked notes.

## Hotkeys

| Shortcut | Action |
|----------|--------|
| ⌘G | Open the note box |
| ⌘↩ | Save (in the box) |
| Esc | Cancel |
| ⌃⌘V | Copy all notes to the pasteboard and clear the file |

When you press ⌘G, Quote tries to read the front app’s selected text (Accessibility — grant Quote once in **System Settings → Privacy & Security → Accessibility**). That works in browsers, PDF viewers, and native apps with a normal selection. If nothing is selected there, it falls back to the clipboard when its contents changed since your last saved note. Terminals usually don’t expose selection to Accessibility; use copy-on-select instead (e.g. Ghostty: `copy-on-select = clipboard`).

## Notes file

Path: `QUOTE_FILE` environment variable, or `~/notes/quote.md` by default. Send writes a backup to `quote.last.md` in the same folder.

## Install / uninstall

```bash
./scripts/install.sh   # build Quote.app, install to ~/Applications, register LaunchAgent
./scripts/uninstall.sh # stop agent, remove plist and app
```

## Development / logs

```bash
./scripts/dev.sh       # build Quote.app and run via LaunchServices (for tmux)
swift run quote        # typing works; macOS Dictation (fn-fn) in the box needs the app bundle
tail -f ~/Library/Logs/quote.log   # when using install.sh
```

System Dictation (fn-fn) works in the note box when Quote runs as `Quote.app`, because macOS can attach dictation to a real app identity.
