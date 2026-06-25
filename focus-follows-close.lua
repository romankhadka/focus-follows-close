-- focus-follows-close.lua
-- Focus-follows-close: when you close a window, move focus to the next
-- most-recently-active window overall — regardless of app — restricted to the
-- current Space. Mimics the Windows/Linux window-centric behavior that macOS
-- (which is app-centric) deliberately omits.
--
-- Works two ways:
--   * As a standalone config: copy/symlink this file to ~/.hammerspoon/init.lua
--   * Inside an existing config: drop it in ~/.hammerspoon/ and add
--       require("focus-follows-close")
--     to your init.lua. (`_G.FocusFollowsClose = M` keeps it alive, so you do
--     not need to hold the return value.)

require("hs.ipc")  -- enables the `hs` command-line tool to talk to this instance

local M = {}

-- Master switch. Toggle at runtime with the hotkey below (⌘⌥⌃F).
M.enabled = true

-- Only ever promote a window that's on a currently-visible Space, so closing a
-- window never yanks you to a different desktop / triggers a Space switch.
M.sameSpaceOnly = true

-- Hotkey to toggle M.enabled on/off (mnemonic: F = "follows").
M.toggleMods = {"cmd", "alt", "ctrl"}
M.toggleKey  = "F"

-- Don't auto-focus INTO these apps (e.g. background utilities you don't want
-- grabbing focus). Set a name to true to exclude it as a focus target.
M.skipFocusInto = {
  -- ["Finder"] = true,
}

-- Don't run the logic at all when a window from these apps closes
-- (transient panels, launchers, Hammerspoon's own console, etc.).
M.skipTriggerFrom = {
  ["Hammerspoon"] = true,
  ["Spotlight"]   = true,
  ["Alfred"]      = true,
}

local DELAY        = 0.00  -- seconds before we apply our chosen focus. macOS has
                           -- already done its own re-focus by the time the close
                           -- event fires, so no settle delay is needed.
local COMMIT_DELAY = 0.18  -- seconds a focus is held "pending" before joining
                           -- the MRU. macOS's app-centric auto-promotion of a
                           -- same-app window on close arrives within this window
                           -- and is cancelled by the close, so it never
                           -- pollutes the true activation order.
local SETTLE       = 0.15  -- keep ignoring focus events this long after we act,
                           -- so a late auto-promotion can't sneak into the MRU.

-- Most-recently-used window OBJECTS, most-recent first. Storing objects (not
-- IDs) is the whole performance trick: validating an object is sub-millisecond,
-- whereas resolving an ID back to a window (hs.window.get) re-enumerates every
-- window and costs ~57ms per call.
M.mru = {}
local MRU_MAX = 60

-- A focus waits here for COMMIT_DELAY before being committed to the MRU, so a
-- near-simultaneous close can cancel it (see COMMIT_DELAY above).
local pendingWin   = nil
local pendingApp   = nil
local pendingTimer = nil

-- True while a close is being processed, so macOS's interim same-app re-focus
-- doesn't reorder the MRU out from under our snapshot.
local closeInProgress = false

-- ---- Space helpers --------------------------------------------------------

local function activeSpaceSet()
  local set = {}
  local active = hs.spaces.activeSpaces()  -- { screenUUID = spaceID, ... }
  if active then
    for _, spaceID in pairs(active) do set[spaceID] = true end
  end
  return set
end

local function onActiveSpace(win, activeSet)
  local spaces = hs.spaces.windowSpaces(win)
  if not spaces then return false end
  for _, spaceID in ipairs(spaces) do
    if activeSet[spaceID] then return true end
  end
  return false
end

-- ---- MRU bookkeeping (objects) --------------------------------------------

local function removeFromMru(id)
  for i, w in ipairs(M.mru) do
    if w:id() == id then table.remove(M.mru, i); return end
  end
end

local function inMru(id)
  for _, w in ipairs(M.mru) do
    if w:id() == id then return true end
  end
  return false
end

local function touchMru(win)
  local id = win and win:id()
  if not id then return end
  removeFromMru(id)
  table.insert(M.mru, 1, win)
  while #M.mru > MRU_MAX do table.remove(M.mru) end
end

-- Drop any focus that's still waiting to be committed (e.g. macOS's auto-
-- promotion of a same-app window during a close).
local function cancelPending()
  if pendingTimer then pendingTimer:stop() end
  pendingTimer = nil
  pendingWin   = nil
  pendingApp   = nil
end

-- Most-recently-active *surviving* window, skipping the just-closed window,
-- ignored apps, and (optionally) anything off the current Space. App identity
-- is irrelevant — same-app windows are eligible. Returns an hs.window or nil.
-- Prunes dead/non-standard windows as it scans; keeps valid-but-off-Space ones.
local function nextMruWindow(closedId)
  local useSpaces = M.sameSpaceOnly and (hs.spaces ~= nil)
  local activeSet = useSpaces and activeSpaceSet() or nil
  -- If the active-Space set comes back empty (spaces API not ready, or screen
  -- locked), don't let it reject every candidate — skip the filter instead.
  if activeSet and next(activeSet) == nil then activeSet = nil end

  local i = 1
  while i <= #M.mru do
    local win = M.mru[i]
    local id  = win:id()
    if not id or not win:isStandard() then
      table.remove(M.mru, i)            -- dead / non-standard; prune for good
    else
      local app  = win:application()
      local name = app and app:name() or ""
      local ok =
        id ~= closedId
        and win:isVisible()
        and not M.skipFocusInto[name]
        and (not activeSet or onActiveSpace(win, activeSet))
      if ok then return win end
      i = i + 1                          -- valid but not a match; keep, move on
    end
  end
  return nil
