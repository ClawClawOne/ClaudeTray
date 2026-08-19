# Changelog

[ClaudeTray](https://github.com/ClawClawOne/ClaudeTray) — [TheUnnamedCompany](https://theunnamedcompany.com)

## 1.6 — 19 August 2026

- **The version number is in the popover**, in the header and again next to the update setting —
  the spot where you actually compare it with what GitHub reports. There was no way to tell which
  build was running short of opening the Finder, which made “is it up to date?” impossible to answer
  from the app. The verdict names it too: “ClaudeTray 1.6 is the latest version.”
- **A failed update check no longer claims you are up to date.** Network errors, GitHub rate limits
  and unexpected payloads all returned the same `nil` as “nothing newer”, so **Check now** said
  “ClaudeTray is up to date” when it had in fact reached nothing. The three outcomes are now
  distinct, and an unreachable GitHub says so.
- **No cadence under five minutes any more.** The **Auto** mode polled every 90 seconds while the
  5-hour window was in use, and the endpoint answers that with a stream of 429s. Auto and the 1-minute
  option are gone; the choice is 5, 15, 30 minutes or an hour, and settings pointing at a removed
  value fall back to 5 minutes.
- **Errors are visible from the menu bar.** An orange warning triangle appears next to the columns
  whenever a call fails, so nothing forces you to open the popover to learn that a refresh failed.
  The stale marker keeps its discreet monochrome circle.

## 1.5 — 19 August 2026

- **Fixed: the 429 message announced a wrong delay.** It printed the server’s `Retry-After` header,
  which is sometimes `0`, while the app actually waits for its own exponential backoff — so the
  popover could read “Retrying in 0 s” and then sit still for minutes. It now shows the delay that
  was really scheduled, formatted like the countdowns (“2 min 30 s”).
- **Hardening around revocation, from a review of 1.4.** The keychain item was force-cast, which
  would have crashed the app rather than reported an error if the system ever returned another kind
  of reference; the type is now checked first. The red confirmation expires after six seconds instead
  of staying armed for a distracted click on the next popover. The manual token field is back
  directly under its own button, rather than below the revoke row.
- A version check that was still in flight when the daily setting is switched off no longer displays
  its result, unless it was the one you asked for with **Check now**.

## 1.4 — 19 August 2026

- **An app icon.** ClaudeTray lives in the menu bar, but it still shows up in Finder, in the DMG and
  in system dialogs, where it had none. The icon is drawn by `scripts/make-icon.swift` — a quota ring
  three quarters full — so it can be regenerated instead of being an opaque binary.
- **“Check now” button** next to the daily update setting. The automatic check runs once every 24
  hours; the button asks GitHub immediately and says so when nothing newer exists. It works even when
  the daily check is switched off: asking explicitly is consent for that one request.
- **“Revoke token access” button.** It deletes the manual token and removes ClaudeTray from the
  trusted applications of the `Claude Code-credentials` keychain item, so macOS asks for permission
  again on the next call — the “Always Allow” granted once could not be undone from the app before.
  The button asks for confirmation, only ever removes entries that point at ClaudeTray, and writes
  nothing if there is none.

## 1.3 — 19 August 2026

- **Fixed: the token source shown after a failure.** The popover only updated the “Token:” line after
  a successful call, so pasting a manual token that the API rejected left the line showing the
  previous source — usually the macOS keychain. It read as if ClaudeTray had ignored the manual token
  and gone back to the keychain, when the manual token had in fact been used and refused. The source
  is now published as soon as it is resolved, before the request, so it always names the token the
  last call actually carried.
- **A 401 on a manual token now says so.** The message states that the manual token takes priority
  over the keychain and that clearing it is what falls back to Claude Code.
- **The clear button is explicit.** “Clear” became “Clear the manual token” — it never touched the
  keychain authorisation granted to ClaudeTray, and now says as much.

## 1.2 — 19 August 2026

- **Fixed: repeated notifications.** Once a window went past 80 % or 95 %, a notification was posted
  on every refresh — up to one a minute on the fastest interval. The threshold state was re-armed by
  the `resets_at` date, which moves forward on every call for the rolling 5-hour window. Notifications
  are now edge-triggered: one is posted only when the percentage was below the threshold at the
  previous reading and reaches it at the current one, so a rising window produces at most two.
- **Daily update check.** ClaudeTray asks GitHub once every 24 hours whether a newer release exists
  and, if so, shows a link in the popover footer. The request is anonymous and the check can be
  turned off in the settings.
- A discreet support link in the popover footer.

## 1.1 — 18 August 2026

- **The interface is now available in English, French, German, Spanish and Italian.** It follows the
  macOS language by default, with English as the fallback, and a picker in the popover forces any of
  the five. The change applies immediately, with no restart: translations live in `Loc`, a plain Swift
  struct, rather than in `.lproj` bundles, which cannot be switched at runtime.
- Dates, times and countdown units follow the selected language.
- Error messages, notifications and quota window titles are translated too.

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
