# Predawn-CC-1.7.10-Program-Repo
A collection of scripts for Computer Craft 1.7.10 mostly for my own personal use but take a look around!

## Layout

- `From_CC_Computer/` — programs that were written and pushed from inside the game.
- everything else — anything hand-written on a PC.

### From_CC_Computer/CC_git

A git client that runs **inside** ComputerCraft 1.75 (Minecraft 1.7.10). It speaks
to the GitHub REST API using only `http.get`/`http.post`, which is all that
version of ComputerCraft offers — no sockets, no `PATCH`, no `DELETE`.

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo main cc
git pull cc
git status cc
git push cc "what changed"
```

`git.lua` is also a library (`local git = require("git")`), and `bootstrap.lua` is
a one-file in-game downloader for grabbing a single script from this repo.
