# quote

Background macOS utility: global hotkeys, a small floating note box, and a Markdown file of stacked notes.

## Hotkeys

| Shortcut | Action |
|----------|--------|
| ⌘G | Open the note box |
| ⌘↩ | Save (in the box) |
| Esc | Cancel |
| ⌃⌘V | Copy all notes to the pasteboard and clear the file |

Select text and press ⌘C in any app before ⌘G to attach it as a block quote on save.

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
