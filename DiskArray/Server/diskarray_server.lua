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
    "                            [--discover <secs>] [--host-timeout <secs>]",
    "                            [--file-timeout <secs>] [--no-net]",
    "",
    "  --monitor <side>    put the UI on a monitor (clickable via monitor_touch)",
    "  --refresh <secs>    redraw interval, default 1",
    "  --rescan  <secs>    local drive re-scan interval, default 10",
    "  --discover <secs>   ask the network for host drives, default 5",
    "  --host-timeout <s>  drop a host silent this long, default 20",
    "  --no-net            ignore modems: only this computer's drives",
    "",
    "Run diskarray_host.lua on any other computer whose drives you want here.",
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
local noNet, discoverEvery, hostTimeout = false, 5, 20
local fileTimeout, fileTimeoutOpt = 15, nil
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
    elseif a == "--discover" then
        discoverEvery = tonumber(argv[i + 1]) or discoverEvery; i = i + 2
    elseif a == "--file-timeout" then
        fileTimeoutOpt = tonumber(argv[i + 1]); i = i + 2
    elseif a == "--host-timeout" then
        hostTimeout = tonumber(argv[i + 1]) or hostTimeout; i = i + 2
    elseif a == "--no-net" then
        noNet = true; i = i + 1
    else
        print("unknown argument: " .. tostring(a)); usage(); return
    end
end
if refresh < 0.5 then refresh = 0.5 end
if rescanEvery < 1 then rescanEvery = 1 end
if discoverEvery < 1 then discoverEvery = 1 end
if type(fileTimeoutOpt) == "number" and fileTimeoutOpt > 0 then fileTimeout = fileTimeoutOpt end
if hostTimeout < 5 then hostTimeout = 5 end

---------------------------------------------------------------------------
-- Modules. NO ".lua" in these paths: os.loadAPI names the global from
-- fs.getName(), which keeps the extension, so "diskarray/theme.lua" would
-- create a global called "theme.lua" and leave `theme` nil.
---------------------------------------------------------------------------
local MODULES = { ROOT .. "diskarray/theme", ROOT .. "diskarray/widget",
                  ROOT .. "diskarray/widgets", ROOT .. "diskarray/app",
                  ROOT .. "diskarray/manifest", ROOT .. "diskarray/pool",
                  ROOT .. "diskarray/net", ROOT .. "diskarray/builder",
                  ROOT .. "diskarray/files", ROOT .. "diskarray/screens" }

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
-- Network: drives behind a wired modem belong to other computers, and this
-- program never touches them directly. It asks; the host writes.
---------------------------------------------------------------------------
local MY_ID = os.getComputerID()
local PROTO = net.protocol()
local modems = {}
local srv = net.listen({ timeout = hostTimeout })

if not noNet then
    local names = peripheral.getNames()
    for n = 1, #names do
        if peripheral.getType(names[n]) == "modem" then
            if pcall(rednet.open, names[n]) then table.insert(modems, names[n]) end
        end
    end
    if #modems == 0 then
        print("note: no modem found - only drives on this computer will be visible")
        print("      run diskarray_host.lua on a computer that has drives")
    end
end

local function broadcast(msg)
    for n = 1, #modems do pcall(rednet.broadcast, msg, PROTO) end
end

local lastPing = 0
local function pingHosts()
    if #modems == 0 then return end
    lastPing = os.clock()
    broadcast(net.pingMsg(MY_ID))
end

local function absorbRemote()
    pool.setRemote(srv.drives())
    pool.scan()
end

-- Acting on a remote drive is a request, not a call: the host does it and then
-- pushes its new drive list, so the pool catches up within a tick rather than
-- the UI blocking on a modem round trip.
pool.setActFn(function(r, action, label, data)
    if #modems == 0 then return false, "no modem: cannot reach host #" .. tostring(r.computer) end
    local ok, err = pcall(rednet.send, r.computer, net.actMsg(MY_ID, r.computer, r.side,
                                                             action, label, data), PROTO)
    if not ok then return false, tostring(err) end
    return true, "asked host #" .. tostring(r.computer) .. " to " .. tostring(action)
end)
pool.setNetInfo(function() return srv.hosts() end)

