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
./scripts/install.sh   # build, install to ~/.local/bin, register LaunchAgent
./scripts/uninstall.sh # stop agent, remove plist and binary
```

## Foreground / logs

```bash
swift run quote        # run in foreground (e.g. in tmux)
tail -f ~/Library/Logs/quote.log   # when using install.sh
```
