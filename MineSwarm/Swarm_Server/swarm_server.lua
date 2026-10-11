-- ===========================================================================
--  swarm_server.lua   -- SWARM CONTROLLER (ComputerCraft 1.7.5)
-- ---------------------------------------------------------------------------
--  Entry point only: installs auto-start, loads the swarm modules, boots the
--  UI. All behaviour lives in /swarm/.
--
--  Run it as:            swarm_server.lua
--  (shell.resolveProgram does NOT append ".lua", so the extension is required.)
--
--  Auto-start: this program writes /startup (no extension -- that is the exact
--  name rom/startup looks up) which relaunches it on every boot. Press Quit on
--  the Settings tab to write /halt, which stops the auto-start loop; delete
--  /halt to re-enable.
-- ===========================================================================

---------------------------------------------------------------------------
-- Where is this program? It may sit at the computer root or inside a folder a
-- `git clone` created, so nothing about its own location is hard-coded.
-- shell.getRunningProgram() gives the path the shell is running, and fs.getDir
-- cuts at the last slash -- it returns "" for a file at the root, which is why
-- ROOT defaults to "/".
---------------------------------------------------------------------------
local ROOT = "/"
if shell and shell.getRunningProgram then
    local ok, me = pcall(shell.getRunningProgram)
    if ok and type(me) == "string" and me ~= "" then
        local ok2, dir = pcall(fs.getDir, me)
        if ok2 and type(dir) == "string" and dir ~= "" then ROOT = dir .. "/" end
    end
end
local SELF = ROOT .. "swarm_server.lua"

-- /startup and /halt stay at the computer root on purpose: "startup" is the exact
-- literal name rom/startup looks up, and /halt is a computer-wide kill switch.

---------------------------------------------------------------------------
-- Self-install auto-start (written to THIS computer's own filesystem)
---------------------------------------------------------------------------
local function installAutoStart()
    local content = table.concat({
        "-- auto-installed by swarm_server: relaunches on every boot",
        'if not shell.path():find("/usr", 1, true) then shell.setPath(shell.path() .. ":/usr") end',
        "while true do",
        '    if fs.exists("/halt") then',
        '        print("swarm_server auto-start is halted (delete /halt to re-enable)")',
        "        break",
        "    end",
        '    local ok, err = shell.run("' .. SELF .. '")',
        '    if not ok then print("swarm_server: " .. tostring(err)) end',
        "    sleep(3)",
        "end",
    }, "\n")
    -- rom/startup resolves the literal name "startup"; shell.resolveProgram
    -- never appends ".lua". Remove any legacy startup.lua so there is exactly
    -- one startup file.
    if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
    local f = fs.open("/startup", "w")
    if f then f.write(content) f.close() end
end
installAutoStart()

---------------------------------------------------------------------------
-- Load modules (order matters: each may reference the ones before it)
---------------------------------------------------------------------------
-- Load modules (order matters: each may reference the ones before it).
-- NO ".lua" here on purpose: os.loadAPI names the global from fs.getName(),
-- which keeps the extension -- "/swarm/theme.lua" would create a global called
-- "theme.lua" and leave `theme` nil. CC's own rom/apis files are extension-less
-- for exactly this reason.
local MODULES = { ROOT .. "swarm/theme", ROOT .. "swarm/widget", ROOT .. "swarm/widgets",
                  ROOT .. "swarm/app", ROOT .. "swarm/core", ROOT .. "swarm/screens" }

for i = 1, #MODULES do
    if not fs.exists(MODULES[i]) then
        print("ERROR: missing " .. MODULES[i])
        print("Restore the swarm/ folder that sits next to swarm_server.lua, then re-run it")
        return
    end
    if not os.loadAPI(MODULES[i]) then
        print("ERROR: failed to load " .. MODULES[i])
        return
    end
end

theme.auto()

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------
if not core.init() then
    term.setTextColor(colors.red)
    print("ERROR: no modem found on this computer.")
    print("Attach a modem to any side, then re-run swarm_server.lua")
    term.setTextColor(colors.white)
    return
end

---------------------------------------------------------------------------
-- App
---------------------------------------------------------------------------
local a = app.create({
    title    = "SWARM CONTROLLER  id " .. core.address(),
    refresh  = 1,
    onTick   = core.tick,
    onRednet = core.onRednet,
})

local function fmtUp(s)
    s = math.floor(s)
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
end
a.statusRight      = function() return "up " .. fmtUp(os.clock()) end
-- The bottom bar carries the last action plus the key hints only; fleet
-- counts live on the Dashboard and Turtles screens now.
a.statusRightText  = function() return "up/down menu  enter=open  tab=focus" end

-- Declarative actions feed the Cluster tab.
local defs = core.actionDefs()
local names = {}
for k in pairs(defs) do table.insert(names, k) end
table.sort(names)
for i = 1, #names do
    a.registerAction(names[i], defs[names[i]])
end

screens.build(a)

local ok, err = pcall(a.run)

-- Leave the terminal in a sane state whatever happened.
term.clear()
term.setCursorPos(1, 1)
if not ok then
    term.setTextColor(colors.red)
    print("swarm_server crashed: " .. tostring(err))
    term.setTextColor(colors.white)
    print("auto-start will retry in a few seconds (Quit on Settings writes /halt)")
else
    print("swarm_server stopped.")
end
