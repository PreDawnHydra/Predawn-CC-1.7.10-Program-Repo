-- ===========================================================================
--  diskarray_host.lua   -   export this computer's Disk Drives over rednet
-- ---------------------------------------------------------------------------
--  Run this on a computer that has Disk Drives attached (and a wired modem).
--  A DiskArray server pings the network, this answers with a snapshot of its
--  drives, and the server shows them as drives named "#<computerID>:<side>".
--  The array definition still lives on the floppies: enrolling one of these
--  drives asks THIS computer to write the manifest, using the same manifest
--  module the server has.
--
--  It needs no UI, so it loads only three modules and stays small enough to run
--  on a plain computer next to a stack of drives.
--
--  Usage:  diskarray_host.lua [--beacon <secs>] [--allow <id,id>] [--once]
--            --beacon  how often to re-announce the drive list (default 10)
--            --allow   only take orders from these computer IDs (default: any)
--            --once    print what would be reported, then exit (a check)
--            --help    this text
--
--  Stop it with Ctrl+T. The server notices a host that stopped answering after
--  --host-timeout seconds and drops its drives from the pool.
-- ===========================================================================

local USAGE = {
    "usage: diskarray_host.lua [--beacon <secs>] [--allow <id,id>] [--once] [--help]",
    "",
    "  exports this computer's Disk Drives to a DiskArray server over rednet.",
    "  needs a wired modem on any side, and the diskarray/ folder next to it.",
}

local ROOT = "/"
if shell and shell.getRunningProgram then
    local ok, me = pcall(shell.getRunningProgram)
    if ok and type(me) == "string" and me ~= "" then
        local ok2, dir = pcall(fs.getDir, me)
        if ok2 and type(dir) == "string" and dir ~= "" then ROOT = dir .. "/" end
    end
end

local beacon, allow, once = 10, nil, false
local argv = { ... }
local i = 1
while i <= #argv do
    local a = argv[i]
    if a == "--help" or a == "-h" then
        for j = 1, #USAGE do print(USAGE[j]) end
        return
    elseif a == "--beacon" then
        beacon = tonumber(argv[i + 1]) or beacon; i = i + 2
    elseif a == "--once" then
        once = true; i = i + 1
    elseif a == "--allow" then
        allow = {}
        local spec = tostring(argv[i + 1] or "")
        for part in string.gmatch(spec, "[^,]+") do
            local id = tonumber(part)
            if id then allow[id] = true end
        end
        i = i + 2
    else
        print("unknown argument: " .. tostring(a))
        for j = 1, #USAGE do print(USAGE[j]) end
        return
    end
end
if beacon < 2 then beacon = 2 end

local MODULES = { ROOT .. "diskarray/manifest", ROOT .. "diskarray/pool", ROOT .. "diskarray/net" }
for m = 1, #MODULES do
    if not fs.exists(MODULES[m]) then
        print("ERROR: missing " .. MODULES[m])
        print("Copy the whole DiskArray/Server folder onto this computer, then re-run it")
        return
    end
    if not os.loadAPI(MODULES[m]) then
        print("ERROR: failed to load " .. MODULES[m])
        return
    end
end

local MY_ID = os.getComputerID()
local PROTO = net.protocol()

---------------------------------------------------------------------------
-- Modems: open every side that has one. No modem means this program has
-- nothing to say for itself, so say so plainly instead of sitting silent.
---------------------------------------------------------------------------
local modems = {}
local names = peripheral.getNames()
for n = 1, #names do
    if peripheral.getType(names[n]) == "modem" then
        rednet.open(names[n])
        table.insert(modems, names[n])
    end
end
if #modems == 0 then
    print("ERROR: no modem on any side. Attach a wired modem to this computer.")
    return
end

---------------------------------------------------------------------------
-- Orders from the server. Any computer on the rednet can send these, so
-- --allow exists; without it, treat the network as trusted (it is your own
-- wire) and say which orders were taken.
---------------------------------------------------------------------------
local function allowed(from)
    if allow == nil then return true end
    return allow[from] == true
end

local function act(side, action, label, data)
    if type(side) ~= "string" or side == "" then return false, "no side in the message" end
    if action == "eject" then
        return pool.eject(side)
    elseif action == "label" then
        return pool.setLabel(side, label)
    elseif action == "manifest" then
        local r = pool.get(side)
        if not r then return false, "no such drive here: " .. side end
        if not r.mount then return false, side .. " has no mounted disk" end
        if type(data) ~= "table" then return false, "no manifest in the message" end
        -- written by THIS computer's manifest module, so the file format stays
        -- in one place and a server can never invent a format the disks will
        -- not understand
        return manifest.write(r.mount, data)
    elseif action == "unmanifest" then
        return pool.clearManifest(side)
    end
    return false, "unknown action: " .. tostring(action)
end

local host = net.serve({
    computer = MY_ID,
    provider = function()
        pool.scan()
        return pool.drives()
    end,
    act = act,
})

local function send(msg)
    if type(msg) ~= "table" or msg.to == nil then return end
    pcall(rednet.send, msg.to, msg, PROTO)
end

local function broadcast(msgs)
    for j = 1, #msgs do pcall(rednet.broadcast, msgs[j], PROTO) end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
pool.scan()
if once then
    print("host #" .. MY_ID .. " would report " .. pool.count() .. " drive(s):")
    local msgs = host.push()
    for j = 1, #msgs do
        local d = msgs[j].drives
        for k = 1, #d do
            print(string.format("  %-6s %-10s %-8s %s", d[k].side,
                tostring(d[k].label or "-"),
                tostring(d[k].free or "?"),
                tostring(d[k].array or "no manifest")))
        end
    end
    return
end

print("DiskArray host #" .. MY_ID .. ": " .. #modems .. " modem(s), "
      .. pool.count() .. " drive(s), beacon " .. beacon .. "s")
broadcast(host.push())
os.startTimer(beacon)

---------------------------------------------------------------------------
-- Loop. Everything is event driven: a ping gets answered, a disk swap gets
-- pushed, a beacon keeps the roster warm.
---------------------------------------------------------------------------
local okRun, errRun = pcall(function()
    while true do
        local event, a, b, c = os.pullEvent()
        if event == "rednet_message" then
            -- 1.75 order, read out of rom/apis/rednet in the jar:
            --   rednet_message <replyChannel> <message> <protocol>
            -- where replyChannel is the SENDER's computer id (rednet uses it as
            -- the reply channel). Modern CC's (protocol, sender, message) order
            -- would silently treat the protocol string as a computer id.
            local sender, message, protocol = a, b, c
            if protocol == PROTO then
                if allowed(sender) then
                    local replies = host.onMessage(message)
                    for j = 1, #replies do
                        replies[j].to = sender
                        send(replies[j])
                    end
                end
            end
        elseif event == "disk" or event == "disk_eject" then
            broadcast(host.push())
        elseif event == "peripheral_attach" or event == "peripheral_detach" then
            -- only a drive changing matters here; a monitor being wired up
            -- should not make the host shout at the network
            if peripheral.getType(a) == "drive" then broadcast(host.push()) end
        elseif event == "timer" then
            broadcast(host.push())
            os.startTimer(beacon)
        end
    end
end)

---------------------------------------------------------------------------
-- Leave the network tidy
---------------------------------------------------------------------------
for n = 1, #modems do pcall(rednet.close, modems[n]) end
term.clear()
term.setCursorPos(1, 1)
if okRun then
    print("host stopped.")
else
    print("diskarray_host crashed: " .. tostring(errRun))
end
