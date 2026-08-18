# Changelog

[ClaudeTray](https://github.com/ClawClawOne/ClaudeTray) — [TheUnnamedCompany](https://theunnamedcompany.com)

## 1.0 — 18 August 2026

First release.

### Features

- Menu bar: monochrome Claude logo (hideable) and one column per quota window — `5H`, `WEEK`, plus
  one column per per-model quota (`FABLE`…). Uppercase label on top, percentage used underneath,
  left-aligned.
- Popover: one progress bar per window with its percentage and countdown, the token source in use,
  the time of the last successful refresh, a readable error message, a Refresh button, a manual token
  field, and Quit.
- Local notifications at 80% and 95% of each window, once per window, re-armed at reset, toggleable.
- Launch at login through `SMAppService`.

### Settings

- Refresh rate: Auto, 1 min, 5 min, 15 min, 30 min, 1 h.
- Claude logo shown or hidden.
- One or all windows in the menu bar; in single-window mode, choose between the 5-hour window, the
  weekly window, and whichever is most constrained.
- Used or remaining.
- Percentage colour: eight swatches.
- Spacing between elements (2–24 pt) and edge margin (0–24 pt).

### Robustness

- Three token sources, in order: manual file, macOS keychain, `.credentials.json`.
- Exponential backoff capped at 30 min, `Retry-After` honoured.
- Polling suspended on sleep and locked session, resumed on wake.
- Last valid snapshot kept on error, with a staleness marker.

### Requirement

Claude Code must be installed **and logged in** (`claude` then `/login`): that is what writes the
OAuth token ClaudeTray reads.
