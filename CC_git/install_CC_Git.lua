-- install_CC_Git.lua -- put git.lua in a permanent place on this computer and
-- make the command `git` work from any directory.
--
--   install_CC_Git           install anything missing, refresh anything present
--   install_CC_Git update    ignore local copies and re-download from GitHub
--   install_CC_Git status    what is installed, and whether the path entry is in place
--   install_CC_Git unhook    take the path entry out of /startup again
--
-- Running it again is safe: files that already match are left alone, and a failed
-- download never removes a working copy.
--
-- It writes the programs into /usr and adds /usr to the shell's search path from
-- /startup, which ComputerCraft runs at boot. After installing, type `reboot`
-- once. From then on:
--
--   cd myfolder
--   git clone you/repo          -> clones into ./repo, like git on a desktop
--   git status                  -> acts on the clone in the current directory
--
-- Version 1.1.0 - ComputerCraft 1.75 (Lua 5.1).

-- where to pull from when there is no local copy on this machine
local RAW     = "https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/"
-- fetched name -> installed name. ComputerCraft's shell matches program names
-- exactly (it never appends .lua), so what lands in /usr has no extension.
local FILES   = { { "git.lua", "git" }, { "install_CC_Git.lua", "install_CC_Git" } }
local DIR     = "/usr"
local STARTUP = "/startup"
local MARKER  = "-- git.lua path entry (added by install_CC_Git.lua)"

--------------------------------------------------------------------------------

