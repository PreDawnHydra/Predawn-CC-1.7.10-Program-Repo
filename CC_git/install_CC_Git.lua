-- install_CC_Git.lua -- put git.lua in a permanent place on this computer and
-- make the command `git` work from any directory.
--
--   install_CC_Git           install anything missing, refresh anything present
--   install_CC_Git update    ignore local copies and re-download from GitHub
--   install_CC_Git status    what is installed, and whether the path entry is in place
--   install_CC_Git hook      print the path line, for a /startup you generate yourself
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
-- Version 1.2.0 - ComputerCraft 1.75 (Lua 5.1).

-- where to pull from when there is no local copy on this machine
local RAW     = "https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/"
-- fetched name -> installed name. ComputerCraft's shell matches program names
-- exactly (it never appends .lua), so what lands in /usr has no extension.
local FILES   = { { "git.lua", "git" }, { "install_CC_Git.lua", "install_CC_Git" },
                  { "git_complete.lua", "git_complete" } }
local DIR     = "/usr"
local STARTUP = "/startup"
local MARKER  = "-- git.lua path entry (added by install_CC_Git.lua)"
-- bump when the installer itself changes; the version is read back out of a freshly
-- fetched copy with installerVersion() below
local VERSION = "1.3.0"

--------------------------------------------------------------------------------

