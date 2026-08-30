# Clipwell

A macOS clipboard manager that keeps **everything** you copy — not just text.
Images, rich text, files, colours, links and code all get captured, searched and
pasted back with full fidelity.

Menu-bar only. No dock icon, no external dependencies, no network access.

---

## Build

Requires macOS 13+ and the Xcode command line tools.

```bash
./build.sh --run        # test, build, assemble Clipwell.app, launch it
./build.sh --install    # build and copy to /Applications
./build.sh              # build only, leaves it in dist/
swift test              # just the test suite
```

There are no package dependencies, so the build works offline.

### Signing (do this once)

macOS ties the Accessibility permission to an app's **code signature**. An
ad-hoc signature changes every time the binary changes, so without a stable
identity macOS treats each rebuild as a brand new app and silently drops the
permission — auto-paste just stops working until you re-grant it.

```bash
./scripts/make-signing-cert.sh          # asks for your admin password once
echo 'export CLIPWELL_SIGN_IDENTITY="Clipwell Local Signing"' >> ~/.zshrc
```

Then rebuild and grant Accessibility once, in
System Settings → Privacy & Security → Accessibility.

Skipping this is fine if you don't want auto-paste — Clipwell still puts the
item on the clipboard and you press <kbd>⌘V</kbd> yourself.

---

## Use

<kbd>⌘⇧V</kbd> opens the history panel. Start typing to search.

| Key | Action |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Move selection |
| <kbd>⏎</kbd> | Paste |
| <kbd>⌥⏎</kbd> | Paste as plain text |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | Paste the Nth item directly |
| <kbd>⌘P</kbd> | Pin / unpin |
| <kbd>⌫</kbd> | Delete (when search is empty) |
| <kbd>⇥</kbd> | Toggle list / grid view |
| <kbd>esc</kbd> | Close |

Screenshots are searchable by the text inside them — type "invoice" and the
screenshot of an invoice comes back.

Right-click the menu bar icon for settings, pause, and quit.

---

## How it works

### Items are a bag of representations, not a single type

The central design decision, and the reason "just add images" to a text-only
manager isn't a small change.

A single copy publishes **several representations at once**. Copy a cell range
from Excel and the pasteboard carries RTF, HTML, plain text *and* a TIFF
simultaneously. A text-only manager grabs `.string` and discards the rest, so
pasting later loses all formatting.

Clipwell stores every UTI it finds, across every pasteboard item, and restores
all of them on paste. A `kind` (image, code, link…) is attached purely for
display and filtering — it never determines what gets stored.

### Classification

Ordering matters where representations conflict. The genuinely ambiguous case
is "image *and* text together", which happens in two opposite situations:

- Copy a range from Excel → RTF + HTML + text + TIFF. You want the **text**.
- Copy an image in Safari → TIFF + the image's URL as text. You want the **image**.

What separates them is whether the text is real content or a bare URL tagging
along with the picture, so that's what `ContentClassifier` tests.

### Size discipline

A text history is a few megabytes and you can afford to be careless. An image
history is gigabytes, and macOS puts screenshots on the pasteboard as
*uncompressed TIFF* at 10–20 MB each. Three things keep that under control:

1. **TIFF → PNG at capture**, when nothing already offers a compressed form.
   Typically a 10–20× reduction.
2. **Thumbnails.** A 400px JPEG is generated at capture and the list renders
   only from that — full-size bytes are never decoded to draw a row, and are
   loaded off the main thread only when a preview is actually shown.
3. **Two caps with LRU eviction** — item count (default 500) and total disk
   (default 2 GB). Pinned items are exempt from both.

### Finding images again

Storing images is easy; finding one three days later is the actual problem. An
image contributes nothing to a text index, so a history full of screenshots
degrades into a wall of thumbnails you have to scroll.

Clipwell runs OCR (Vision) over captured images on a background queue *after*
the item is saved, then folds the recognized text into the search index. The
capture path never waits on it. The extracted text is also shown under the
preview, so it's clear why a screenshot matched. Toggle it off in Settings →
General if you'd rather not spend the CPU.

### Storage

