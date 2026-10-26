# Chrome Profile Bar

A small macOS app (plain AppKit, no Dock icon) that shows a floating bar of Chrome profile
buttons for jumping straight to each profile's window. It uses about 13 MB of memory footprint.

The bar is styled as a companion to the Dock: same Liquid Glass, same height and corner shape,
sitting level with it just to its left. Each profile is a tile like a Dock icon showing the
profile's Google account picture (or its initial on the profile color) with a Chrome badge in
the corner; hovering shows the name, and a dot under a tile marks the active profile.
Right-click → *Show Labels* switches to labelled buttons instead.

| Action | Result |
|---|---|
| Click a button | Focus the profile's window (found by given name); if there is none, open a new window with `--profile-directory` and name it after 2.5 seconds |
| Alt + Click | Set the given name of the frontmost Chrome window to the profile's `window` (and clear that name from other windows) |
| Drag the background (the edge around the tiles, or ⋮ with labels) | Move the bar; the position is remembered. Dropped level with the Dock it stays attached, anywhere else it detaches |
| Right-click | Show Labels, Attach to Dock, Launch at Login, Match Window Titles (Accessibility), Open/Reload Config, Quit |
| Ctrl+Alt+P | Show/hide the bar |
| Ctrl+Alt+1…9 | Jump to profile 1…9 |

The button of the active profile (the focused Chrome window) is highlighted. While *Attach to
Dock* is on, the bar follows the Dock's height and stays next to it; with the Accessibility
permission it also lines up with the Dock's left edge and follows it whenever the Dock changes
width (apps launching and quitting, windows minimized into it, items added or removed);
without it, drag the bar next to the Dock once and it keeps that spot. The app ignores any
Chrome instance running with `--enable-automation` (e.g. chrome-devtools-mcp) and always sends
Apple Events by pid to your own Chrome.

## Build & install

Requires Swift 6 (the Command Line Tools are enough, Xcode is not needed).

```sh
./scripts/make-signing-cert.sh   # one-time: creates the "ChromeProfileBar Dev" identity in the login keychain
./build.sh                       # -> build/ChromeProfileBar.app
./build.sh install               # build, copy to /Applications and restart the app
./scripts/test.sh                # unit tests (config, title matching, placement, argv parsing)
swift scripts/make-icon.swift     # redraw Resources/AppIcon.icns (only needed when changing the icon)
```

### Why a dedicated signing certificate

The Automation/Accessibility grants stored by TCC are bound to the signature's *designated
requirement*. With ad-hoc signing the requirement is the cdhash, which changes on every build,
so macOS asks for permission again. Signing with a fixed identity gives the requirement
`identifier "dev.cuongnb.ChromeProfileBar" and certificate leaf = H"…"`, which stays the same
across rebuilds. The self-signed certificate does not need to be trusted for `codesign` to use
it (`security find-identity` shows `CSSMERR_TP_NOT_TRUSTED`, which is fine). To check:

```sh
codesign -dr - /Applications/ChromeProfileBar.app
```

To use a different identity, set `CODESIGN_IDENTITY="…" ./build.sh`. If the identity is not
found, `build.sh` signs ad-hoc and prints a warning.

## Permissions

- **Automation → Google Chrome** (required): macOS asks the first time the app controls Chrome.
  If you denied it: System Settings → Privacy & Security → Automation → Chrome Profile Bar →
  enable Google Chrome. Reset with `tccutil reset AppleEvents dev.cuongnb.ChromeProfileBar`.
- **Accessibility** (optional): Chrome scripting only returns tab titles, without the
  `(<profile>)` suffix. To also find/highlight *unnamed* windows by their title, right-click →
  *Match Window Titles (Accessibility)…* and enable the app in System Settings. Without it the
  app relies on given names only: clicking a profile with no named window opens a new window;
  use Alt+Click to name an existing one.
- Hotkeys use Carbon `RegisterEventHotKey`, so no extra permission is needed. If another app
  already registers Ctrl+Alt+P or Ctrl+Alt+1…9, one of the two will not receive the key.

Always launch the app via `open`/Finder (not the binary directly) so macOS attributes the
permissions to the app.

## Configuration

`~/.config/chrome-profile-bar/profiles.json` (the app creates a sample file if it is missing):

```json
[
  { "label": "Main", "window": "Main", "profile": "Main",        "dir": "Default",   "color": "#4285F4" },
  { "label": "Work", "window": "work", "profile": "example.com", "dir": "Profile 2", "color": "#0F9D58" }
]
```

| Key | Meaning | Default |
|---|---|---|
| `label` | Button text | required |
| `window` | The window's given name ("Name window…") used to find it | `label` |
| `profile` | The profile's display name, matched against the window title suffix (needs Accessibility) | `label` |
| `dir` | Last segment of "Profile Path" in `chrome://version` | required |
| `color` | Button color `#RRGGBB` | `#4285F4` |

After editing, right-click → *Reload Config* (or quit and reopen the app). The bar position is
stored in `defaults read dev.cuongnb.ChromeProfileBar`.

## Launch at login

Right-click → *Launch at Login* (uses `SMAppService.mainApp`, so the app must live in
`/Applications`). The app then shows up in System Settings → General → Login Items.

## Memory

Measured on macOS 26, arm64, with 4 profiles:

```sh
pid=$(pgrep -x ChromeProfileBar)
footprint $pid | grep phys_footprint   # ~13 MB, also the "Memory" column in Activity Monitor
ps -o rss= -p $pid                     # ~45 MB, includes shared system framework pages
```

An idle AppKit app (just one NSPanel) already has about 38 MB RSS, because RSS also counts
framework pages shared with other processes. Footprint is the memory private to the app.

## How it works

- `Chrome.swift` + `AppleEvent.swift`: raw Apple Events (`NSAppleEventDescriptor`) sent by pid
  using the codes from Chrome's `scripting.sdef` (`GNam` given name, `pidx` index, `pmnd`
  minimized, `misc/actv`). OSAKit/JavaScriptCore are not loaded. Automation instances are
  detected by reading argv via `sysctl(KERN_PROCARGS2)`.
- `ActiveTracker.swift`: refreshes when Chrome is activated (`NSWorkspace`). Only while Chrome
  is frontmost, it reads Chrome's top window number once a second via
  `CGWindowListCopyWindowInfo` (no permission needed) and sends Apple Events only when it changes.
- `Panel.swift`: a `.nonactivatingPanel` `NSPanel` at `.floating` level, `.canJoinAllSpaces`
  + `.stationary`. Clicks do not steal focus from Chrome.
- `HotKeys.swift`: Carbon hotkeys. `WindowTitles.swift`: the optional Accessibility part.

Log: `log stream --info --predicate 'subsystem == "dev.cuongnb.ChromeProfileBar"'`.
