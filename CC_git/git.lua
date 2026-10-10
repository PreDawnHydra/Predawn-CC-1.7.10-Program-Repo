--[[
git.lua - GitHub client for ComputerCraft 1.75 (Minecraft 1.7.10)

Clone / pull / push a GitHub repository as plain files. This does NOT speak the
git wire protocol (ComputerCraft 1.75 has no sockets and no websockets); it uses
the GitHub REST API for metadata and raw.githubusercontent.com for file bodies.

Usage:
  git clone <owner>/<repo> [branch] [dest] [flags]
  git pull  [dest] [flags]
  git push  [dest] [message] [flags]
  git status [dest]
  git ls [dest]
  git branch [dest]
  git token [<pat>]            store / show a Personal Access Token
  git help

Flags:
  --path=PREFIX   only touch files under this path in the repo
  --ext=a,b       only touch files with these extensions
  --prune         delete local files that were removed upstream
  --max=BYTES     abort a clone/pull that would download more than BYTES
  --token=TOKEN   use this GitHub token for this command only
  --force         pull: re-download everything
  --all           push: upload every local file, not just tracked/dirty ones

Version notes (verified against ComputerCraft1.75.jar):
  * http only supports GET and POST (no PATCH/PUT/DELETE) -> push creates a
    commit + branch and merges it server-side via POST /merges.
  * http handles expose readLine/readAll/close/getResponseCode only.
    readAll() strips the trailing newline and normalises CRLF -> LF.
  * Non-2xx responses give a nil handle, so error bodies cannot be read.
  * Computer space is capped by ComputerCraft.cfg computerSpaceLimit.
--]]

local git = {}

git.VERSION = "1.0.0"
git.API = "https://api.github.com"
git.RAW = "https://raw.githubusercontent.com"
git.USER_AGENT = "ComputerCraft-git.lua/" .. git.VERSION

--------------------------------------------------------------------------------
-- small utilities
--------------------------------------------------------------------------------

local function pjoin(a, b)
  if a == "" then return b end
  if string.sub(a, -1) == "/" then return a .. b end
  return a .. "/" .. b
end

-- CC 1.75 quirks here:
--   * os.getenv does NOT exist (no $HOME).
--   * fs.getDir EXISTS but requires a path argument - calling fs.getDir() with
--     no argument throws "Expected string".
--   * the shell API is shell.dir()/setDir()/resolve()/path() (NOT the modern
--     shell.getWorkingDir()).
--   * fs.* resolves relative paths against the computer root, NOT the shell's
--     current directory, so CLI path arguments must go through shell.resolve().
local function cwd()
  if shell and shell.dir then
    local ok, d = pcall(shell.dir)
    if ok and type(d) == "string" and d ~= "" then return d end
  end
  return "."
end

-- make a user-supplied path follow the shell's working directory
local function resolvePath(p)
  if p == nil then return nil end
  if shell and shell.resolve then
    local ok, r = pcall(shell.resolve, p)
    if ok and type(r) == "string" and r ~= "" then return r end
  end
  return p
end

local function parentOf(dir)
  if dir == "/" or dir == "." then return nil end
  local parent = string.match(dir, "^(.*)/[^/]+$")
  if parent == nil or parent == "" then return "/" end
  return parent
end

local function printf(fmt, ...) print(string.format(fmt, ...)) end
local function warn(...) printError(...) end

