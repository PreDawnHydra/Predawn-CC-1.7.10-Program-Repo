# Predawn-CC-1.7.10-Program-Repo

Scripts for ComputerCraft 1.75 on Minecraft 1.7.10, published so they can be pulled
and updated from inside the game.

## Layout

One folder per program, at the top level. Nothing here is separated by whether it
was written in game or on a PC.

### CC_git

A git client that runs **inside** ComputerCraft 1.75 (Minecraft 1.7.10). It speaks
to the GitHub REST API using only `http.get`/`http.post`, which is all that
version of ComputerCraft offers — no sockets, no `PATCH`, no `DELETE`.

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo main cc
git pull cc
git status cc
git push cc "what changed"
```

`git.lua` is also a library (`local git = require("git")`). `install_CC_Git.lua`
installs and updates it, and `git_complete.lua` provides tab completion.

### StartHere

A single pasted line that becomes a downloader, for a computer that has nothing on it
yet.

```
StartHere  ->  install_CC_Git  ->  /usr/git
```

### MineSwarm

A server-plus-agents system (work in progress): a controller computer plus agent
computers, with a terminal UI. See `MineSwarm/README.md`.

### DiskArray

Several Disk Drives presented as one volume, with a clickable UI: Overview,
Drives, an **Arrays** screen (one pool per row with a capacity bar; open a pool to
see its members and browse its files), and an **Array Builder** that creates arrays, joins disks into them and
repairs them (capacity bars, single-click Eject, labels, degraded/duplicate
reporting). Slice 3 runs: drives behind a **wired modem** join the same pool —
run `diskarray_host.lua` on another computer and its drives appear as
`#7:back` — and the array definition still lives on the floppies, because a
remote disk is enrolled by asking its own host to write the manifest. Files
themselves cross the wire too: `put`/`get`/`ls` per array at `<mount>/files/`, in
`plain` (one copy) or `mirror` (a copy per member, compared when read), with
checksum-verified chunks. No `span`/`stripe` yet — those modes are refused rather
than faked. `DiskArray/README.md` holds the design,
the rednet protocol, and the 1.75 drive-peripheral and mount-path facts it is
built on.

```
cd cc/DiskArray/Server
diskarray_server.lua --monitor left
```
