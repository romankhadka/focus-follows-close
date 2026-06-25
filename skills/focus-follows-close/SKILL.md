---
name: focus-follows-close
description: Install, verify, or troubleshoot the Hammerspoon "focus-follows-close" macOS behavior — when you close an app's LAST window, focus moves to the next most-recently-active window (the one gap macOS leaves). Use when setting up a new Mac, replicating this config, toggling/tuning it, or diagnosing why it isn't working. macOS + Hammerspoon only.
---

# focus-follows-close — setup & management skill

This skill installs and manages a Hammerspoon script that fills the one
window-focus gap macOS leaves: when you close an app's **last** window, it
focuses the next most-recently-active window instead of stranding you on a
windowless app. Every other case (closing one of several windows, switching
apps, Spotlight) is left to macOS — so there is no flicker. Source repo:
`https://github.com/romankhadka/focus-follows-close`.

The config file is `focus-follows-close.lua`. The single source of truth for the
machine is `~/.hammerspoon/init.lua` (or a `~/.hammerspoon/focus-follows-close.lua`
module that init.lua `require`s).

## Before doing anything

- Confirm the platform is **macOS**. If not, stop — this is macOS-only.
- This is the user's personal machine config. Always **back up** an existing
  `~/.hammerspoon/init.lua` before overwriting it.

## Install (preferred path)

1. Clone the repo somewhere temporary and run its installer — it handles
   Homebrew, backup, placement (fresh vs. existing config), relaunch, and
   verification:
   ```bash
   git clone https://github.com/romankhadka/focus-follows-close.git /tmp/focus-follows-close
   cd /tmp/focus-follows-close && ./install.sh
   ```
2. If `git`/network isn't available but you already have the repo checkout, run
   `./install.sh` from it directly.

## Install (manual fallback, if the installer can't run)

1. Ensure Hammerspoon is installed: `brew install --cask hammerspoon` (or direct
   from https://www.hammerspoon.org/).
2. `mkdir -p ~/.hammerspoon`.
3. If `~/.hammerspoon/init.lua` is **missing or empty**, copy
   `focus-follows-close.lua` to `~/.hammerspoon/init.lua`.
   If it **exists and is non-empty**, back it up
   (`cp init.lua init.lua.backup.<timestamp>`), copy `focus-follows-close.lua`
   into `~/.hammerspoon/`, and append `require("focus-follows-close")` to
   `init.lua` (only if not already present).
4. (Re)launch Hammerspoon so the new config loads:
   `osascript -e 'tell application "Hammerspoon" to quit'` then `open -a Hammerspoon`.

## Critical: Accessibility permission

The script is **completely inert** without it, and this can't be scripted — the
user must grant it manually:

> System Settings → Privacy & Security → Accessibility → enable **Hammerspoon**.

After granting, reload: click the Hammerspoon menu-bar icon → Reload Config, or
`hs -c "hs.reload()"`.

Always verify: `hs -c "tostring(hs.accessibilityState())"` must be `true`.

## Verify

The config enables Hammerspoon's `hs` command-line tool. Use it (it only works
*after* the config has loaded once, since loading is what enables `hs.ipc`):

```bash
hs -c "tostring(_G.FOCUS_FOLLOWS_CLOSE_LOADED)"   # → true   (config ran clean)
hs -c "tostring(hs.accessibilityState())"          # → true   (permission granted)
hs -c "tostring(_G.FocusFollowsClose.enabled)"     # → true   (feature on)
hs -c "tostring(#_G.FocusFollowsClose.mru)"        # → >0     (windows tracked)
```

If `hs` reports `can't access Hammerspoon message port`, the config hasn't loaded
with `hs.ipc` yet — relaunch Hammerspoon (the first load can't be triggered via
the CLI), then retry.

Then have the user do a real test: with two apps open (each one window), close
the last window of the frontmost one and confirm focus lands on the other app's
window. Closing one of several windows of the same app, switching apps, and
launching via Spotlight should behave exactly like native macOS.

## Manage / tune

All knobs are at the top of `focus-follows-close.lua`; edit and save (it
auto-reloads). Toggle on/off at runtime with **⌘⌥⌃F**, or:

- Disable now: `hs -c "_G.FocusFollowsClose.enabled = false"`
- `M.sameSpaceOnly` — set `false` to allow crossing to other desktops/Spaces.
- `M.skipFocusInto` — apps to never land focus on (e.g. `["Finder"] = true`).
- `M.skipTriggerFrom` — apps whose closes are ignored entirely.

## Troubleshooting

- **Nothing happens when closing an app's last window** → Accessibility not
  granted (check `accessibilityState()`).
- **It focuses an app you never want focused** → add it to `M.skipFocusInto`.
- **A launcher/panel close triggers it** → add that app to `M.skipTriggerFrom`.
- **Edits don't apply** → menu-bar icon → Reload Config (auto-reload watcher may
  have been removed or your config has its own).

## Design note

This is intentionally the *windowless-only* version: it acts solely when an app
loses its last window. It does NOT try to override macOS when an app still has
other windows — doing that causes a one-frame flicker (macOS raises a same-app
window before any script can react). The repo's `main` branch is this
flicker-free version; the earlier, more aggressive "next window overall, even
across apps" implementation is preserved on the `roman/flicker-prone-original`
branch for reference. Don't reintroduce the cross-app override on `main`.

See the repo `README.md` for the full rationale (MRU tracking, the windowless
check, the app-match guard, and why window objects beat IDs for performance).