local function startsWith(s, prefix)
  return string.sub(s, 1, #prefix) == prefix
end

local function endsWith(s, suffix)
  return #suffix == 0 or string.sub(s, -#suffix) == suffix
end

local function sortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- percent-encode a repo path for raw.githubusercontent.com
local function urlEncodePath(p)
  local out = {}
  for i = 1, #p do
    local c = p:sub(i, i)
    local b = string.byte(c)
    if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
       or c == "/" or c == "-" or c == "_" or c == "." or c == "~" then
      out[#out + 1] = c
    else
      out[#out + 1] = string.format("%%%02X", b)
    end
  end
  return table.concat(out)
end
git.urlEncodePath = urlEncodePath

--------------------------------------------------------------------------------
-- base64 (encode for push, decode for API blobs)
--------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function git.b64encode(s)
  local out, n = {}, #s
  for i = 1, n, 3 do
    local a = string.byte(s, i)
    local b = string.byte(s, i + 1)
    local c = string.byte(s, i + 2)
    local x = a * 65536 + (b or 0) * 256 + (c or 0)
    local e = {
      B64:sub(math.floor(x / 262144) % 64 + 1, math.floor(x / 262144) % 64 + 1),
      B64:sub(math.floor(x / 4096) % 64 + 1, math.floor(x / 4096) % 64 + 1),
      B64:sub(math.floor(x / 64) % 64 + 1, math.floor(x / 64) % 64 + 1),
      B64:sub(x % 64 + 1, x % 64 + 1),
    }
    if c == nil then e[4] = "=" ; if b == nil then e[3] = "=" end end
    out[#out + 1] = table.concat(e)
  end
  return table.concat(out)
end

function git.b64decode(s)
  s = s:gsub("[^" .. B64 .. "=]", "")
  local rev = {}
  for i = 1, 64 do rev[B64:sub(i, i)] = i - 1 end
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == "=" then break end
    local v = rev[ch]
    if v then
      acc = acc * 64 + v
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        out[#out + 1] = string.char(math.floor(acc / 2 ^ bits) % 256)
        acc = acc % 2 ^ bits
      end
    end
  end
  return table.concat(out)
end

--------------------------------------------------------------------------------
-- JSON
--------------------------------------------------------------------------------

local json = {}
git.json = json

local function utf8Encode(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000),
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
  else
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + math.floor(cp / 0x1000) % 0x40,
                       0x80 + math.floor(cp / 0x40) % 0x40,
                       0x80 + cp % 0x40)
  end
end

local parseValue

local function skipWs(s, i)
  while true do
    local c = string.byte(s, i)
    if c == 32 or c == 9 or c == 10 or c == 13 then i = i + 1 else return i end
  end
end

-- All parsers return (value, nextIndex) on success and (nil, nil, err) on
-- failure. JSON null is a legitimate nil value with no error, so callers must
-- test the error slot, never the value slot.
local function parseString(s, i)
  local out = {}
  i = i + 1
  while true do
    local c = string.byte(s, i)
    if c == nil then return nil, nil, "unterminated string at " .. i end
    if c == 34 then return table.concat(out), i + 1 end
    if c == 92 then
      local e = string.byte(s, i + 1)
      if e == 34 then out[#out + 1] = '"'; i = i + 2
      elseif e == 92 then out[#out + 1] = "\\"; i = i + 2
      elseif e == 47 then out[#out + 1] = "/"; i = i + 2
      elseif e == 98 then out[#out + 1] = "\b"; i = i + 2
      elseif e == 102 then out[#out + 1] = "\f"; i = i + 2
      elseif e == 110 then out[#out + 1] = "\n"; i = i + 2
      elseif e == 114 then out[#out + 1] = "\r"; i = i + 2
      elseif e == 116 then out[#out + 1] = "\t"; i = i + 2
      elseif e == 117 then
        local cp = tonumber(string.sub(s, i + 2, i + 5), 16)
        if not cp then return nil, nil, "bad \\u escape at " .. i end
        i = i + 6
        if cp >= 0xD800 and cp <= 0xDBFF and string.byte(s, i) == 92
           and string.byte(s, i + 1) == 117 then
          local lo = tonumber(string.sub(s, i + 2, i + 5), 16)
          if lo and lo >= 0xDC00 and lo <= 0xDFFF then
            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
            i = i + 6
          end
        end
        out[#out + 1] = utf8Encode(cp)
      else
        return nil, nil, "bad escape at " .. i
      end
    else
      out[#out + 1] = string.char(c)
      i = i + 1
    end
  end
end

local function parseNumber(s, i)
  local num = string.match(s, "^[-+]?%d+%.?%d*[eE]?[-+]?%d*", i)
  if not num then return nil, nil, "bad number at " .. i end
  return tonumber(num), i + #num
end

local function parseArray(s, i)
  local arr = {}
  i = skipWs(s, i + 1)
  if string.byte(s, i) == 93 then return arr, i + 1 end
  while true do
    local v, pos, err = parseValue(s, i)
    if err then return nil, nil, err end
    arr[#arr + 1] = v
    i = skipWs(s, pos)
    local c = string.byte(s, i)
    if c == 44 then i = skipWs(s, i + 1)
    elseif c == 93 then return arr, i + 1
    else return nil, nil, "expected , or ] at " .. i end
  end
end

local function parseObject(s, i)
  local obj = {}
  i = skipWs(s, i + 1)
  if string.byte(s, i) == 125 then return obj, i + 1 end
  while true do
    if string.byte(s, i) ~= 34 then return nil, nil, "expected string key at " .. i end
    local key, pos, kerr = parseString(s, i)
    if kerr then return nil, nil, kerr end
    i = skipWs(s, pos)
    if string.byte(s, i) ~= 58 then return nil, nil, "expected : at " .. i end
    local v, vpos, verr = parseValue(s, skipWs(s, i + 1))
    if verr then return nil, nil, verr end
    obj[key] = v
    i = skipWs(s, vpos)
    local c = string.byte(s, i)
    if c == 44 then i = skipWs(s, i + 1)
    elseif c == 125 then return obj, i + 1
    else return nil, nil, "expected , or } at " .. i end
  end
end

parseValue = function(s, i)
  i = skipWs(s, i)
  local c = string.byte(s, i)
  if c == nil then return nil, nil, "empty document" end
  if c == 34 then return parseString(s, i) end
  if c == 123 then return parseObject(s, i) end
  if c == 91 then return parseArray(s, i) end
  if c == 116 then
    if string.sub(s, i, i + 3) == "true" then return true, i + 4 end
    return nil, nil, "bad literal at " .. i
  end
  if c == 102 then
    if string.sub(s, i, i + 4) == "false" then return false, i + 5 end
    return nil, nil, "bad literal at " .. i
  end
  if c == 110 then
    if string.sub(s, i, i + 3) == "null" then return nil, i + 4 end
    return nil, nil, "bad literal at " .. i
  end
  if c == 45 or c == 43 or (c >= 48 and c <= 57) then return parseNumber(s, i) end
  return nil, nil, "unexpected byte " .. tostring(c) .. " at " .. i
end

function json.decode(s)
  if type(s) ~= "string" then return nil, "not a string" end
  local v, _, err = parseValue(s, 1)
  if err then return nil, err end
  return v
end

local function escString(s)
  local out = { '"' }
  for i = 1, #s do
    local c = s:sub(i, i)
    local b = string.byte(c)
    if c == '"' then out[#out + 1] = '\\"'
    elseif c == "\\" then out[#out + 1] = "\\\\"
    elseif b == 8 then out[#out + 1] = "\\b"
    elseif b == 9 then out[#out + 1] = "\\t"
    elseif b == 10 then out[#out + 1] = "\\n"
    elseif b == 12 then out[#out + 1] = "\\f"
    elseif b == 13 then out[#out + 1] = "\\r"
    elseif b < 32 then out[#out + 1] = string.format("\\u%04x", b)
    else out[#out + 1] = c end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local function encode(v)
  local t = type(v)
  if v == nil then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v == math.floor(v) and math.abs(v) < 2^31 then return string.format("%d", v) end
    return tostring(v)
  end
  if t == "string" then return escString(v) end
  if t == "table" then
    local n = #v
    if n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = encode(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    elseif next(v) == nil then
      return "{}"
    else
      local parts, keys = {}, sortedKeys(v)
      for _, k in ipairs(keys) do
        parts[#parts + 1] = escString(tostring(k)) .. ":" .. encode(v[k])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  error("cannot encode " .. t)
end

function json.encode(v) return encode(v) end

--------------------------------------------------------------------------------
-- HTTP layer (CC 1.75: GET/POST only, text bodies only)
--------------------------------------------------------------------------------

git.authStyle = "bearer"   -- "bearer" or "token"; GitHub accepts both for PATs

local function authHeader()
  if not git.token or git.token == "" then return nil end
  if git.authStyle == "token" then return "token " .. git.token end
  return "Bearer " .. git.token
end

local function headers(extra)
  local h = {
    ["User-Agent"] = git.USER_AGENT,
    ["Accept"] = "application/vnd.github+json",
  }
  local a = authHeader()
  if a then h["Authorization"] = a end
  if extra then
    for k, v in pairs(extra) do h[k] = v end
  end
  return h
end

-- GitHub documents both "Bearer" and "token" prefixes. If one is refused, retry
-- once with the other and remember which form worked for this session, because
-- CC cannot read the response body of a failed request.
local function retryOtherAuthStyle(what, url, body, hdrExtra)
  if not git.token or git.token == "" then return nil end
  local other = (git.authStyle == "bearer") and "token" or "bearer"
  if other == "token" then
    print("  (retrying with 'Authorization: token' header form)")
  else
    print("  (retrying with 'Authorization: Bearer' header form)")
  end
  git.authStyle = other
  local res
  if what == "post" then res = http.post(url, body, headers(hdrExtra))
  else res = http.get(url, headers(hdrExtra)) end
  if res then
    print("  header form '" .. other .. "' worked - using it for this session")
  else
    git.authStyle = (other == "token") and "bearer" or "token"
  end
  return res
end

-- returns ok(true/false), info (body string, or error string)
function git.httpGet(url)
  local res = http.get(url, headers())
  if not res then res = retryOtherAuthStyle("get", url, nil, nil) end
  if not res then
    return false, "request failed (network, blocked host, bad/expired token, or HTTP 4xx/5xx): " .. url
  end
  local code = res.getResponseCode and res.getResponseCode() or 0
  local body = res.readAll() or ""
  res.close()
  if code and code >= 400 then
    return false, "HTTP " .. code .. " for " .. url
  end
  return true, body
end

function git.httpPost(url, payload)
  local body = json.encode(payload)
  local extra = {["Content-Type"] = "application/json"}
  local res = http.post(url, body, headers(extra))
  if not res then res = retryOtherAuthStyle("post", url, body, extra) end
  if not res then
    return false, "POST failed (network, blocked host, bad/expired token, missing Contents:write permission, or HTTP 4xx/5xx): " .. url
  end
  local code = res.getResponseCode and res.getResponseCode() or 0
  local text = res.readAll() or ""
  res.close()
  if code and code >= 400 then
    return false, "HTTP " .. code .. " for " .. url
  end
  return true, text
end

function git.apiGet(path)
  local ok, body = git.httpGet(git.API .. path)
  if not ok then return nil, body end
  local data, err = json.decode(body)
  if data == nil and err then return nil, "bad JSON from API: " .. err end
  return data
end

function git.apiPost(path, payload)
  local ok, body = git.httpPost(git.API .. path, payload)
  if not ok then return nil, body end
  if body == "" then return {} end
  local data, err = json.decode(body)
  if data == nil and err then return nil, "bad JSON from API: " .. err end
  return data
end

function git.rawGet(owner, repo, ref, path)
  local url = table.concat({ git.RAW, owner, repo, ref, urlEncodePath(path) }, "/")
  return git.httpGet(url)
end

--------------------------------------------------------------------------------
-- filesystem helpers (CC fs API)
--------------------------------------------------------------------------------

local function exists(p) return fs.exists(p) end

function git.mkdirs(path)
  if path == "" or fs.isDir(path) then return end
  -- keep a leading "/" so absolute destinations work
  local acc = (string.sub(path, 1, 1) == "/") and "/" or nil
  for part in string.gmatch(path, "[^/]+") do
    if acc == nil then acc = part
    elseif acc == "/" then acc = "/" .. part
    else acc = acc .. "/" .. part end
    -- "." and ".." segments (and the root itself) are never files to replace:
    -- fs.delete(".") would take the whole directory with it.
    if part ~= "." and part ~= ".." and acc ~= "/" then
      if fs.exists(acc) and not fs.isDir(acc) then
        -- a local file sits where the repository has a directory (a rename done on
        -- GitHub, for instance). Nothing can be written under it, so replace it.
        warn("replacing local file " .. acc .. " with a directory")
        fs.delete(acc)
      end
      if not fs.exists(acc) then fs.makeDir(acc) end
    end
  end
end

function git.readFile(path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local s = h.readAll() or ""
  h.close()
  return s
end

function git.writeFile(path, data)
  local dir = string.match(path, "^(.*)/[^/]+$")
  if dir then git.mkdirs(dir) end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(data)
  h.close()
  return true
end

function git.walk(dir, prefix, out)
  out = out or {}
  prefix = prefix or ""
  for _, name in ipairs(fs.list(dir) or {}) do
    local rel = prefix == "" and name or pjoin(prefix, name)
    local abs = pjoin(dir, name)
    if fs.isDir(abs) then
      if name ~= ".git" then git.walk(abs, rel, out) end
    else
      if name ~= git.CFG and name ~= git.TOKEN then
        out[rel] = fs.getSize and fs.getSize(abs) or #git.readFile(abs)
      end
    end
  end
  return out
end

-- Cheap content fingerprint. CC 1.75 has no sha library, and FNV-style 32-bit
-- multiplies lose precision in Lua 5.1 doubles, so keep the accumulator under
-- 2^31: h*31 + byte < 2^36 is still exact in a double.
function git.checksum(s)
  local h = 2166136261 % 2147483647
  for i = 1, #s do
    h = (h * 31 + string.byte(s, i)) % 2147483647
  end
  return h
end

-- Fingerprint the way fs/http hand it to us: readAll() has no trailing newline,
-- so strip it before hashing and sizes stay comparable across clone/pull/push.
function git.fingerprint(content)
  if content:sub(-1) == "\n" then content = content:sub(1, -2) end
  return #content, git.checksum(content)
end

-- true when the local file no longer matches the manifest entry
function git.isDirty(absPath, meta)
  local content = git.readFile(absPath)
  if content == nil then return true end
  if meta.fsum == nil then
    local sz = #content
    return sz ~= meta.size and sz ~= (meta.size or 0) - 1
  end
  local fsize, fsum = git.fingerprint(content)
  return fsize ~= meta.fsize or fsum ~= meta.fsum
end

--------------------------------------------------------------------------------
-- clone config file (.gitcfg)
--------------------------------------------------------------------------------

git.CFG = ".gitcfg"
-- never uploaded by push, at any depth: uploading this would publish the token
git.TOKEN = ".git-token"

function git.cfgPath(dir) return pjoin(dir, git.CFG) end

-- friendlier "not a clone" message: show what is actually there, because a
-- failed/aborted clone and a wrong directory look identical otherwise.
function git.missingCfgMsg(dest)
  local what
  if not fs.exists(dest) then
    what = "directory does not exist"
  else
    local names = fs.list(dest) or {}
    if #names == 0 then
      what = "directory is empty"
    else
      local show = {}
      for i = 1, math.min(#names, 8) do show[i] = names[i] end
      what = "contains: " .. table.concat(show, ", ")
      if #names > 8 then what = what .. ", (" .. (#names - 8) .. " more)" end
    end
  end
  return "no " .. git.CFG .. " in " .. dest .. " (" .. what .. ") - run git clone first"
end

function git.loadCfg(dir)
  local s = git.readFile(git.cfgPath(dir))
  if not s then return nil end
  local ok = textutils.unserialize(s)
  if type(ok) ~= "table" then return nil end
  return ok
end

function git.saveCfg(dir, cfg)
  git.writeFile(git.cfgPath(dir), textutils.serialize(cfg))
end

--------------------------------------------------------------------------------
-- repo parsing
--------------------------------------------------------------------------------

function git.parseRepo(s)
  if not s then return nil, "no repository given" end
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("^git@github.com:", "")
  s = s:gsub("^https?://github%.com/", "")
  s = s:gsub("^https?://www%.github%.com/", "")
  s = s:gsub("%.git/?$", "")
  s = s:gsub("/+$", "")
  local owner, repo = string.match(s, "^([^/%s]+)/([^/%s]+)$")
  if not owner then return nil, "could not parse repository: " .. s end
  return { owner = owner, repo = repo }
end

--------------------------------------------------------------------------------
-- filters
--------------------------------------------------------------------------------

function git.makeFilter(opts)
  local exts
  if opts.ext then
    exts = {}
    for e in string.gmatch(opts.ext, "[^,]+") do exts[e:lower()] = true end
  end
  return function(path)
    if opts.path and not startsWith(path, opts.path) then return false end
    if exts then
      local ext = string.match(path, "%.([^/]+)$")
      if not ext or not exts[ext:lower()] then return false end
    end
    return true
  end
end

--------------------------------------------------------------------------------
-- remote queries
--------------------------------------------------------------------------------

function git.resolveCommit(owner, repo, branch)
  local ref, err = git.apiGet("/repos/" .. owner .. "/" .. repo ..
                              "/git/ref/heads/" .. branch)
  if ref and ref.object and ref.object.sha then return ref.object.sha end
  -- branch may not exist, or default branch differs: ask the repo
  local repoInfo = git.apiGet("/repos/" .. owner .. "/" .. repo)
  if repoInfo and repoInfo.default_branch then
    if repoInfo.default_branch ~= branch then
      local r2 = git.apiGet("/repos/" .. owner .. "/" .. repo ..
                            "/git/ref/heads/" .. repoInfo.default_branch)
      if r2 and r2.object and r2.object.sha then
        return r2.object.sha, repoInfo.default_branch
      end
    end
    return nil, "branch '" .. branch .. "' not found (default is " ..
                repoInfo.default_branch .. ")"
  end
  return nil, err or "repository not found: " .. owner .. "/" .. repo
end

function git.fetchTree(owner, repo, sha)
  local data, err = git.apiGet("/repos/" .. owner .. "/" .. repo ..
                               "/git/trees/" .. sha .. "?recursive=1")
  if not data then return nil, err end
  if not data.tree then return nil, "no tree in response" end
  return data
end

--------------------------------------------------------------------------------
-- download one blob and write it locally
--------------------------------------------------------------------------------

local function downloadFile(owner, repo, ref, entry, destDir)
  local ok, body = git.rawGet(owner, repo, ref, entry.path)
  if not ok then return false, body end
  local fsize, fsum = git.fingerprint(body)
  -- readAll() drops the final newline; the tree API tells us the true size
  if entry.size and #body + 1 == entry.size then body = body .. "\n" end
  if not git.writeFile(pjoin(destDir, entry.path), body) then
    return false, "could not write " .. entry.path
  end
  return true, #body, fsize, fsum
end

--------------------------------------------------------------------------------
-- commands
--------------------------------------------------------------------------------

-- returns available bytes, or nil if the API is unavailable
local function freeSpace(dir)
  if not fs.getFreeSpace then return nil end
  local ok, space = pcall(fs.getFreeSpace, dir)
  if ok and type(space) == "number" then return space end
  return nil
end

function git.cmdClone(args)
  local repo, err = git.parseRepo(args[1])
  if not repo then return false, err end
  local branch = args[2]
  if branch and (branch:sub(1, 2) == "--" or branch == "") then branch = nil end
  local dest = args[3]
  if dest and (dest:sub(1, 2) == "--" or dest == "") then dest = nil end
  local opts = git.parseFlags(args, 1)
  branch = branch or opts.branch or "main"
  dest = resolvePath(dest or repo.repo)

  if exists(git.cfgPath(dest)) then
    return false, dest .. " already looks like a clone (has " .. git.CFG .. ")"
  end

  print("resolving " .. repo.owner .. "/" .. repo.repo .. " (" .. branch .. ")")
  local sha, resolved = git.resolveCommit(repo.owner, repo.repo, branch)
  if not sha then return false, resolved end
  if resolved and resolved ~= branch then
    print("branch '" .. branch .. "' not found, using " .. resolved)
    branch = resolved
  end

  print("reading tree " .. sha:sub(1, 8))
  local treeData, terr = git.fetchTree(repo.owner, repo.repo, sha)
  if not treeData then return false, terr end
  if treeData.truncated then
    return false, "repository tree is too large to list; use --path=DIR to clone a subdirectory"
  end

  local keep = git.makeFilter(opts)
  local files, total = {}, 0
  for _, e in ipairs(treeData.tree) do
    if e.type == "blob" and keep(e.path) then
      files[#files + 1] = e
      total = total + (e.size or 0)
    end
  end
  if #files == 0 then return false, "no files matched the filter" end

  if opts.max and total > tonumber(opts.max) then
    return false, string.format("clone would download %d bytes (limit %d)", total, tonumber(opts.max))
  end
  local space = freeSpace(dest)
  if space and total > space - 4096 then
    return false, string.format("not enough disk space: need %d bytes, %d free (see computerSpaceLimit in ComputerCraft.cfg)", total, space)
  end
  print(string.format("cloning %d files, %d bytes", #files, total))

  git.mkdirs(dest)
  local manifest, failed = {}, 0
  for i, e in ipairs(files) do
    local ok, info, fsize, fsum = downloadFile(repo.owner, repo.repo, sha, e, dest)
    if not ok then
      failed = failed + 1
      warn("  ! " .. e.path .. ": " .. info)
    else
      manifest[e.path] = { sha = e.sha, size = e.size or info, fsize = fsize, fsum = fsum }
      if #files <= 40 or i % 20 == 0 then
        printf("  [%d/%d] %s (%s bytes)", i, #files, tostring(e.path), tostring(info))
      end
    end
  end

  git.saveCfg(dest, {
    owner = repo.owner, repo = repo.repo, branch = branch,
    commit = sha, tree = treeData.sha, files = manifest,
    filter = { path = opts.path, ext = opts.ext },
    updated = os.time and os.time() or 0,
  })

  local n = 0
  for _ in pairs(manifest) do n = n + 1 end
  print(string.format("done: %d files in %s (%d failed)", n, dest, failed))
  if failed > 0 then printError("some files failed; run 'git pull' to retry") end
  return failed == 0
end

function git.cmdPull(args)
  local dest = args[1]
  if dest and dest:sub(1, 2) == "--" then dest = nil end
  dest = resolvePath(dest or ".")
  local opts = git.parseFlags(args, 1)
  local cfg = git.loadCfg(dest)
  if not cfg then return false, git.missingCfgMsg(dest) end

  local sha, resolved = git.resolveCommit(cfg.owner, cfg.repo, cfg.branch)
  if not sha then return false, resolved end
  if sha == cfg.commit and not opts.force then
    print("already up to date (" .. sha:sub(1, 8) .. ")")
    return true
  end

  local treeData, terr = git.fetchTree(cfg.owner, cfg.repo, sha)
  if not treeData then return false, terr end

  local keep = git.makeFilter(cfg.filter or {})
  local remote = {}
  for _, e in ipairs(treeData.tree) do
    if e.type == "blob" and keep(e.path) then remote[e.path] = e end
  end

  local updated, added, failed, bytes = 0, 0, 0, 0

  -- removals first: a tracked file that became a directory upstream would
  -- otherwise block the download of everything under it
  local removed = {}
  for _, path in ipairs(sortedKeys(cfg.files)) do
    if not remote[path] then removed[#removed + 1] = path end
  end
  for _, path in ipairs(removed) do
    if opts.prune then
      fs.delete(pjoin(dest, path))
      cfg.files[path] = nil
      printf("  del   %s", path)
    else
      printf("  gone  %s (kept; use --prune to delete)", path)
    end
  end

  for _, path in ipairs(sortedKeys(remote)) do
    local e = remote[path]
    local old = cfg.files[path]
    if not old or old.sha ~= e.sha then
      local ok, info, fsize, fsum = downloadFile(cfg.owner, cfg.repo, sha, e, dest)
      if ok then
        cfg.files[path] = { sha = e.sha, size = e.size or info, fsize = fsize, fsum = fsum }
        bytes = bytes + info
        if old then updated = updated + 1 else added = added + 1 end
        printf("  %s %s (%s bytes)", old and "update" or "add  ", tostring(path), tostring(info))
      else
        failed = failed + 1
        warn("  ! " .. path .. ": " .. info)
      end
    end
  end

  cfg.commit, cfg.tree, cfg.branch = sha, treeData.sha, cfg.branch
  cfg.updated = os.time and os.time() or 0
  git.saveCfg(dest, cfg)

  print(string.format("pulled %s: %d updated, %d added, %d removed%s, %d bytes, %d failed",
        sha:sub(1, 8), updated, added, #removed, opts.prune and " (deleted)" or " (kept)",
        bytes, failed))
  return failed == 0
end

function git.cmdStatus(args)
  local dest = args[1]
  if dest and dest:sub(1, 2) == "--" then dest = nil end
  dest = resolvePath(dest or ".")
  local cfg = git.loadCfg(dest)
  if not cfg then return false, git.missingCfgMsg(dest) end

  printf("%s/%s  branch %s  commit %s", tostring(cfg.owner), tostring(cfg.repo),
    tostring(cfg.branch), tostring(cfg.commit):sub(1, 8))
  printf("tracked files: %d", #sortedKeys(cfg.files))

  local localFiles = git.walk(dest, "", {})
  local dirty, missing = {}, {}
  for path, meta in pairs(cfg.files) do
    if localFiles[path] == nil then
      missing[#missing + 1] = path
    elseif git.isDirty(pjoin(dest, path), meta) then
      dirty[#dirty + 1] = string.format("%s (local %s bytes, committed %s bytes)", path,
        tostring(localFiles[path]), tostring(meta.size))
    end
  end
  local untracked = {}
  for path in pairs(localFiles) do
    if not cfg.files[path] then untracked[#untracked + 1] = path end
  end
  table.sort(dirty); table.sort(untracked); table.sort(missing)

  for _, m in ipairs(missing) do printf("  missing   %s", m) end
  for _, m in ipairs(dirty) do printf("  modified  %s", m) end
  for _, m in ipairs(untracked) do printf("  new       %s", m) end
  if #dirty == 0 and #untracked == 0 and #missing == 0 then print("  clean") end
  return true
end

function git.cmdLs(args)
  local dest = args[1]
  if dest and dest:sub(1, 2) == "--" then dest = nil end
  dest = resolvePath(dest or ".")
  local cfg = git.loadCfg(dest)
  if not cfg then return false, git.missingCfgMsg(dest) end
  for _, path in ipairs(sortedKeys(cfg.files)) do
    printf("%8d  %s", cfg.files[path].size or 0, path)
  end
  return true
end

function git.cmdBranch(args)
  local dest = resolvePath(args[1] or ".")
  local cfg = git.loadCfg(dest)
  if not cfg then return false, git.missingCfgMsg(dest) end
  printf("%s/%s @ %s (%s)", tostring(cfg.owner), tostring(cfg.repo), tostring(cfg.branch),
    tostring(cfg.commit):sub(1, 40))
  return true
end

--------------------------------------------------------------------------------
-- push
--
-- CC 1.75 can only send GET and POST, so we cannot PATCH a ref. Instead:
--   POST /git/blobs   -> object shas
--   POST /git/trees   -> new tree (based on the tree we cloned)
--   POST /git/commits -> commit whose parent is our known commit
--   POST /git/refs    -> throwaway branch holding that commit
--   POST /merges      -> merge it into the target branch server-side
--------------------------------------------------------------------------------

function git.cmdPush(args)
  local dest = args[1]
  if dest and dest:sub(1, 2) == "--" then dest = nil end
  dest = resolvePath(dest or ".")
  local message = args[2]
  if message and message:sub(1, 2) == "--" then message = nil end
  local opts = git.parseFlags(args, 1)
  if not git.token then return false, "no token - run 'git token <pat>' first (needs write access)" end

  local cfg = git.loadCfg(dest)
  if not cfg then return false, git.missingCfgMsg(dest) end

  local localFiles = git.walk(dest, "", {})
  local keep = opts.all and function() return true end or git.makeFilter(cfg.filter or {})

  local todo = {}
  for path, size in pairs(localFiles) do
    if keep(path) then
      local meta = cfg.files[path]
      if not meta or git.isDirty(pjoin(dest, path), meta) then
        todo[#todo + 1] = path
      end
    end
  end
  if #todo == 0 then print("nothing to push") return true end
  table.sort(todo)

  print(string.format("uploading %d file(s)", #todo))
  local treeEntries = {}
  local blobHintShown = false
  for i, path in ipairs(todo) do
    local content = git.readFile(pjoin(dest, path))
    if content == nil then
      warn("  ! cannot read " .. path)
    else
      local blob, err = git.apiPost("/repos/" .. cfg.owner .. "/" .. cfg.repo .. "/git/blobs",
                                    { content = git.b64encode(content), encoding = "base64" })
      if not blob or not blob.sha then
        warn("  ! blob " .. path .. ": " .. tostring(err))
        if not blobHintShown then
          blobHintShown = true
          warn("  the first upload call failed - check, in this order:")
          warn("    1. git auth " .. cfg.owner .. "/" .. cfg.repo .. "   (token applied? push allowed?)")
          warn("    2. token has Contents: Read and write")
          warn("    3. token's Repository access includes " .. cfg.repo)
          warn("    4. token has not expired")
        end
      else
        treeEntries[#treeEntries + 1] = { path = path, mode = "100644", type = "blob", sha = blob.sha }
        local fsize, fsum = git.fingerprint(content)
        cfg.files[path] = { sha = blob.sha, size = size, fsize = fsize, fsum = fsum }
        printf("  [%d/%d] %s", i, #todo, path)
      end
    end
  end
  if #treeEntries == 0 then return false, "no files uploaded" end

  local tree, terr = git.apiPost("/repos/" .. cfg.owner .. "/" .. cfg.repo .. "/git/trees",
                                 { base_tree = cfg.tree, tree = treeEntries })
  if not tree or not tree.sha then return false, "create tree failed: " .. tostring(terr) end

  local commit, cerr = git.apiPost("/repos/" .. cfg.owner .. "/" .. cfg.repo .. "/git/commits", {
    message = message or ("ComputerCraft update (" .. #treeEntries .. " files)"),
    parents = { cfg.commit },
    tree = tree.sha,
  })
  if not commit or not commit.sha then return false, "create commit failed: " .. tostring(cerr) end

  local stamp = tostring(commit.sha):sub(1, 8)
  local tmpBranch = "cc-sync/" .. stamp
  local ref, rerr = git.apiPost("/repos/" .. cfg.owner .. "/" .. cfg.repo .. "/git/refs", {
    ref = "refs/heads/" .. tmpBranch,
    sha = commit.sha,
  })
  if not ref then
    return false, "create branch " .. tmpBranch .. " failed: " .. tostring(rerr) ..
           " (commit " .. commit.sha .. " exists; you can cherry-pick it on GitHub)"
  end

  local merge, merr = git.apiPost("/repos/" .. cfg.owner .. "/" .. cfg.repo .. "/merges", {
    base = cfg.branch,
    head = commit.sha,
    commit_message = "Merge " .. tmpBranch .. " (ComputerCraft push)",
  })
  if not merge or not merge.sha then
    warn("merged on GitHub manually: branch " .. tmpBranch .. " holds commit " .. commit.sha)
    return false, "server-side merge failed: " .. tostring(merr)
  end

  cfg.commit = merge.sha
  if merge.commit and merge.commit.tree and merge.commit.tree.sha then
    cfg.tree = merge.commit.tree.sha
  end
  cfg.updated = os.time and os.time() or 0
  git.saveCfg(dest, cfg)

  print("pushed: " .. commit.sha:sub(1, 8) .. " merged into " .. cfg.branch ..
        " as " .. merge.sha:sub(1, 8))
  print("note: branch " .. tmpBranch .. " was left behind (CC cannot delete refs)")
  return true
end

--------------------------------------------------------------------------------
-- token storage
--------------------------------------------------------------------------------

-- look for .git-token in the current directory and every parent, so a token
-- stored once at the computer root works from any clone directory.
function git.tokenPath()
  local dir = cwd()
  for _ = 1, 8 do
    local candidate = pjoin(dir, git.TOKEN)
    if fs.exists(candidate) then return candidate end
    dir = parentOf(dir)
    if not dir then break end
  end
  return pjoin(cwd(), git.TOKEN)
end

function git.loadToken()
  local t = git.readFile(git.tokenPath())
  if t then git.token = t:match("^%s*(.-)%s*$") end
end

function git.cmdToken(args)
  if args[1] then
    git.writeFile(git.tokenPath(), args[1])
    git.token = args[1]
    print("token saved to " .. git.tokenPath())
    print("note: for push it needs repo write scope")
    return true
  end
  git.loadToken()
  if git.token and git.token ~= "" then
    print("token set (" .. #git.token .. " chars, " .. git.tokenPath() .. ")")
  else
    print("no token stored at " .. git.tokenPath())
  end
  return true
end

-- Diagnostic: proves whether the token is actually being accepted, using only
-- GET requests (CC cannot read the body of a failed response).
function git.cmdAuth(args)
  git.loadToken()
  if not git.token or git.token == "" then
    print("no token stored at " .. git.tokenPath())
    print("clone/pull work without a token for public repos; push needs one")
    return true
  end
  printf("token: %d chars, header form '%s'", #git.token, git.authStyle)

  local ok, body = git.httpGet(git.API .. "/rate_limit")
  if not ok then
    printError("token was REJECTED (or api.github.com is unreachable)")
    print("check: token not expired, no typo/extra spaces, and Contents: Read and write")
    return false
  end
  local data = json.decode(body)
  local core = data and data.resources and data.resources.core
  if core and core.limit then
    printf("token accepted - core rate limit: %d requests/hour", core.limit)
    if tonumber(core.limit) <= 60 then
      warn("that limit looks UNAUTHENTICATED - the token is not being applied")
    end
  else
    print("token accepted (could not parse the rate_limit body)")
  end

  local repo = args[1] and git.parseRepo(args[1])
  if not repo then
    local cfg = git.loadCfg(".")
    if cfg then repo = { owner = cfg.owner, repo = cfg.repo } end
  end
  if repo then
    local info, err = git.apiGet("/repos/" .. repo.owner .. "/" .. repo.repo)
    if not info then
      printError("cannot read " .. repo.owner .. "/" .. repo.repo .. ": " .. tostring(err))
      return false
    end
    printf("repo visible: %s (private=%s, default branch %s)", tostring(info.full_name),
      tostring(info.private), tostring(info.default_branch))
    -- the permissions block only appears on authenticated calls, so it is a
    -- readable answer to "can this token write?"
    if info.permissions then
      printf("this token may push: %s", tostring(info.permissions.push))
      if info.permissions.push ~= true then
        warn("the token can READ but NOT WRITE - set Contents: Read and write,")
        warn("and check the repo is in the token's Repository access list")
      end
    else
      print("no permissions block returned - token may not be applied to this call")
    end
  else
    print("pass a repo (or run me inside a clone) to check write access:")
    print("  git auth owner/repo")
  end
  return true
end

--------------------------------------------------------------------------------
-- CLI plumbing
--------------------------------------------------------------------------------

function git.parseFlags(args, from)
  local opts = {}
  for i = from or 1, #args do
    local a = args[i]
    if type(a) == "string" and a:sub(1, 2) == "--" then
      local key, value = string.match(a, "^%-%-([%w%-]+)=(.*)$")
      if not key then key, value = string.match(a, "^%-%-([%w%-]+)$") end
      opts[key] = (value == nil) and true or value
    end
  end
  return opts
end

function git.usage()
  print("git.lua " .. git.VERSION .. " for ComputerCraft 1.75 (GitHub only)")
  print("git clone <owner>/<repo> [branch] [dest] [--path=PFX] [--ext=lua,md] [--max=N]")
  print("git pull  [dest] [--prune] [--force]")
  print("git push  [dest] [message] [--all]")
  print("git status [dest]   git ls [dest]   git branch [dest]")
  print("git token [<pat>]      git auth [owner/repo]")
end

function git.run(args)
  if not args or #args == 0 then git.usage() return true end
  local cmd = table.remove(args, 1)
  git.loadToken()
  local handlers = {
    clone = git.cmdClone, pull = git.cmdPull, push = git.cmdPush,
    status = git.cmdStatus, ls = git.cmdLs, fetch = git.cmdPull,
    branch = git.cmdBranch, token = git.cmdToken, auth = git.cmdAuth,
    whoami = git.cmdAuth,
    help = function() git.usage() return true end,
    version = function() print("git.lua " .. git.VERSION) return true end,
  }
  local f = handlers[cmd]
  if not f then
    printError("unknown command: " .. tostring(cmd))
    git.usage()
    return false
  end
  local ok, err = f(args)
  if not ok and err then printError("error: " .. tostring(err)) end
  return ok
end

-- Running this file as a program starts the CLI (no args prints help).
-- Loading it as a library: `local git = require "git"` (require passes the
-- module name as varargs, which we detect and ignore) or set
-- _G.__GIT_LIB = true before dofile("git.lua").
local cliArgs = { ... }
if not _G.__GIT_LIB and not (#cliArgs == 1 and cliArgs[1] == "git") then
  git.run(cliArgs)
end

return git
