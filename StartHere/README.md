# StartHere

A one-line downloader for a ComputerCraft 1.75 computer that has nothing on it yet —
no floppy, no clone, no installer. The pasted line becomes a downloader, and the
downloader fetches everything else from GitHub.

```
StartHere  ->  install_CC_Git  ->  /usr/git  ->  git pull / git push
```

## The line to copy

```
local u,d=... u=u or "https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/install_CC_Git.lua" d=d or (u:match("[^/]+$")):gsub("%.lua$","") local r=http.get(u) if not r then printError("no net, blocked, or 404") return end local c=r.getResponseCode()or 0 local b=(r.readAll()or"").."\n" r.close() if c>=400 then printError("HTTP "..c) return end local h=fs.open(d,"w") if not h then printError("cannot write "..d) return end h.write(b) h.close() print(#b.." bytes -> "..d)
```

That is **509 characters**, one line, no comments — deliberately.

ComputerCraft 1.75 silently cuts any paste at **512 characters**: `WidgetTerminal`
does `if (text.length() > 512) text = text.substring(0, 512)` before it sends the
`paste` event. Anything longer arrives chopped mid-statement, which looks like a
syntax error in the file. So the whole program has to live inside 512 characters,
and the test suite in `../CC_git/tests` refuses to run if this line ever exceeds
that, grows a second line or a comment, or stops matching the copy in this README.

## First install

```
edit StartHere            # paste the line, Ctrl+S, Ctrl+Q
StartHere                 # downloads install_CC_Git (saved without .lua)
install_CC_Git            # installs git, the updater and the completer into /usr
reboot                    # picks up the new shell path
git help
```

`install_CC_Git` installs anything missing and refreshes anything already present, so
running it again is how you update. It writes its hook at the **top** of `/startup` — a
marker comment, the shell path line, and the tab-completion line. If you already have a
startup script of your own, yours still runs underneath, and `install_CC_Git unhook`
takes the hook back out. Everything then lives in `/usr`, so later updates need no
pasting and no floppy:

```
install_CC_Git            # update everything; it re-pulls itself first
install_CC_Git status     # what is installed, which version, where the hook is
```

## Using it

```
StartHere                 # the repo's install_CC_Git, saved as "install_CC_Git"
StartHere <url>           # save under the URL's own file name
StartHere <url> <dest>    # save as <dest>
```

The destination defaults to the file name from the URL **with `.lua` removed** —
ComputerCraft's shell matches program names exactly and never appends `.lua`, so an
extension-less file is the one you can run by typing its name. Pass a destination if
you want the extension kept.

With no arguments it pulls:

```
https://raw.githubusercontent.com/PreDawnHydra/Predawn-CC-1.7.10-Program-Repo/main/CC_git/install_CC_Git.lua
```

## What it does

1. `http.get` the URL. ComputerCraft 1.75 returns `nil` for a blocked host, a
   network failure **and** a 404 — it cannot tell them apart, so the error message
   says all three.
2. Reads the body with `readAll()`, which drops the final newline; StartHere adds it
   back so the saved file matches the source byte for byte.
3. Writes the file — **it overwrites without asking**, because an overwrite prompt
   would not fit in the 512-character paste budget.
4. Reports how many bytes landed.

It checks the HTTP status but not the content: a 200 response that is not the program
still gets written. The sanity check on size lives in `install_CC_Git`, which refuses
anything under 200 bytes rather than installing it.

## Limits

- Text only. ComputerCraft 1.75's HTTP layer returns a Java string, so binary files
  arrive corrupted — StartHere cannot fetch images, zips, or anything non-text.
- The URL must be reachable under the server's `http_whitelist` setting.
- It follows no redirects; use the direct `raw.githubusercontent.com` URL.
- It overwrites an existing destination without asking.
- If a floppy holds an old copy of the installer, prefer this one: the repository is
  the source of truth, and a stale copy in the computer's own folders will be run in
  preference to `/usr` because the shell path starts with `.`.
- If the line ever needs to grow past 512 characters, paste it in two goes: paste
  the first half, press End, then paste the rest. Each paste is capped at 512, not
  the file.