end

-- ---- Event handlers -------------------------------------------------------

local function onFocus(win)
  if closeInProgress then return end       -- ignore macOS's interim auto-focus
  if not (win and win:id()) then return end
  local app = win:application()

  -- Defer the commit. If a close arrives before COMMIT_DELAY elapses, the close
  -- cancels this — that's how we keep macOS's same-app auto-promotion (which
  -- fires right as you close a window) out of the real activation order.
  cancelPending()
  pendingWin   = win
  pendingApp   = app and app:name() or ""
  pendingTimer = hs.timer.doAfter(COMMIT_DELAY, function()
    pendingTimer = nil
    if pendingWin == win then
      pendingWin = nil
      pendingApp = nil
      touchMru(win)
    end
  end)
end

-- Decide which window to focus after a window in `appName` closes, or nil if we
-- should stay out of it. PURE — never changes focus — so it's CLI-testable.
local function decideTarget(closedId, appName)
  local frontApp = hs.application.frontmostApplication()
  if not frontApp then return nil end

  -- Only act when the closed window belonged to the app that is STILL
  -- frontmost. When you switch apps or launch via Spotlight, the destroyed
  -- window (old app / launcher) is a DIFFERENT app than the one now frontmost,
  -- so we leave focus exactly where the OS just put it. This is what stops the
  -- script from yanking you back out of a freshly-activated app.
  if appName ~= frontApp:name() then return nil end

  return nextMruWindow(closedId)
end

local function onWindowClosed(closedWin, appName, _)
  if not M.enabled then return end
  if M.skipTriggerFrom[appName] then return end

  -- Lazy bootstrap: if focus events haven't populated the MRU yet (e.g. first
  -- close after an unlock), seed it from the current windows before deciding.
  if #M.mru == 0 and M.seedMru then M.seedMru() end

  -- If macOS already auto-promoted a SAME-APP window for this close, it's
  -- sitting in `pending` right now — drop it so it can't override the genuine
  -- previously-active window. A genuine switch to a DIFFERENT app stays.
  if pendingWin and pendingApp == appName then cancelPending() end

  -- Decide the target from the CLEAN committed MRU (macOS's auto-promotion was
  -- never committed), before anything else runs.
  local closedId = closedWin and closedWin:id() or nil
  removeFromMru(closedId)
  local target = decideTarget(closedId, appName)
  if not target then return end

  closeInProgress = true
  -- Focus synchronously: every millisecond here is a millisecond macOS's
  -- promoted window stays on screen. macOS has already done its own re-focus by
  -- the time this event fires, so there's no race to wait out.
  if target:isStandard() then              -- still valid?
    target:focus()
    touchMru(target)                       -- commit our choice immediately
  end
  -- Keep ignoring focus events briefly so a late macOS auto-promotion can't
  -- sneak into the MRU after we've acted.
  hs.timer.doAfter(SETTLE, function() closeInProgress = false end)
end

-- ---- Wiring ---------------------------------------------------------------

M.filter = hs.window.filter.new(nil)  -- default filter: real windows, all apps
M.filter:subscribe(hs.window.filter.windowFocused, onFocus)
M.filter:subscribe(hs.window.filter.windowDestroyed, onWindowClosed)

-- Seed the MRU with all current windows in z-order (front-most first), so
-- closes right after a reload already have candidates. Idempotent and order-
-- preserving: only APPENDS windows not already tracked, so it never disturbs
-- real recency built from focus events. Run now and again shortly after, since
-- orderedWindows() can be empty while the window system warms up post-reload.
local function seedMru()
  -- Prefer orderedWindows() for true z-order; fall back to visibleWindows()
  -- when it returns empty (it can right after reload, or while the screen is
  -- locked, where orderedWindows()/filter both report nothing).
  local list = hs.window.orderedWindows()
  if #list == 0 then list = hs.window.visibleWindows() end
  for _, w in ipairs(list) do
    local id = w:id()
    if id and not inMru(id) then table.insert(M.mru, w) end
  end
end
M.seedMru = seedMru
seedMru()
M.seedTimer = hs.timer.doAfter(0.5, seedMru)

-- Hotkey: toggle the whole behavior on/off at runtime.
local function toggle()
  M.enabled = not M.enabled
  hs.alert.show("Focus-follows-close: " .. (M.enabled and "ON" or "OFF"))
end
M.toggle = toggle
hs.hotkey.bind(M.toggleMods, M.toggleKey, toggle)

-- Expose helpers + module so behavior is inspectable from the `hs` CLI.
M.nextMruWindow = nextMruWindow
M.decideTarget  = decideTarget
_G.FocusFollowsClose = M

-- Sentinel: lets the CLI confirm the whole config executed without error.
_G.FOCUS_FOLLOWS_CLOSE_LOADED = true

-- Auto-reload Hammerspoon when any .lua file in ~/.hammerspoon/ changes.
-- NOTE: must retain the watcher on M — an anonymous pathwatcher gets
-- garbage-collected and silently stops firing. If your existing config already
-- has its own reloader, delete this block.
M.watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then hs.reload(); return end
  end
end):start()
hs.alert.show("Focus-follows-close active  (MRU mode · toggle: ⌘⌥⌃F)")

return M
