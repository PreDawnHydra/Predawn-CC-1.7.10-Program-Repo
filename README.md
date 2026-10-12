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
