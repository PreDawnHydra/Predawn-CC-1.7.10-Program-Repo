-- git_complete.lua - tab completion for `git` (ComputerCraft 1.75)
--
-- Run this file once per shell session and `git <TAB>` completes. The installer's
-- /startup hook runs it at boot; `git` also runs it when it starts, so completion
-- still arrives on a computer whose startup file belongs to another program.
--
-- How the shell asks for completion (rom/programs/shell): it keeps a table keyed by
-- the RESOLVED program path, so the completer has to be registered under the path
-- `git` resolves to - /usr/git normally. It is called as
--     fn(shell, argIndex, partialWord, previousWords)
-- and returns the *remainder* of each completion, which the shell appends to what
-- you have typed. A trailing space means "this one is complete".
--
-- fs.complete() is documented in rom/help/fs and used all over rom/startup, but this
-- ComputerCraft 1.75 jar never registers it - FSAPI has no "complete" method - so the
-- ROM's own file completion is broken on this build. We list and match by hand.

local COMMANDS = {
  "auth", "branch", "clone", "fetch", "help", "ls",
  "pull", "push", "status", "token", "version", "whoami",
}

local FLAGS = {
  "--all", "--ext=", "--force", "--keep-path", "--max=",
  "--new", "--path=", "--prune",
}

local function filter(list, prefix, spaceWhenDone)
  local out = {}
  for i = 1, #list do
    local s = list[i]
    if s:sub(1, #prefix) == prefix then
      local suffix = s:sub(#prefix + 1)
      -- a trailing space means "that one is complete", same as the ROM completers
      if spaceWhenDone and spaceWhenDone(s) then suffix = suffix .. " " end
      out[#out + 1] = suffix
    end
  end
  return out
end

-- --force is finished; --path= is not, it wants a value
local function flagDone(s) return s:sub(-1) ~= "=" end

-- files and folders under wherever the argument points, as suffixes to append
local function completePath(sh, text)
  local slash
  for j = #text, 1, -1 do
    if text:sub(j, j) == "/" then slash = j break end
  end
  local dirPart, leaf
  if slash then dirPart, leaf = text:sub(1, slash - 1), text:sub(slash + 1)
  else dirPart, leaf = "", text end

  local base
  if dirPart == "" then
    base = sh.dir()
  elseif sh.resolve then
    base = sh.resolve(dirPart)
  else
    base = dirPart
  end

  local names = fs.list(base)
  if not names then return {} end

  local out = {}
  for i = 1, #names do
    local n = names[i]
    if n ~= "." and n ~= ".." and n:sub(1, #leaf) == leaf then
      local suffix = n:sub(#leaf + 1)
      if fs.isDir(base .. "/" .. n) then
        suffix = suffix .. "/"
      else
        suffix = suffix .. " "
      end
      out[#out + 1] = suffix
    end
  end
  return out
end

local function completeGit(sh, argIndex, text, previous)
  text = text or ""
  if argIndex == 1 then return filter(COMMANDS, text) end
  if text:sub(1, 1) == "-" then return filter(FLAGS, text, flagDone) end
  -- `git clone owner/repo` and `git auth owner/repo`: complete the local path only
  -- once a slash is in the word, so typing a repo name is never interrupted
  return completePath(sh, text)
end

local function register()
  if not shell or not shell.setCompletionFunction then return false end
  -- The shell looks the completer up by the RESOLVED program path, and fs.combine()
  -- sanitises paths by splitting on "/" and dropping empty parts - so a resolved path
  -- NEVER has a leading slash. resolveProgram("git") answers "usr/git", which is why
  -- rom/startup registers "rom/programs/alias" and not "/rom/programs/alias".
  -- Registering "/usr/git" here would simply never match, in total silence.
  local keys = { "usr/git", "/usr/git" }
  local resolved = shell.resolveProgram and shell.resolveProgram("git")
  if resolved then keys[#keys + 1] = resolved end
  for i = 1, #keys do shell.setCompletionFunction(keys[i], completeGit) end
  return true
end

register()
