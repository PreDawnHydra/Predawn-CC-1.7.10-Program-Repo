# TinyFetch

The smallest possible way to get software onto a ComputerCraft 1.75 computer when
you have nothing on it yet — no floppy, no clone, no installer.

Pasting into ComputerCraft only delivers **a single line**, so `TinyFetch.lua` is
written as one line with no comments. Copy the whole line below, paste it into the
`edit` program, save, and you have a downloader. From there you can fetch the real
tools (`install_CC_Git.lua`, then `git.lua`) from GitHub.

## The line to copy

```
local u,d=... if not u then u="https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/install_CC_Git.lua" end if not d then d=(u:match("([^/]+)$")) or "download.txt" end if fs.exists(d) then io.write("Overwrite "..d.."? y/n ") if read()~="y" then print("cancelled") return end end local r=http.get(u) if not r then printError("fetch failed: no network, blocked host, or 404") return end local c=r.getResponseCode and r.getResponseCode() or 0 local b=r.readAll() or "" r.close() if c>=400 then printError("HTTP "..c) return end if b:sub(-1)~="\n" then b=b.."\n" end local h=fs.open(d,"w") if not h then printError("cannot write "..d) return end h.write(b) h.close() print("wrote "..#b.." bytes to "..d) if d:match("install_CC_Git%.lua$") then print("next: "..d) end
```

That is 799 characters, one line, no comments — deliberately. `tests/` in the
`CC_git` folder fails if a second line or a comment ever creeps in.

## Using it

```
edit TinyFetch        # paste, Ctrl+S, Ctrl+Q
TinyFetch             # no arguments: fetches install_CC_Git.lua from the repo
TinyFetch <url>       # fetch a URL, saving it under its own file name
TinyFetch <url> <dest># fetch a URL, saving it as <dest>
```

With no arguments it pulls:

```
https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/install_CC_Git.lua
```

## What it does

1. `http.get` the URL. ComputerCraft 1.75 returns `nil` for a blocked host, a
   network failure **and** a 404 — it cannot tell them apart, so the error message
   says all three.
2. Reads the body with `readAll()`, which drops the final newline; TinyFetch adds
   it back so the saved file matches the source byte for byte.
3. Refuses to overwrite an existing file unless you answer `y`.
4. Writes the file and reports how many bytes landed.

## Then continue the setup

```
TinyFetch
install_CC_Git
reboot
git help
```

`install_CC_Git` puts `git.lua` in `/usr` and adds it to the shell path, so after a
reboot `git` works from any directory. See the `CC_git` folder for that program.

## Limits

- Text only. ComputerCraft 1.75's HTTP layer returns a Java string, so binary files
  arrive corrupted — TinyFetch cannot fetch images, zips, or anything non-text.
- The URL must be reachable under the server's `http_whitelist`.
- It follows no redirects; use the direct `raw.githubusercontent.com` URL.