local function readText(path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local s = h.readAll() or ""
  h.close()
  return s
end

-- fs readAll() drops a trailing newline, so a file written from a download (which
-- fetch() puts back) never compares equal to one read from disk. Compare like-for-like
-- or every run looks like a change and rewrites the same bytes.
local function sameContent(a, b)
  if a == b then return true end
  if a == nil or b == nil then return false end
  return a .. "\n" == b or a == b .. "\n"
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
  -- NOT /disk: a floppy is not the source of truth any more, and an old floppy copy
  -- would silently install over the current repo version. fs.* resolves relative
  -- paths against the computer root, so "/" also covers a copy StartHere just saved.
  dirs[#dirs + 1] = "/"
  for _, d in ipairs(dirs) do
    -- never source from the folder we install into: once `install_CC_Git` lives in
    -- DIR it is on the shell path, so running it from there would find the old
    -- installed copy and install that over itself, forever
    if d ~= DIR then
      for _, name in ipairs(names) do
        local p = join(d, name)
        if fs.exists(p) and not fs.isDir(p) then return p end
      end
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
  if not text then return nil end
  return text:match('git%.VERSION%s*=%s*"([^"]+)"')
end

-- the installer keeps its own version in `local VERSION = "..."`
local function installerVersion(text)
  if not text then return nil end
  return text:match([[local VERSION%s*=%s*"([^"]+)"]])
end

-- the updater has no version of its own, so print "-" rather than a misleading "v?"
local function verCol(text)
  local v = versionOf(text)
  return v and ("v" .. v) or "-"
end

local function ensureDir(d)
  if fs.exists(d) then return fs.isDir(d) end
  -- ComputerCraft 1.75: fs.makeDir returns nothing and raises on failure, so the
  -- only honest check is whether the directory exists afterwards.
  pcall(fs.makeDir, d)
  return fs.isDir(d)
end

-- The hook is MARKER plus the code, so it is easy to detect, idempotent, and
-- removable with `install_CC_Git unhook`. MARKER starts with `--`, so it CANNOT share
-- a line with the code: `-- tag <code>` comments the code out and the hook silently
-- does nothing forever. Marker on its own line, code on the next.
local function hookCode()
  return "if not shell.path():find(" .. string.format("%q", DIR) .. ", 1, true) then" ..
    " shell.setPath(shell.path() .. " .. string.format("%q", ":" .. DIR) .. ") end"
end

-- tab completion has to be registered before you type the command, so the boot hook
-- runs the completer too. It is a 3 KB file; loading git.lua at boot for this would
-- be silly.
local COMPLINE = "if fs.exists(" .. string.format("%q", DIR .. "/git_complete") .. ") then" ..
  " shell.run(" .. string.format("%q", DIR .. "/git_complete") .. ") end"

local function startupLine() return MARKER .. "\n" .. hookCode() .. "\n" .. COMPLINE end

-- /startup can be regenerated by another program (swarm_server does exactly this),
-- in which case our line is overwritten seconds later. Say so, and hand over the
-- line to put in whatever owns the file.
local function startupIsRegenerated(text)
  return text ~= nil and (text:find("while true do", 1, true) ~= nil or
                          text:find("auto-installed", 1, true) ~= nil)
end

local function regenerationWarning()
  printError("note: this " .. STARTUP .. " regenerates itself, so another program owns it")
  printError("and will overwrite our line the next time it runs. Put this line in the")
  printError("text THAT program writes, as its first lines:")
  print("  " .. hookCode())
  print("  " .. COMPLINE)
end

-- Signatures of the multi-line block written by older installers. Those blocks sat
-- at the BOTTOM of /startup, so on a computer with a startup script of its own they
-- never ran - which is why an upgrade has to migrate them, not just notice that a
-- marker is present somewhere. Only lines under a MARKER line are ever dropped, so a
-- path line that someone else generated stays exactly where it is.
local SETPATH = "shell.setPath(shell.path() .. " .. string.format("%q", ":" .. DIR) .. ")"

local function stripHook(text)
  local kept, want = "", 0          -- want: 0 nothing, 1 `if`, 2 `setPath`, 3 `end`
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line:find(MARKER, 1, true) then
      want = 1
    elseif want == 1 and line:find("if not shell.path():find(", 1, true) then
      want = 2
    elseif want == 2 and line:find("git_complete", 1, true) then
      want = 0                     -- our completion line, straight after the hook
    elseif want == 2 and line:find(SETPATH, 1, true) then
      want = 3
    elseif want == 3 and line:match("^%s*end%s*$") then
      want = 0
    else
      want = 0
      kept = kept .. line .. "\n"
    end
  end
  return kept
end

local function blank(t) return t:gsub("%s+", "") == "" end

-- /rom is a read-only JarMount in ComputerCraft 1.75, so /startup in the computer
-- root is the only boot hook there is. Their startup may error out or run forever,
-- so our line goes at the TOP: appended, it would never be reached.
-- the path line, with or without our marker: an unmarked one belongs to whoever
-- generates that startup (swarm_server does) and must not be duplicated or removed
local function hookPresent(text) return text:find(hookCode(), 1, true) ~= nil end

-- an UNMARKED path line is part of whatever generates this file, so it comes back on
-- every regeneration. Ours (marked) does not - the generator would drop it again.
local function foreignHook(text) return hookPresent(text) and not text:find(MARKER, 1, true) end

-- returns message, changed. A no-op says nothing to the user, so `changed` is what
-- decides whether install() prints it and whether a reboot is needed.
local function ensureStartup()
  local cur = readText(STARTUP)
  if cur == nil then
    if not writeText(STARTUP, startupLine() .. "\n") then
      printError("! FAILED writing " .. STARTUP)
      return "", false
    end
    return "set up " .. STARTUP .. " to put git on the path", true
  end
  if hookPresent(cur) and not cur:find(MARKER, 1, true) then
    return "your " .. STARTUP .. " already sets the path - left alone", false
  end
  local want = startupLine() .. "\n" .. stripHook(cur)
  if want:gsub("%s+$", "") == cur:gsub("%s+$", "") then
    return "path entry already at the top of " .. STARTUP, false
  end
  if not writeText(STARTUP, want) then
    printError("! FAILED writing " .. STARTUP)
    return "", false
  end
  if cur:find(MARKER, 1, true) then return "moved the path entry to the top of " .. STARTUP, true end
  return "added the path entry to the top of " .. STARTUP, true
end

-- drop only the lines we added; everything else in their startup stays put
local function removeStartup()
  local cur = readText(STARTUP)
  if cur == nil then return "no " .. STARTUP .. " to change" end
  -- marker only: a path line someone else generated is theirs to keep
  if not cur:find(MARKER, 1, true) then return "no path entry in " .. STARTUP end
  local kept = stripHook(cur)
  if blank(kept) then
    -- nothing of theirs was in there, so take the file away too
    local ok = pcall(fs.delete, STARTUP)
    return ok and "removed the path entry and " .. STARTUP or "removed the path entry from " .. STARTUP
  end
  if not writeText(STARTUP, kept) then return "FAILED writing " .. STARTUP end
  return "removed the path entry from " .. STARTUP
end

-- install, refresh or leave alone. Silent: the caller decides what to print.
-- Returns ok, note, version, oldVersion, err  (note: new / updated / current / kept / failed)
--
-- The source rule, in words: if the program is already installed, the repository is
-- the source of truth and we download. If it is NOT installed yet, a copy sitting
-- next to this script is the offline cold start (floppy, or a folder you cloned).
-- `update` skips local copies entirely and always downloads.
local function one(item, preferNet)
  local name, target = item[1], item[2] or item[1]
  local dest = join(DIR, target)
  local existing = nil
  if fs.exists(dest) and not fs.isDir(dest) then existing = readText(dest) end
  local oldVer = versionOf(existing)

  local text, source, err
  if not existing and not preferNet then
    local p = localCopy({ name, target })
    if p then text, source = readText(p), p end
  end

  if not text then
    local body
    body, err = fetch(RAW .. name)
    if body then
      text, source = body, RAW .. name
    elseif not existing then
      -- cold start with no network: fall back to whatever is sitting next to us
      local p = localCopy({ name, target })
      if p then text, source = readText(p), p end
    end
  end

  if not text then
    if existing then return true, "kept", oldVer, oldVer, err end
    return false, "failed", nil, oldVer, err
  end

  if #text < 200 then
    err = "only " .. #text .. " bytes - that does not look like the program"
    if existing then return true, "kept", oldVer, oldVer, err end
    return false, "failed", nil, oldVer, err
  end

  if sameContent(existing, text) then return true, "current", versionOf(text), oldVer end

  if not writeText(dest, text) then
    return false, "failed", nil, oldVer, "cannot write " .. dest .. " (disk full?)"
  end
  return true, existing and "updated" or "new", versionOf(text), oldVer
end

-- The copy running here only knows the files IT shipped with. Rather than telling the
-- user to run the installer twice, read the file list out of the copy we just pulled.
local function fileListOf(text)
  -- the closing brace has to be the one that ends the statement (followed by a
  -- newline), otherwise the first inner `}` of `{ "git.lua", "git" }` stops the match
  local block = text and text:match("local FILES%s*=%s*{([%s%S]-)}%s*\n")
  if not block then return nil end
  local list = {}
  for a, b in block:gmatch('"([^"]+)"%s*,%s*"([^"]+)"') do list[#list + 1] = { a, b } end
  if #list == 0 then return nil end
  return list
end

local function verPair(oldV, newV)
  local a, b = oldV or "?", newV or "?"
  if a == b then return b end
  return a .. " -> " .. b
end

local function status()
  print("programs in " .. DIR .. ":")
  local found = false
  for _, item in ipairs(FILES) do
    local target = item[2] or item[1]
    local p = join(DIR, target)
    if fs.exists(p) and not fs.isDir(p) then
      found = true
      print(string.format("  %-16s %6d bytes  version %s", target, fs.getSize(p),
        versionOf(readText(p)) or "n/a"))
    else
      print("  " .. target .. ": not installed")
    end
  end
  local startup = readText(STARTUP)
  if startup == nil then
    print(STARTUP .. ": no startup script at all - git will not be on the path after a reboot")
  else
    local lines, n = {}, 0
    for line in (startup .. "\n"):gmatch("([^\n]*)\n") do
      n = n + 1 lines[n] = line
    end
    local at = nil
    for i = 1, n do
      if lines[i]:find(MARKER, 1, true) or lines[i]:find(hookCode(), 1, true) then
        at = i break
      end
    end
    if at == nil then
      print(STARTUP .. ": no path entry - run install_CC_Git")
    elseif lines[at]:find(MARKER, 1, true) and lines[at]:find(hookCode(), 1, true) then
      -- marker and code on one line: the marker comments the code out, so the entry
      -- looks perfect and does nothing at all
      print(STARTUP .. ": path entry is line " .. at .. " but COMMENTED OUT - run install_CC_Git")
    else
      -- comments and blank lines above it cannot stop it running
      local blocked = false
      for i = 1, at - 1 do
        if not (lines[i]:match("^%s*$") or lines[i]:match("^%s*%-%-")) then blocked = true end
      end
      if blocked then
        print(STARTUP .. ": path entry is on line " .. at .. ", below other code - it may not be reached")
      else
        print(STARTUP .. ": path entry is line " .. at .. ", where it belongs")
      end
    end
  end
  -- tab completion: registered at boot only if the startup hook runs the completer
  if fs.exists(join(DIR, "git_complete")) and not fs.isDir(join(DIR, "git_complete")) then
    if startup and startup:find("git_complete", 1, true) then
      print("tab completion: registered at boot from " .. STARTUP)
    else
      print("tab completion: not run at boot; `git` registers it when it runs")
    end
  end
  -- warn even when the entry is present: a regenerated startup file gets rewritten,
  -- so a hook that looks fine now is gone the next time that program runs
  if startupIsRegenerated(startup) and not foreignHook(startup) then regenerationWarning() end
  print("shell path now: " .. tostring(shell.path()))
  return found
end

local function main(args)
  -- `--reran` marks the second copy: it must not re-exec again, or a repo that keeps
  -- changing under us could loop. Anything else that is not a flag is the action.
  local action, reran = nil, false
  for _, a in ipairs(args or {}) do
    if a == "--reran" then reran = true
    elseif action == nil and type(a) == "string" and a:sub(1, 2) ~= "--" then action = a end
  end
  if action == "status" then
    status()
    return true
  end
  if action == "hook" then
    print("add these lines wherever your " .. STARTUP .. " comes from, as its first lines:")
    print("  " .. hookCode())
    print("  " .. COMPLINE)
    return true
  end
  if action == "unhook" then
    print(removeStartup())
    print("the programs stay in " .. DIR .. " - call them as " .. DIR .. "/git if you unhook")
    return true
  end
  if action ~= "update" and action ~= nil and action ~= "install" then
    print("usage: install_CC_Git [update|status|hook|unhook]")
    return false
  end

  -- Both forms do the same thing: pull ourselves first, then install or refresh every
  -- program. `update` differs only in ignoring a copy sitting next to the script.
  local preferNet = (action == "update")
  if not ensureDir(DIR) then
    printError("cannot create " .. DIR)
    return false
  end

  -- 1. ourselves. Doing this first means one run is enough even when the new release
  --    added files this copy has never heard of.
  local installedSelf = readText(join(DIR, "install_CC_Git"))
  local selfText = nil
  if installedSelf == nil and not preferNet then
    -- cold start: a copy beside the script is enough to bootstrap from
    local p = localCopy({ "install_CC_Git.lua", "install_CC_Git" })
    if p then selfText = readText(p) end
  end
  if not selfText then selfText = fetch(RAW .. "install_CC_Git.lua") end
  if not selfText and installedSelf == nil then
    local p = localCopy({ "install_CC_Git.lua", "install_CC_Git" })
    if p then selfText = readText(p) end
  end

  local list = FILES
  local failed = false
  if selfText and #selfText >= 200 then
    list = fileListOf(selfText) or FILES
    if not sameContent(installedSelf, selfText) then
      if writeText(join(DIR, "install_CC_Git"), selfText) then
        if installedSelf == nil then
          print("install_CC_Git " .. (installerVersion(selfText) or "?") .. " installed")
        else
          print(string.format("install_CC_Git %s",
            verPair(installerVersion(installedSelf), installerVersion(selfText))))
          -- We just replaced ourselves, so the code still running is the OLD copy and
          -- cannot know about behaviour changes. Run the new copy instead of asking the
          -- user to type the same command twice. rom/programs/shell uses os.run's
          -- return value, so shell.run waits for the program to finish; --reran stops
          -- the child from doing this again.
          if not reran then
            local ok = false
            if shell and shell.run then
              ok = pcall(shell.run, join(DIR, "install_CC_Git"), "--reran")
            end
            if ok then return true end
            printError("! could not run the new copy - finishing with the old one")
          end
        end
      else
        printError("! install_CC_Git: cannot write " .. DIR .. " (disk full?)")
        failed = true
      end
    end
  elseif installedSelf == nil then
    printError("! install_CC_Git: cannot reach GitHub and there is no local copy to install from")
    return false
  end

  -- 2. the programs
  local changed, gitVer = 0, nil
  for _, item in ipairs(list) do
    local target = item[2] or item[1]
    if target ~= "install_CC_Git" then
      local ok, note, ver, oldVer, err = one(item, preferNet)
      if note == "new" then
        print(string.format("%s %s installed", target, ver or ""))
        changed = changed + 1
      elseif note == "updated" then
        print(string.format("%s %s", target, verPair(oldVer, ver)))
        changed = changed + 1
      elseif note == "kept" then
        printError(string.format("! %s: %s - keeping %s", target, tostring(err), ver or "the installed copy"))
        failed = true
      elseif note == "failed" then
        printError(string.format("! %s: %s", target, tostring(err)))
        failed = true
      end
      if target == "git" then gitVer = ver or gitVer end
    end
  end

  -- 3. the boot hook, but only say something when it actually changed
  local before = readText(STARTUP)
  local startupNote, startupChanged = ensureStartup()
  if startupChanged then
    print(startupNote)
    changed = changed + 1
  end
  if startupIsRegenerated(before) and not foreignHook(before) then regenerationWarning() end

  if changed > 0 then
    print("reboot to put git on the path, then from any folder: git help")
  elseif gitVer and not failed then
    print("git " .. gitVer .. " - up to date")
  end

  if failed then
    printError("done with errors - `install_CC_Git status` has the detail")
    return false
  end
  return true
end

return main({ ... })