`~/Library/Application Support/Clipwell/`

```
history.sqlite     items + representations + blob refcounts + FTS5 index
blobs/ab/abc123…   representations over 64 KB, content-addressed by SHA-256
thumbnails/        400px JPEG previews
```

Blobs are addressed by content hash, so copying the same screenshot ten times
costs one file on disk. Smaller representations live inline in the row — fewer
files, faster reads.

Blob references are **counted in SQLite**, which is what keeps eviction cheap.
Asking the filesystem "how much disk am I using" and "which blobs are orphaned"
means walking the entire blob tree, and both questions come up on every single
capture once the history reaches its cap. With refcounts, disk usage is an
indexed `SUM` and a blob is deleted exactly when its count reaches zero. The
tree is walked once, at startup, to reconcile the accounting against reality in
case a crash left it drifting.

Readers ask for the representations they need rather than the whole item —
showing three lines of text shouldn't pull a 20 MB PNG off disk.

Search uses FTS5, falling back to `LIKE` if the system SQLite lacks it.

### Capture

macOS publishes no "pasteboard changed" notification, so Clipwell polls
`NSPasteboard.changeCount` every 0.3s (configurable). This is what every
clipboard manager does; the poll itself is a single integer compare, and the
full pasteboard is only read once that integer moves.

### Paste

The history panel is a **non-activating** `NSPanel`. The app you were typing in
never loses focus, so a synthesized <kbd>⌘V</kbd> lands there rather than in
Clipwell. Without this, auto-paste has nowhere to go.

---

## Privacy

- Content marked `org.nspasteboard.ConcealedType` — the convention password
  managers use — is **never recorded**, regardless of settings.
- Transient content is likewise skipped.
- Any app can be excluded by bundle ID; 1Password, Bitwarden and Keychain
  Access are excluded out of the box.
- Copies that look like credentials — API keys, provider tokens, private key
  blocks, card numbers passing Luhn — are **not recorded**. The convention
  above only works when the source app cooperates, and terminals, editors and
  cloud consoles never do. The menu bar icon flashes when a copy is skipped, so
  it is never silent. Toggle it in Settings → Privacy.
- Capture can be paused from the menu bar.
- Nothing leaves your machine. There is no network code in this app.

---

## Known limitations

These are real, and worth knowing before you rely on it.

- **Rapid copies can be missed.** Two copies inside one poll interval and only
  the second is seen. No API exists to avoid this on macOS.
- **File copies store paths, not bytes.** Move or delete the file and the entry
  goes stale — the preview marks it `missing` rather than failing silently at
  paste time.
- **File promises can't be captured.** Some apps (Mail, some browsers) put a
  *promise* on the pasteboard, where bytes only materialise on paste. These are
  unavailable retroactively, so an occasional item will look empty.
- **Launch at login may be refused** for an unsigned build. The toggle reports
  the failure rather than silently lying about its state.
- **Syntax highlighting is regex-based**, not a parser. It colours strings,
  comments, numbers and keywords, which is what a preview pane needs.
- **Secret detection is a heuristic.** It targets distinctive credential
  formats to keep false positives rare, but it will not catch a password that
  looks like an ordinary word, and it can still be wrong in both directions.
  It is a safety net, not a guarantee.
- **OCR is best-effort.** Low-confidence results are discarded rather than
  polluting the index, so text in small or stylised images may not be found.

---

## Layout

```
Sources/Clipwell/       executable shim; entry point only
Sources/ClipwellCore/   everything, as a library so it can be tested
  Capture/    polling, snapshot model, classification, OCR, secret detection
  Store/      SQLite wrapper, blob store, history + eviction
  Paste/      pasteboard restore, synthetic ⌘V
  Hotkey/     Carbon global hotkey
  UI/         panel, list, previews, settings, menu bar
  Model/      item, kind, metadata
  Support/    hashing, image transcoding, preferences, logging
Tests/ClipwellCoreTests/
```

The library/executable split exists so the pure logic — classification,
detection, eviction, blob accounting — is reachable from `swift test`. Those
are the parts most likely to be subtly wrong and the cheapest to pin down.
