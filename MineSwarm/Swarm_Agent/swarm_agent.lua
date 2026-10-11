-- ===========================================================================
--  swarm_agent.lua   -- MINING TURTLE AGENT (ComputerCraft 1.7.5)
-- ---------------------------------------------------------------------------
--  Entry point only: installs auto-start, loads the swarm modules, boots the
--  small status UI. All behaviour lives in /swarm/agent.lua.
--
--  Run it as:            swarm_agent.lua
--  (shell.resolveProgram does NOT append ".lua", so the extension is required.)
--
--  MODEM: a turtle gets rednet from a wireless modem EQUIPPED as a turtle
--  UPGRADE (left or right side). A modem merely sitting in the inventory
--  provides no peripheral at all.
-- ===========================================================================

---------------------------------------------------------------------------
-- Self-install auto-start (written to THIS turtle's own filesystem)
---------------------------------------------------------------------------
local function installAutoStart()
    local content = table.concat({
        "-- auto-installed by swarm_agent: relaunches on every boot",
        'if not shell.path():find("/usr", 1, true) then shell.setPath(shell.path() .. ":/usr") end',
        "while true do",
        '    if fs.exists("/halt") then',
        '        print("swarm_agent auto-start is halted (delete /halt to re-enable)")',
        "        break",
        "    end",
        '    local ok, err = shell.run("/swarm_agent.lua")',
        '    if not ok then print("swarm_agent: " .. tostring(err)) end',
        "    sleep(3)",
        "end",
    }, "\n")
    if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
    local f = fs.open("/startup", "w")
    if f then f.write(content) f.close() end
end
installAutoStart()

---------------------------------------------------------------------------
-- Load modules (order matters)
---------------------------------------------------------------------------
-- Load modules (order matters).
-- NO ".lua" on purpose: os.loadAPI names the global from fs.getName(), which
-- keeps the extension, so "/swarm/theme.lua" would create a global named
-- "theme.lua" and leave `theme` nil.
local MODULES = { "/swarm/theme", "/swarm/widget", "/swarm/widgets",
                  "/swarm/app", "/swarm/agent", "/swarm/screens" }

for i = 1, #MODULES do
    if not fs.exists(MODULES[i]) then
        print("ERROR: missing " .. MODULES[i])
        print("Restore the /swarm/ folder, then re-run swarm_agent.lua")
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
if not agent.init() then
    term.setTextColor(colors.red)
    print("ERROR: no modem found on this turtle.")
    print("A turtle needs the wireless modem EQUIPPED as a turtle upgrade")
    print("(left or right side) -- an item in the inventory does not count.")
    print("Then re-run swarm_agent.lua")
    term.setTextColor(colors.white)
    return
end

---------------------------------------------------------------------------
-- App
---------------------------------------------------------------------------
local a = app.create({
    title    = "TURTLE AGENT  id " .. agent.id(),
    refresh  = 1,
    onTick   = agent.tick,
    onRednet = agent.onRednet,
})
a.statusRight     = function() return agent.status() end
a.statusRightText = function() return "up/down menu  enter=open  tab=focus" end

screens.build(a)

-- Kick registration immediately so the first frame already shows progress.
agent.register()

local ok, err = pcall(a.run)

term.clear()
term.setCursorPos(1, 1)
if not ok then
    term.setTextColor(colors.red)
    print("swarm_agent crashed: " .. tostring(err))
    term.setTextColor(colors.white)
    print("auto-start will retry in a few seconds")
else
    print("swarm_agent stopped.")
end
