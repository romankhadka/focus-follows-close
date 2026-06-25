# focus-follows-close

Linux/Windows-style window focus on macOS, via [Hammerspoon](https://www.hammerspoon.org/).

**When you close a window, focus moves to the next most-recently-active window — regardless of which app it belongs to.** No more being left staring at a windowless, still-"active" app, and no manual click to get back to work.

---

## The problem

macOS is **application-centric**; Linux and Windows are **window-centric**.

- **Windows / Linux:** focus belongs to a *window*. Close it and the window manager promotes the next window in your recent-use order — often a different app.
- **macOS:** focus belongs to an *application*. Close a window and the app stays frontmost even with **zero** windows (the menu bar still shows its name). Focus never crosses the app boundary for you. Close the last window of an app and you're left with nothing focused, having to manually switch.

There is no native System Settings toggle for this — it's baked into how `NSApplication` activation works. This script adds the missing layer on top.

## What it does

On every window close, it focuses the **next most-recently-active window** — the one you'd naturally expect to fall back to — even if that's a different app. App identity is irrelevant: if the next-most-recent window happens to be another window of the *same* app, it goes there; if it's a different app, it goes there.

| You do | What happens |
|---|---|
| Close a window | Focus moves to the window you used **just before** it (MRU order), same app or not |
| Close one of several windows of an app | Focus follows real recency — not whichever window macOS reflexively raises |
| Switch apps / launch via Spotlight | **Nothing** — the script stays out of the way (see the app-match guard below) |
| Close a window when the only other windows are on a different desktop/Space | **Nothing** — it never yanks you to another Space (toggleable) |

Toggle the whole thing on/off any time with **⌘⌥⌃F**.

## Requirements

- macOS (developed against Sequoia; uses `hs.spaces`, available in Hammerspoon ≥ 0.9.90)
- [Hammerspoon](https://www.hammerspoon.org/) (tested with 1.1.1)
- **Accessibility** permission granted to Hammerspoon (the script is inert without it)

## Install

### Option A — one-line installer (recommended)

```bash
git clone https://github.com/romankhadka/focus-follows-close.git
cd focus-follows-close
./install.sh
```

The installer will:
1. Install Hammerspoon via Homebrew if it's missing.
2. Back up any existing `~/.hammerspoon/init.lua`.
3. Place the script (as your `init.lua` if you have none, or as a `require`d module if you already have a config).
4. Launch Hammerspoon and tell you how to grant Accessibility.
5. Reload and verify.

### Option B — manual

```bash
brew install --cask hammerspoon
mkdir -p ~/.hammerspoon
cp focus-follows-close.lua ~/.hammerspoon/init.lua   # fresh config
# — or, if you already have an init.lua —
cp focus-follows-close.lua ~/.hammerspoon/
echo 'require("focus-follows-close")' >> ~/.hammerspoon/init.lua
```

Then launch Hammerspoon, grant **Accessibility** in *System Settings → Privacy & Security → Accessibility*, and click the menu-bar icon → **Reload Config**.

### Option C — with Claude Code (another Mac, hands-off)

This repo ships a Claude Code **skill** at [`skills/focus-follows-close/`](skills/focus-follows-close/SKILL.md). Copy it into your global skills directory and Claude will do the whole install + verification for you:

```bash
mkdir -p ~/.claude/skills/focus-follows-close
cp skills/focus-follows-close/SKILL.md ~/.claude/skills/focus-follows-close/
```

Then in Claude Code: *"set up focus-follows-close"* (or invoke the skill). See the skill file for details.

## Verify it's working

Open Chrome + a terminal + another app on one Space, with the terminal frontmost. Close the terminal window with ⌘W → focus should land on the next window you were using, not leave you in a windowless app. Switching apps and launching via Spotlight should feel completely normal.

From the CLI (Hammerspoon's `hs` tool, enabled by this config):

```bash
hs -c "tostring(_G.FocusFollowsClose.enabled)"   # → true
hs -c "tostring(#_G.FocusFollowsClose.mru)"       # → number of tracked windows
```

## Configuration

All knobs live at the top of the file. Edit and save — the config auto-reloads.

| Setting | Default | Meaning |
|---|---|---|
| `M.enabled` | `true` | Master switch (also toggled by the hotkey) |
| `M.sameSpaceOnly` | `true` | Never focus a window on a hidden Space/desktop |
| `M.toggleMods` / `M.toggleKey` | `⌘⌥⌃` + `F` | The on/off hotkey |
| `M.skipFocusInto` | `{}` | Apps to never land focus on (e.g. `["Finder"] = true`) |
| `M.skipTriggerFrom` | Hammerspoon, Spotlight, Alfred | Apps whose window-closes are ignored entirely |

## How it works

Four ideas carry the whole thing:

1. **An MRU (most-recently-used) window list, built from focus events.** macOS z-order is unreliable for "what did I use last" because the OS reshuffles it on close, so the script tracks activation order itself by listening to `windowFocused`.

2. **Delayed commit (the correctness trick).** When you close a window, macOS *instantly* raises another window of the same app and focuses it — which would pollute the MRU before the script reads it. So focus events are held "pending" for ~180 ms before they join the MRU. macOS's reflexive auto-promotion fires in the same instant as the close, so it's still pending and uncommitted when the close arrives — and the close cancels it. The committed MRU stays clean, so the script picks the window *you* actually used last. (A same-app window still wins when it is genuinely the most-recent — because that ordering was committed by real use, not by macOS's reflex.)

3. **The app-match guard (the safety trick).** The script only acts when the closed window's app is still the frontmost app. When you switch apps or launch via Spotlight, the destroyed window (the old app, or the launcher) belongs to a *different* app than the one now frontmost — so the script does nothing and leaves focus where the OS put it. This is what keeps it from yanking you back out of an app you just switched to.

4. **Window objects, not IDs (the performance trick).** Resolving a window ID back to a window (`hs.window.get`) re-enumerates every window and costs ~57 ms per call — enough to make the focus swap visibly choppy. Storing the window *objects* and validating them directly is sub-millisecond, so the swap lands within a single display frame.

### Honest limitation

There is an unavoidable sub-frame flicker in one case: closing a window when its app has *other* windows. macOS raises one of those other windows *as part of* the close, before any event reaches the script — so the script can only ever respond *after*. At ~1 ms response time the swap usually lands in the same ~16 ms display frame (no visible flash), but you may occasionally catch a single frame of the intermediate window. Eliminating it entirely would require intercepting ⌘W and closing windows manually, which breaks "close tab" semantics in browsers/editors/terminals — a worse problem than a rare one-frame flicker. So it's left as-is by design.

## Troubleshooting

- **Nothing happens on close.** Check Accessibility is granted: `hs -c "tostring(hs.accessibilityState())"` should be `true`. The script's window tracking is inert without it.
- **It pulled me out of an app I switched to.** Shouldn't happen with the app-match guard — but if some app reports an unexpected name, add it to `M.skipTriggerFrom`.
- **It focuses an app I never want focused.** Add it to `M.skipFocusInto`.
- **Editing the file doesn't take effect.** The config auto-reloads on save; if not, click the Hammerspoon menu-bar icon → Reload Config. (The auto-reloader keeps a reference so it isn't garbage-collected — see the note in the source.)

## Files

| File | Purpose |
|---|---|
| `focus-follows-close.lua` | The whole feature, self-contained. Drop-in `init.lua` or `require`d module. |
| `install.sh` | Installer: Homebrew + placement + backup + reload + verify. |
| `skills/focus-follows-close/SKILL.md` | Claude Code skill to install/manage it hands-off. |