local function readText(path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local s = h.readAll() or ""
  h.close()
  return s
end

local function writeText(path, text)
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(text)
  h.close()
  return true
end

-- the directory this script itself was run from, when the shell can tell us
local function here()
  if shell and shell.getRunningProgram then
    local ok, p = pcall(shell.getRunningProgram)
    if ok and type(p) == "string" and p ~= "" then
      local ok2, d = pcall(fs.getDir, p)
      if ok2 and type(d) == "string" and d ~= "" then return d end
    end
  end
  return nil
end

local function join(a, b)
  if a == "/" then return "/" .. b end
  return a .. "/" .. b
end

local function localCopy(names)
  local dirs = {}
  local h = here()
  if h then dirs[#dirs + 1] = h end
  dirs[#dirs + 1] = "/disk"
  dirs[#dirs + 1] = "."
  dirs[#dirs + 1] = "/"
  for _, d in ipairs(dirs) do
    for _, name in ipairs(names) do
      local p = join(d, name)
      if fs.exists(p) and not fs.isDir(p) then return p end
    end
  end
  return nil
end

local function fetch(url)
  local res = http.get(url)
  if not res then
    return nil, "no network, host blocked, or 404 (ComputerCraft 1.75 cannot tell those apart)"
  end
  local code = res.getResponseCode and res.getResponseCode() or 0
  local body = res.readAll() or ""
  res.close()
  if code >= 400 then return nil, "HTTP " .. code end
  -- readAll() drops the final newline
  if body:sub(-1) ~= "\n" then body = body .. "\n" end
  return body
end

local function versionOf(text)
  if not text then return "?" end
  return text:match('git%.VERSION%s*=%s*"([^"]+)"') or "?"
end

local function ensureDir(d)
  if fs.exists(d) then return fs.isDir(d) end
  -- ComputerCraft 1.75: fs.makeDir returns nothing and raises on failure, so the
  -- only honest check is whether the directory exists afterwards.
  pcall(fs.makeDir, d)
  return fs.isDir(d)
end

-- The hook is ONE line, tagged with MARKER, so it is easy to detect, to keep
-- idempotent, and to remove again with `install_CC_Git unhook`.
local function startupLine()
  return MARKER .. " if not shell.path():find(" .. string.format("%q", DIR) .. ", 1, true) then" ..
    " shell.setPath(shell.path() .. " .. string.format("%q", ":" .. DIR) .. ") end"
end

-- Signatures of the multi-line block written by older installers. Those blocks sat
-- at the BOTTOM of /startup, so on a computer with a startup script of its own they
-- never ran - which is why an upgrade has to migrate them, not just notice that a
-- marker is present somewhere.
local function hookTail(line, state)
  if state == 0 then
    if line:find("if not shell.path():find(", 1, true) then return 1 end
  elseif state == 1 then
    if line:find("shell.setPath(shell.path() .. " .. string.format("%q", ":" .. DIR) .. ")", 1, true) then
      return 2
    end
  elseif state == 2 then
    if line:match("^%s*end%s*$") then return 3 end
  end
  return nil
end

-- every trace of our hook, old block included
local function stripHook(text)
  local kept, state = "", 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:find(MARKER, 1, true) then
      state = 0                      -- our one-liner, or the first line of an old block
    else
      local nxt = hookTail(line, state)
      if nxt then
        state = nxt
      else
        state = 0
        kept = kept .. line .. "\n"
      end
    end
  end
  return kept
end

local function blank(t) return t:gsub("%s+", "") == "" end

-- /rom is a read-only JarMount in ComputerCraft 1.75, so /startup in the computer
-- root is the only boot hook there is. Their startup may error out or run forever,
-- so our line goes at the TOP: appended, it would never be reached.
local function ensureStartup()
  local cur = readText(STARTUP)
  if cur == nil then
    if not writeText(STARTUP, startupLine() .. "\n") then return "FAILED writing " .. STARTUP end
    return "created " .. STARTUP .. " with the path entry"
  end
  local want = startupLine() .. "\n" .. stripHook(cur)
  if want:gsub("%s+$", "") == cur:gsub("%s+$", "") then
    return "path entry already at the top of " .. STARTUP
  end
  if not writeText(STARTUP, want) then return "FAILED writing " .. STARTUP end
  if cur:find(MARKER, 1, true) then return "moved the path entry to the top of " .. STARTUP end
  return "added the path entry to the top of " .. STARTUP
end

-- drop only the lines we added; everything else in their startup stays put
local function removeStartup()
  local cur = readText(STARTUP)
  if cur == nil then return "no " .. STARTUP .. " to change" end
  if not cur:find(MARKER, 1, true) and not cur:find("if not shell.path():find(", 1, true) then
    return "no path entry in " .. STARTUP
  end
  local kept = stripHook(cur)
  if blank(kept) then
    -- nothing of theirs was in there, so take the file away too
    local ok = pcall(fs.delete, STARTUP)
    return ok and "removed the path entry and " .. STARTUP or "removed the path entry from " .. STARTUP
  end
  if not writeText(STARTUP, kept) then return "FAILED writing " .. STARTUP end
  return "removed the path entry from " .. STARTUP
end

-- install, refresh or leave alone. Returns ok, note where note is one of
-- new / updated / current / kept / failed
local function one(item, preferNet)
  local name, target = item[1], item[2] or item[1]
  local dest = join(DIR, target)
  local existing = nil
  if fs.exists(dest) and not fs.isDir(dest) then existing = readText(dest) end

  local text, source
  if not preferNet then
    local p = localCopy({ name, target })
    if p then
      text = readText(p)
      source = p
    end
  end
  if not text then
    -- fetch returns the body only; keep the URL separate instead of assuming it
    -- hands back two values, or source ends up nil and the print below throws
    local body, err = fetch(RAW .. name)
    if not body then
      if existing then
        printError("  ! " .. target .. ": " .. tostring(err) .. " - keeping the installed copy")
        return true, "kept"
      end
      printError("  ! " .. target .. ": " .. tostring(err))
      return false, "failed"
    end
    text, source = body, RAW .. name
  end

  if #text < 200 then
    printError("  ! " .. target .. ": only " .. #text .. " bytes - that does not look like the program")
    if existing then return true, "kept" end
    return false, "failed"
  end

  if existing == text then
    print(string.format("  %-16s %6d bytes  v%-7s  up to date", target, #text, versionOf(text)))
    return true, "current"
  end

  if not writeText(dest, text) then
    printError("  ! " .. target .. ": cannot write " .. dest .. " (disk full?)")
    return false, "failed"
  end
  print(string.format("  %-16s %6d bytes  v%-7s  %s from %s", target, #text, versionOf(text),
    existing and "updated" or "new", tostring(source)))
  return true, existing and "updated" or "new"
end

local function status()
  print("programs in " .. DIR .. ":")
  local found = false
  for _, item in ipairs(FILES) do
    local target = item[2] or item[1]
    local p = join(DIR, target)
    if fs.exists(p) and not fs.isDir(p) then
      found = true
      print(string.format("  %-16s %6d bytes  version %s", target, fs.getSize(p), versionOf(readText(p))))
    else
      print("  " .. target .. ": not installed")
    end
  end
  local startup = readText(STARTUP)
  if startup == nil then
    print(STARTUP .. ": no startup script at all - git will not be on the path after a reboot")
  elseif startup:match("^[^\n]*"):find(MARKER, 1, true) then
    print(STARTUP .. ": path entry is line 1, where it belongs")
  elseif startup:find(MARKER, 1, true) then
    print(STARTUP .. ": path entry is buried below your own startup - run install_CC_Git to move it")
  else
    print(STARTUP .. ": no path entry - run install_CC_Git")
  end
  print("shell path now: " .. tostring(shell.path()))
  return found
end

local function main(args)
  local action = args[1]
  if action == "status" then
    status()
    return true
  end
  if action == "unhook" then
    print(removeStartup())
    print("the programs stay in " .. DIR .. " - call them as " .. DIR .. "/git if you unhook")
    return true
  end
  if action ~= "update" and action ~= nil and action ~= "install" then
    print("usage: install_CC_Git [update|status|unhook]")
    return false
  end

  -- no arguments: install what is missing, refresh what is already there.
  -- "update" skips any copy sitting next to the script and goes to GitHub.
  local preferNet = (action == "update")
  print((preferNet and "updating " .. DIR .. " from GitHub" or "installing or updating " .. DIR))
  if not ensureDir(DIR) then
    printError("cannot create " .. DIR)
    return false
  end

  local counts, okAll = { new = 0, updated = 0, current = 0, kept = 0, failed = 0 }, true
  for _, item in ipairs(FILES) do
    local ok, note = one(item, preferNet)
    counts[note] = (counts[note] or 0) + 1
    if not ok then okAll = false end
  end

  print(ensureStartup())
  print(string.format("summary: %d new, %d updated, %d already current, %d kept, %d failed",
    counts.new, counts.updated, counts.current, counts.kept, counts.failed))
  if not okAll then
    printError("installed with errors - check the messages above")
    return false
  end

  print("")
  print("done. type `reboot` once to pick up the new path, then from any folder:")
  print("  git help")
  print("  git clone you/repo          (clones into ./repo)")
  return true
end

return main({ ... })
