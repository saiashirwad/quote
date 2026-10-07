# quote

Background macOS utility: global hotkeys, a small floating note box, and a Markdown file of stacked notes.

## Hotkeys

| Shortcut | Action |
|----------|--------|
| ⌘G | Open the box (type) |
| ⌘E | Open the box and start dictation |
| ⌃⌘V | Copy all notes to the pasteboard and clear the file |

Select text and press ⌘C in any app before ⌘G/⌘E to attach it as a block quote on save.

## Notes file

Path: `QUOTE_FILE` environment variable, or `~/notes/quote.md` by default. Send writes a backup to `quote.last.md` in the same folder.

## Install / uninstall

```bash
./scripts/install.sh   # build, install to ~/.local/bin, register LaunchAgent
./scripts/uninstall.sh # stop agent, remove plist and binary
```

## Foreground / logs

```bash
swift run quote          # run in a terminal or tmux session
tail -f ~/Library/Logs/quote.log   # when using install.sh
```

Enable **Keyboard → Dictation** in System Settings for ⌘E talk mode.
