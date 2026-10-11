-- install_CC_Git.lua -- put git.lua in a permanent place on this computer and
-- make the command `git` work from any directory.
--
--   /disk/install_CC_Git        install (or refresh) using the copy sitting
--                             next to this script, falling back to GitHub
--   install_CC_Git update     always re-download from GitHub
--   install_CC_Git status     what is installed, and whether the path entry is in place
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
local FILES   = { "git.lua" }
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

local function localCopy(name)
  local dirs = {}
  local h = here()
  if h then dirs[#dirs + 1] = h end
  dirs[#dirs + 1] = "/disk"
  dirs[#dirs + 1] = "."
  dirs[#dirs + 1] = "/"
  for _, d in ipairs(dirs) do
    local p = join(d, name)
    if fs.exists(p) and not fs.isDir(p) then return p end
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

-- append the path entry to /startup, once
local function ensureStartup()
  local cur = readText(STARTUP) or ""
  if cur:find(MARKER, 1, true) then return "path entry already in " .. STARTUP end
  local block = "\n" .. MARKER .. "\n" ..
    "if not shell.path():find(" .. string.format("%q", DIR) .. ", 1, true) then\n" ..
    "    shell.setPath(shell.path() .. " .. string.format("%q", ":" .. DIR) .. ")\n" ..
    "end\n"
  if not writeText(STARTUP, cur .. block) then return "FAILED writing " .. STARTUP end
  return "added the path entry to " .. STARTUP
end

local function one(name, fromNet)
  local text, source
  if not fromNet then
    local p = localCopy(name)
    if p then
      text = readText(p)
      source = p
    end
  end
  if not text then
    text, source = fetch(RAW .. name)
    if not text then
      printError("  ! " .. name .. ": " .. tostring(source))
      return false
    end
  end
  if #text < 200 then
    printError("  ! " .. name .. ": only " .. #text .. " bytes - that does not look like the program")
    return false
  end
  if not writeText(join(DIR, name), text) then
    printError("  ! " .. name .. ": cannot write " .. join(DIR, name) .. " (disk full?)")
    return false
  end
  print(string.format("  %-14s %6d bytes  v%-7s from %s", name, #text, versionOf(text), source))
  return true
end

local function status()
  print("programs in " .. DIR .. ":")
  local found = false
  for _, name in ipairs(FILES) do
    local p = join(DIR, name)
    if fs.exists(p) and not fs.isDir(p) then
      found = true
      print(string.format("  %-14s %6d bytes  version %s", name, fs.getSize(p), versionOf(readText(p))))
    else
      print("  " .. name .. ": not installed")
    end
  end
  local startup = readText(STARTUP)
  print(STARTUP .. ": " .. ((startup and startup:find(MARKER, 1, true)) and "has the path entry" or "no path entry"))
  print("shell path now: " .. tostring(shell.path()))
  return found
end

local function main(args)
  local action = args[1]
  if action == "status" then
    status()
    return true
  end
  if action ~= "update" and action ~= nil and action ~= "install" then
    print("usage: install_CC_Git [install|update|status]")
    return false
  end

  local fromNet = (action == "update")
  print((fromNet and "downloading into " or "installing into ") .. DIR)
  if not ensureDir(DIR) then
    printError("cannot create " .. DIR)
    return false
  end

  local okAll = true
  for _, name in ipairs(FILES) do
    if not one(name, fromNet) then okAll = false end
  end

  print(ensureStartup())
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