---------------------------------------------------------------------------
-- File transfer needs an ANSWER, not just a request, so a put or a get waits
-- for its host. os.pullEvent in a nested loop is how 1.75 does that: the UI
-- stops redrawing while a file crosses the wire, other hosts' pushes are
-- dropped (the next --discover tick puts them back), and the wait is bounded by
-- a timer so a dead host cannot hang the program.
---------------------------------------------------------------------------
local function askHost(computer, msg, timeout)
    if type(computer) ~= "number" then return false, "not a remote drive" end
    if #modems == 0 then return false, "no modem: cannot reach host #" .. tostring(computer) end
    local wait = (type(timeout) == "number" and timeout > 0) and timeout or fileTimeout
    local deadline = os.clock() + wait
    local okSend, serr = pcall(rednet.send, computer, msg, PROTO)
    if not okSend then return false, tostring(serr) end
    os.startTimer(wait)
    while true do
        local ev, a1, a2 = os.pullEvent()
        if ev == "rednet_message" then
            -- 1.75 order: (replyChannel = the sender's computer id, message, protocol)
            local sender, message = a1, a2
            if sender == computer and type(message) == "table" and message.id == msg.id then
                return true, message
            end
        elseif ev == "timer" then
            if os.clock() >= deadline - 0.05 then
                return false, "no answer from host #" .. tostring(computer)
                    .. " in " .. wait .. "s"
            end
            os.startTimer(math.max(0.2, deadline - os.clock()))
        elseif ev == "terminate" then
            return false, "interrupted"
        elseif pool.isPoolEvent(ev) then
            pool.scan()
        end
    end
end

files.setTransport(askHost)

---------------------------------------------------------------------------
-- First scan, before any UI exists, so the screens always have data
---------------------------------------------------------------------------
pool.scan()
pingHosts()

local a = app.create({
    title   = "DISKARRAY  id " .. tostring(os.getComputerID()) ..
              (onMonitor and ("  mon:" .. tostring(monitorSide)) or ""),
    refresh = refresh,
    -- No bottom status row: the body runs to the last row of the screen. Notes
    -- (including failures) go to the top-right of the title bar instead, so a
    -- click still says what it did without a bar under the UI.
    showStatusBar = false,

    -- A floppy swap is an event, not something to poll for.
    onEvent = function(event, p1, p2, p3)
        if event == "rednet_message" then
            -- 1.75 order (rom/apis/rednet): <replyChannel> <message> <protocol>
            local sender, message, protocol = p1, p2, p3
            if protocol == PROTO and type(message) == "table" then
                srv.onMessage(message)
                absorbRemote()
                a.rebuild()
                local ev = srv.takeEvents()
                for k = 1, #ev do a.notify(ev[k], "dim") end
                if #ev == 0 then
                    a.notify("host #" .. tostring(sender) .. " reported its drives", "dim")
                end
            end
            return
        end
        if pool.isPoolEvent(event) then
            pool.scan()
            a.rebuild()
            a.notify("drive change: " .. pool.lastScanNote(), "dim")
        end
    end,

    onTick = function()
        local changed = false
        if pool.age() >= rescanEvery then
            pool.scan()
            changed = true
        end
        if #modems > 0 and os.clock() - lastPing >= discoverEvery then
            lastPing = os.clock()
            pingHosts()
            if srv.expire() > 0 then changed = true end
            absorbRemote()
        end
        if changed then a.rebuild() end
    end,
})

-- The Builder's "Ping hosts" button.
a.pingHosts = function()
    lastPing = os.clock()
    pingHosts()
end

a.statusRight     = function()
    local a2 = pool.arraySummary()
    local hosts = #srv.hosts()
    return pool.count() .. " drives" .. (hosts > 0 and (" (" .. hosts .. " host)") or "")
        .. "  " .. pool.bytes(pool.summary().totalFree) .. " free  " .. a2.state
end

screens.build(a)

local ok, err = pcall(a.run)

---------------------------------------------------------------------------
-- Leave the terminal in a sane state whatever happened
---------------------------------------------------------------------------
if #modems > 0 then
    broadcast(net.byeMsg(MY_ID))
    for n = 1, #modems do pcall(rednet.close, modems[n]) end
end
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
