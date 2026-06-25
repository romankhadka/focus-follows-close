#!/usr/bin/env bash
#
# Installer for focus-follows-close (Hammerspoon).
# Idempotent: safe to re-run. Backs up any existing init.lua before touching it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="${HOME}/.hammerspoon"
INIT="${HS_DIR}/init.lua"
SRC="${SCRIPT_DIR}/focus-follows-close.lua"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }

[ -f "$SRC" ] || { warn "Can't find focus-follows-close.lua next to this script."; exit 1; }

# 1. Hammerspoon ------------------------------------------------------------
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing Hammerspoon via Homebrew…"
    brew install --cask hammerspoon
  else
    warn "Hammerspoon not found and Homebrew isn't installed."
    warn "Install Hammerspoon from https://www.hammerspoon.org/ and re-run."
    exit 1
  fi
else
  ok "Hammerspoon already installed."
fi

# 2. Place the config -------------------------------------------------------
mkdir -p "$HS_DIR"

if [ -f "$INIT" ] && [ -s "$INIT" ]; then
  # Existing, non-empty config — install as a module and require it.
  BACKUP="${INIT}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$INIT" "$BACKUP"
  ok "Backed up existing init.lua → ${BACKUP}"

  cp "$SRC" "${HS_DIR}/focus-follows-close.lua"
  if ! grep -q 'require("focus-follows-close")' "$INIT"; then
    printf '\nrequire("focus-follows-close")\n' >> "$INIT"
    ok "Added require(\"focus-follows-close\") to your init.lua"
  else
    ok "init.lua already requires focus-follows-close"
  fi
else
  # No config (or empty) — this file becomes init.lua.
  cp "$SRC" "$INIT"
  ok "Installed as ${INIT}"
fi

# 3. (Re)launch so the new config loads ------------------------------------
if pgrep -q -f "Hammerspoon.app"; then
  say "Reloading Hammerspoon…"
  osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
open -a Hammerspoon
sleep 2

# 4. Accessibility check + verify ------------------------------------------
if command -v hs >/dev/null 2>&1; then
  # Poll briefly for the config to finish loading (ipc becomes available).
  for _ in $(seq 1 20); do
    [ "$(hs -c 'tostring(_G.FOCUS_FOLLOWS_CLOSE_LOADED)' 2>/dev/null)" = "true" ] && break
    sleep 0.3
  done

  ACX="$(hs -c 'tostring(hs.accessibilityState())' 2>/dev/null || echo '?')"
  LOADED="$(hs -c 'tostring(_G.FOCUS_FOLLOWS_CLOSE_LOADED)' 2>/dev/null || echo '?')"

  if [ "$ACX" = "true" ] && [ "$LOADED" = "true" ]; then
    ok "Installed and active. Toggle with ⌘⌥⌃F."
  elif [ "$ACX" != "true" ]; then
    warn "Hammerspoon needs Accessibility permission — the script is inert without it."
    warn "Grant it in: System Settings → Privacy & Security → Accessibility (enable Hammerspoon),"
    warn "then click the Hammerspoon menu-bar icon → Reload Config."
  else
    warn "Config didn't confirm load. Open the Hammerspoon console for any error, then Reload Config."
  fi
else
  warn "The 'hs' CLI isn't on PATH yet (it's enabled by this config on first load)."
  warn "Grant Accessibility to Hammerspoon, then click its menu-bar icon → Reload Config."
fi

say "Done. Source: ${HS_DIR}"
