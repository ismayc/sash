# Findings

Hard-won facts from building Sash — the kind that cost real debugging time and would
otherwise have to be rediscovered. Newest first.

| Date | Finding |
|---|---|
| 2026-08-16 | [`NSWindow(contentRect:…screen:)` reads its rect relative to that screen](ax-geometry-measurement-traps.md#2b-nswindowcontentrectscreen-reads-the-rect-relative-to-that-screen) — handing it a global frame offsets a full-screen overlay by the screen's origin, and it still looks *mostly* right. |
| 2026-07-22 | [Measuring macOS window geometry: three traps](ax-geometry-measurement-traps.md) — an AX frame write is asynchronous, so reading it back immediately invents constraints that don't exist; `visibleFrame` differs between a CLI script and the real app; `NSLog` from the self-signed bundle never reaches unified logging. |
