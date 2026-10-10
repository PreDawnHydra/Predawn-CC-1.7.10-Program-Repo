-- bootstrap.lua - fetch one text file (usually git.lua) into this computer.
-- ComputerCraft 1.75: http.get returns nil on any non-2xx response, and the body
-- is text only. readAll() drops the trailing newline, so we add one back.
--
-- usage:  bootstrap <url> [dest]
--         bootstrap                      (uses DEFAULT_URL below, prompts for dest)

local DEFAULT_URL = ""   -- e.g. "https://raw.githubusercontent.com/you/cc-scripts/main/git.lua"

local url, dest = ...

if not url then
  if DEFAULT_URL ~= "" then
    url = DEFAULT_URL
  else
    print("usage: bootstrap <url> [dest]")
    print("or edit DEFAULT_URL at the top of this file")
    return
  end
end

if not dest then
  dest = url:match("([^/]+)$") or "download.txt"
  if dest == "" then dest = "download.txt" end
  if fs.exists(dest) then
    io.write("Overwrite " .. dest .. "? y/n ")
    if read() ~= "y" then
      print("cancelled")
      return
    end
  end
end

print("GET " .. url)
local response = http.get(url)
if not response then
  printError("request failed - no network, host blocked, or the URL 404s")
  printError("(ComputerCraft 1.75 cannot tell those apart)")
  return
end

local code = response.getResponseCode and response.getResponseCode() or 0
local body = response.readAll() or ""
response.close()

if code >= 400 then
  printError("HTTP " .. code)
  return
end

if body:sub(-1) ~= "\n" then body = body .. "\n" end

local handle = fs.open(dest, "w")
if not handle then
  printError("could not open " .. dest .. " for writing (disk full?)")
  return
end
handle.write(body)
handle.close()

print("wrote " .. #body .. " bytes to " .. dest)
if dest:match("git%.lua$") then
  print("run it with: git help")
end
