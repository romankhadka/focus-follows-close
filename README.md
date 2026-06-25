# focus-follows-close

Fills the one window-focus gap macOS leaves, via [Hammerspoon](https://www.hammerspoon.org/).

**When you close an app's last window, focus moves to the next most-recently-active window** instead of leaving you stranded on a windowless, still-"active" app. Everything else is left to macOS — so there's no flicker and no surprises.

---

## The problem

macOS is **application-centric**; Linux and Windows are **window-centric**.

- Close one of several windows of an app → macOS focuses that app's next window. Fine, and this script never touches it.
- Close an app's **last** window → macOS keeps the now-windowless app frontmost (the menu bar still shows its name) and focuses **nothing**. You're left having to manually switch to get back to work.

There's no native setting for that last case. This script handles exactly that — and only that.

## What it does

On closing an app's **last** window, it focuses the **next most-recently-active window** — the window you were using before. That's the single case macOS drops the ball on. In every other case it does nothing and lets macOS do its native thing.

| You do | What happens |
|---|---|
| Close an app's **last** window | Focus moves to the window you used **just before** it (MRU order) |
| Close **one of several** windows of an app | Left to macOS — it focuses the app's next window |
| Switch apps / launch via Spotlight | Left to macOS — the script stays out of the way |
| The next-most-recent window is on a different desktop/Space | Skipped — it never yanks you to another Space (toggleable) |

Because it never overrides macOS's same-app behavior, there is **no flicker** — the script only acts in the windowless case, where macOS raises nothing to flash.

Toggle the whole thing on/off any time with **⌘⌥⌃F**.

## Requirements

- macOS (uses `hs.spaces`, available in Hammerspoon ≥ 0.9.90)
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

Open two apps with one window each (say Notes + Safari), Notes frontmost. Close the Notes window with ⌘W → focus should land on Safari instead of leaving you in windowless Notes. Closing one of several windows of the same app, switching apps, and launching via Spotlight should all behave exactly as native macOS.

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

Three small ideas, and a deliberate decision to do *less*:

1. **An MRU (most-recently-used) window list, built from focus events.** macOS z-order is an unreliable record of "what did I use last," so the script tracks activation order itself by listening to `windowFocused`, storing window *objects* (validating an object is sub-millisecond; resolving an ID back to a window via `hs.window.get` re-enumerates everything and costs ~57 ms).

2. **A windowless check.** It only acts when the app whose window you closed now has **no other standard window**. If the app still has windows, it returns immediately and lets macOS focus the next one. The check excludes the just-closed window's id to dodge a teardown timing race.

3. **An app-match guard.** It only acts when the closed window's app is still the frontmost app. When you switch apps or launch via Spotlight, the destroyed window (the old app, or the launcher) belongs to a *different* app than the one now frontmost — so the script does nothing.

**Why there's no flicker:** the flicker problem only exists when you override macOS's reflex of raising another same-app window on close. This script never does that — it stays out of the multi-window case entirely and only fills the windowless gap, where macOS raises nothing. No override, nothing to flash.

## Troubleshooting

- **Nothing happens when I close an app's last window.** Check Accessibility is granted: `hs -c "tostring(hs.accessibilityState())"` should be `true`. The script's window tracking is inert without it.
- **It focuses an app I never want focused.** Add it to `M.skipFocusInto`.
- **A close from some launcher/panel triggers it.** Add that app to `M.skipTriggerFrom`.
- **Editing the file doesn't take effect.** The config auto-reloads on save; if not, click the Hammerspoon menu-bar icon → Reload Config. (The auto-reloader keeps a reference so it isn't garbage-collected — see the note in the source.)

## Files

| File | Purpose |
|---|---|
| `focus-follows-close.lua` | The whole feature, self-contained. Drop-in `init.lua` or `require`d module. |
| `install.sh` | Installer: Homebrew + placement + backup + reload + verify. |
| `skills/focus-follows-close/SKILL.md` | Claude Code skill to install/manage it hands-off. |
