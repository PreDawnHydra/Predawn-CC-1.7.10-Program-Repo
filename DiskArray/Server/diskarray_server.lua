-- ===========================================================================
--  diskarray_server.lua   -- DISKARRAY SERVER (ComputerCraft 1.7.10 / CC 1.75)
-- ---------------------------------------------------------------------------
--  Slice 1: find the Disk Drives on this computer, show a clickable pool
--  (totals + a capacity bar per drive), and let you rescan or eject a disk.
--  No manifest, no striping, no rednet yet — see ../README.md for the roadmap.
--
--  Run it as:            diskarray_server.lua
--  (shell.resolveProgram never appends ".lua", so the extension is required.)
--
--  Options:
--    --monitor <side>   draw the UI on a monitor instead of the computer
--                       screen; the monitor is clickable too, because 1.75
--                       sends monitor_touch (side, x, y) when a player clicks
--                       it — there is no monitor_click in this version.
--    --refresh <secs>   redraw/tick interval (default 1)
--    --rescan <secs>    re-scan the drives this often (default 10; a disk or
--                       disk_eject event rescans immediately either way)
--    --help             this text
--
--  Auto-start is deliberately NOT installed by this slice — it writes /startup,
--  which is a computer-wide change, and the array is still discovery-only.
--  That is roadmap work; run this program by name for now.
-- ===========================================================================

local USAGE = {
    "usage: diskarray_server.lua [--monitor <side>] [--refresh <secs>] [--rescan <secs>]",
    "",
    "  --monitor <side>  put the UI on a monitor (clickable via monitor_touch)",
    "  --refresh <secs>  redraw interval, default 1",
    "  --rescan  <secs>  drive re-scan interval, default 10",
    "",
    "Click a screen in the sidebar. On the keyboard: up/down move the sidebar,",
    "right/tab move into the buttons, enter presses them.",
}

---------------------------------------------------------------------------
-- Where is this program? It may sit at the computer root, on a floppy, or
-- inside a folder a `git clone` made, so nothing about its own location is
-- hard-coded. fs.getDir cuts at the last slash and returns "" for a file at
-- the root — hence the "/" default.
---------------------------------------------------------------------------
local ROOT = "/"
if shell and shell.getRunningProgram then
    local ok, me = pcall(shell.getRunningProgram)
    if ok and type(me) == "string" and me ~= "" then
        local ok2, dir = pcall(fs.getDir, me)
        if ok2 and type(dir) == "string" and dir ~= "" then ROOT = dir .. "/" end
    end
end

---------------------------------------------------------------------------
-- Arguments
---------------------------------------------------------------------------
local function usage()
    for i = 1, #USAGE do print(USAGE[i]) end
end

local monitorSide, refresh, rescanEvery = nil, 1, 10
local argv = { ... }
local i = 1
while i <= #argv do
    local a = argv[i]
    if a == "--help" or a == "-h" then
        usage(); return
    elseif a == "--monitor" then
        monitorSide = argv[i + 1]; i = i + 2
    elseif a == "--refresh" then
        refresh = tonumber(argv[i + 1]) or refresh; i = i + 2
    elseif a == "--rescan" then
        rescanEvery = tonumber(argv[i + 1]) or rescanEvery; i = i + 2
    else
        print("unknown argument: " .. tostring(a)); usage(); return
    end
end
if refresh < 0.5 then refresh = 0.5 end
if rescanEvery < 1 then rescanEvery = 1 end

---------------------------------------------------------------------------
-- Modules. NO ".lua" in these paths: os.loadAPI names the global from
-- fs.getName(), which keeps the extension, so "diskarray/theme.lua" would
-- create a global called "theme.lua" and leave `theme` nil.
---------------------------------------------------------------------------
local MODULES = { ROOT .. "diskarray/theme", ROOT .. "diskarray/widget",
                  ROOT .. "diskarray/widgets", ROOT .. "diskarray/app",
                  ROOT .. "diskarray/pool", ROOT .. "diskarray/screens" }

for m = 1, #MODULES do
    if not fs.exists(MODULES[m]) then
        print("ERROR: missing " .. MODULES[m])
        print("Restore the diskarray/ folder that sits next to diskarray_server.lua, then re-run it")
        return
    end
    if not os.loadAPI(MODULES[m]) then
        print("ERROR: failed to load " .. MODULES[m])
        return
    end
end

theme.auto()

---------------------------------------------------------------------------
-- Optional monitor surface
---------------------------------------------------------------------------
local originalTerm = term.current()
local onMonitor = false
if monitorSide then
    if peripheral.getType(monitorSide) ~= "monitor" then
        print("ERROR: " .. tostring(monitorSide) .. " is not a monitor")
        print("Attach a monitor to that side (or pass --monitor <side> with the right name)")
        return
    end
    local mon = peripheral.wrap(monitorSide)
    if not mon then
        print("ERROR: could not wrap the monitor on " .. tostring(monitorSide))
        return
    end
    originalTerm = term.current()
    term.redirect(mon)
    onMonitor = true
end

---------------------------------------------------------------------------
-- First scan, before any UI exists, so the screens always have data
---------------------------------------------------------------------------
pool.scan()

local a = app.create({
    title   = "DISKARRAY  id " .. tostring(os.getComputerID()) ..
              (onMonitor and ("  mon:" .. tostring(monitorSide)) or ""),
    refresh = refresh,

    -- A floppy swap is an event, not something to poll for.
    onEvent = function(event)
        if pool.isPoolEvent(event) then
            pool.scan()
            a.notify("drive change: " .. pool.lastScanNote(), "dim")
        end
    end,

    onTick = function()
        if pool.age() >= rescanEvery then
            pool.scan()
        end
    end,
})

a.statusRight     = function() return pool.count() .. " drives  " .. pool.bytes(pool.summary().totalFree) .. " free" end
a.statusRightText = function() return "up/down menu  enter=open  tab=focus  click works" end

screens.build(a)

local ok, err = pcall(a.run)

---------------------------------------------------------------------------
-- Leave the terminal in a sane state whatever happened
---------------------------------------------------------------------------
if onMonitor then
    term.redirect(originalTerm)
end
term.clear()
term.setCursorPos(1, 1)
if not ok then
    term.setTextColor(colors.red)
    print("diskarray_server crashed: " .. tostring(err))
    term.setTextColor(colors.white)
    print("re-run: diskarray_server.lua")
else
    print("diskarray_server stopped.")
    print("drives: " .. pool.lastScanNote())
end
