-- focus-follows-close.lua
-- Focus-follows-close (windowless-only): when you close an app's LAST window,
-- focus the next most-recently-active window. When the app still has other
-- windows, macOS already focuses its next window itself — we stay out of that
-- case entirely, which is why this version never flickers.
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

-- Only ever promote a window on a currently-visible Space, so a close never
-- yanks you to a different desktop.
M.sameSpaceOnly = true

-- Hotkey to toggle M.enabled on/off (mnemonic: F = "follows").
M.toggleMods = {"cmd", "alt", "ctrl"}
M.toggleKey  = "F"

-- Don't auto-focus INTO these apps. Set a name to true to exclude it.
M.skipFocusInto = {
  -- ["Finder"] = true,
}

-- Don't run the logic when a window from these apps closes (launchers/panels).
M.skipTriggerFrom = {
  ["Hammerspoon"] = true,
  ["Spotlight"]   = true,
  ["Alfred"]      = true,
}

-- Most-recently-used window OBJECTS, most-recent first, built from focus events.
-- (No delayed-commit machinery needed here: we only act when the app goes
-- windowless, and macOS promotes nothing in that case, so the MRU is never
-- polluted at close time.)
M.mru = {}
local MRU_MAX = 60

-- ---- Space helpers --------------------------------------------------------

local function activeSpaceSet()
  local set = {}
  local active = hs.spaces.activeSpaces()
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

-- Most-recently-active surviving window, skipping the just-closed window,
-- ignored apps, and anything off the current Space. Prunes dead windows.
local function nextMruWindow(closedId)
  local useSpaces = M.sameSpaceOnly and (hs.spaces ~= nil)
  local activeSet = useSpaces and activeSpaceSet() or nil
  if activeSet and next(activeSet) == nil then activeSet = nil end

  local i = 1
  while i <= #M.mru do
    local win = M.mru[i]
    local id  = win:id()
    if not id or not win:isStandard() then
      table.remove(M.mru, i)
    else
      local app  = win:application()
      local name = app and app:name() or ""
      local ok =
        id ~= closedId
        and win:isVisible()
        and not M.skipFocusInto[name]
        and (not activeSet or onActiveSpace(win, activeSet))
      if ok then return win end
      i = i + 1
    end
  end
  return nil
end

-- True if `app` has no standard window other than the one just closed. Excluding
-- the closed window's id avoids a timing race where the destroyed window may or
-- may not still appear in the app's window list.
local function windowlessExcept(app, closedId)
  for _, w in ipairs(app:visibleWindows()) do
    if w:isStandard() and w:id() ~= closedId then return false end
  end
  return true
end

-- ---- Event handlers -------------------------------------------------------

local function onFocus(win)
  if win and win:id() then touchMru(win) end
end

local function onWindowClosed(closedWin, appName, _)
  if not M.enabled then return end
  if M.skipTriggerFrom[appName] then return end

  local frontApp = hs.application.frontmostApplication()
  if not frontApp then return end

  -- Act ONLY when the close happened in the app that is still frontmost (rules
  -- out app switches and Spotlight launches), AND that app now has no windows.
  -- If the app still has windows, macOS focuses its next window itself — we
  -- never touch that case, so there is nothing to flicker.
  if appName ~= frontApp:name() then return end
  local closedId = closedWin and closedWin:id() or nil
  if not windowlessExcept(frontApp, closedId) then return end

  if #M.mru == 0 and M.seedMru then M.seedMru() end
  removeFromMru(closedId)
  local target = nextMruWindow(closedId)
  if target and target:isStandard() then
    target:focus()
    touchMru(target)
  end
end

-- ---- Wiring ---------------------------------------------------------------

M.filter = hs.window.filter.new(nil)  -- default filter: real windows, all apps
M.filter:subscribe(hs.window.filter.windowFocused, onFocus)
M.filter:subscribe(hs.window.filter.windowDestroyed, onWindowClosed)

-- Seed the MRU with current windows (append-only, z-order; falls back to
-- visibleWindows() when orderedWindows() is momentarily empty).
local function seedMru()
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

-- Expose for CLI inspection.
M.nextMruWindow = nextMruWindow
_G.FocusFollowsClose = M
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
hs.alert.show("Focus-follows-close active  (windowless-only · toggle ⌘⌥⌃F)")

return M
