# Measuring macOS window geometry: three traps

*Found 2026-07-22, while building auto-arrange (v0.3.0).*

Three ways measuring window geometry gave the wrong answer on a real three-display desktop.
All three cost real debugging time; the first one produced a confident, fully wrong root cause.

## 1. Setting a frame is not synchronous — never read it back immediately

An app processes a `kAXPosition` / `kAXSize` write on **its own run loop** and reports the new
geometry a beat later. Read straight after writing and you get a mid-flight value.
Electron-based apps (Positron, VS Code) are the worst offenders.

What this looked like in practice: auto-arrange asked a Positron window for a 704.5pt-tall
tile and read back `720` immediately. That reads exactly like "the app has a 720pt minimum and
refused" — so the code "corrected" the overflow by sliding the window, pushing it 16pt off the
bottom of the screen.

The window had no minimum at all. Probed properly, with 250–400ms between calls:

```
asked  704.5 -> got  704.0  ✓          — and identical results on a second display
asked  650.0 -> got  650.0  ✓
asked  600.0 -> got  600.0  ✓
asked  400.0 -> got  400.0  ✓
```

`WindowEngine.settleDelay` (0.35s) exists for this. **Nothing may inspect the result of a move
until it has elapsed.**

### The tell

A read-back claims an app *refuses* a size, but the user can resize that same window by hand
without trouble. When those two disagree, the measurement is wrong — not the app. In this case
the user saying "weirdly I can resize Positron manually just fine" is what exposed it.

## 2. `NSScreen.visibleFrame` from a CLI script disagrees with the real app

A throwaway `swift probe.swift` reported the ultrawide's `visibleFrame == frame` (1440pt tall).
The running `.app` saw **1409** — that display has its own menu bar, reserving ~31pt at the top
that the CLI did not account for. (Oddly, the CLI *did* subtract the built-in display's menu
bar and Dock, so the discrepancy is easy to miss.)

Consequence: never compute "expected" zone rects in a CLI probe and diff them against what the
app actually did. The baseline is wrong, and it produces a table of misses that sends you
hunting for a bug that isn't there. Instrument the app instead.

## 2b. `NSWindow(contentRect:…screen:)` reads the rect *relative to that screen*

*Found 2026-08-16, building the reserved-space editor.*

Passing a screen to the initializer changes what the content rect means: it is interpreted in
that screen's own coordinates, not global ones. So the natural-looking

```swift
NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
         defer: false, screen: screen)          // ✘ offset by the screen's origin
```

puts a full-screen overlay off by the screen's origin — here 274pt right and 30pt down, with
the far edges clipped. It is easy to miss because the window still lands *mostly* over the
right display, and anything centred in it still looks centred.

Build it at `.zero` and move it, which is what `SnapOverlay` already did:

```swift
let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
w.setFrame(screen.frame, display: false)        // ✓ global coordinates
```

### How it was caught

Screenshot the display with the overlay up, press Esc, screenshot again, and diff the two:
the columns and rows that changed *are* the overlay's real extent, measured rather than
assumed. Before the fix the tint covered columns 274–3440; after, 0–3440 with rows 32–1440,
the 32 being that display's own menu bar — exactly `visibleFrame`.

## 3. `NSLog` from the self-signed bundle does not reach unified logging

`log show --last 3m --predicate 'process == "Sash"' --info --debug` returned nothing at all.

What works — run the binary directly so stderr is capturable:

```bash
nohup ./build/Sash.app/Contents/MacOS/Sash > /tmp/sash.log 2>&1 &
grep SASHDIAG /tmp/sash.log
```

This keeps the bundle's Accessibility grant, so it is a usable way to get diagnostics out of
the real app rather than a stand-in.

## The useful counterpart: CLI scripts *are* Accessibility-trusted

`AXIsProcessTrusted()` returns `true` for a `swift file.swift` run from a terminal that has
been granted Accessibility — it inherits the parent's grant. So a throwaway script can read and
set other apps' windows, which makes probing one window's real limits cheap:

```swift
for h in [704.5, 650.0, 600.0, 400.0] {
    setSize(win, CGSize(width: w, height: h))
    usleep(300_000)                       // the whole point — let it settle
    print("asked \(h) -> got \(frame(win).height)")
}
```

Restore the original frame afterwards. This is the fastest way to answer "does this app
actually refuse that size?" — and it should be run *before* building anything on the assumption
that it does.
