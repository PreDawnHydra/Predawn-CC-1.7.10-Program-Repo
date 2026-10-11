# MineSwarm

A server-plus-agents system for ComputerCraft 1.75 (Minecraft 1.7.10). **Work in
progress** — these are the current in-game scripts, published so they can be pulled
and pushed with the `git` program. No detailed docs yet.

```
MineSwarm/
  Swarm_Server/     swarm_server.lua  +  swarm/  (theme, widget, widgets, app, core, screens)
  Swarm_Agent/      swarm_agent.lua   +  swarm/  (theme, widget, widgets, app, agent, screens)
```

## Installing

Copy the files to the computer's root, keeping the `swarm/` folder name and the
**extension-less** module names — the programs load them with
`os.loadAPI("/swarm/theme")`, and `os.loadAPI` names the global from `fs.getName()`,
so `swarm/theme.lua` would create a global called `theme.lua` and leave `theme` nil.

```
/swarm_server.lua     server computer
/swarm_agent.lua      agent computers
/swarm/               the modules that program loads
```

## Run it from wherever you cloned it

Nothing about the program's own location is hard-coded. It asks the shell which file it
is running (`shell.getRunningProgram()`), takes the folder from that
(`fs.getDir()` — which returns `""` for a file at the root, hence the default `"/"`),
and from there:

- modules load from `<that folder>/swarm/...`
- the `/startup` it writes relaunches `<that folder>/swarm_server.lua`

So a clone anywhere works — `/swarm_server.lua`, `/MineSwarm/Swarm_Server/swarm_server.lua`,
even a floppy. `/startup` and `/halt` deliberately stay at the computer root: `startup`
is the exact literal name the ROM looks up, and `/halt` is a computer-wide switch.

**Clone folder gotcha.** `--path=` is relative to the *repo* root, and the clone folder is
where that subtree lands, so cloning into a folder already called `MineSwarm` repeats the
name — `/MineSwarm/MineSwarm/Swarm_Server/...`. Give the clone a different name to avoid
the echo:

```
git clone PreDawnHydra/Predawn-CC-1.7.10-Program-Repo --path=MineSwarm/Swarm_Server/ swarm-server
```

This matches desktop git: a clone always contains the **repo root**, and a path filter
(sparse checkout) hides other paths without ever moving a subtree up to the root. If you
want `Swarm_Server/` itself to be the root, that is a separate repository, not a flag.

One `/startup` per computer: if both the server and an agent run on the same computer,
whichever started last owns it.

## Auto-start

Each program writes `/startup` (no extension — that is the exact name the ROM looks
for) on every run, which relaunches it at boot. `Quit` on the Settings tab writes
`/halt`, which stops the loop; delete `/halt` to re-enable it. The generated
`/startup` also puts `/usr` on the shell path, which is where `git` lives.

`/startup` itself is not in this repo — it is generated. For `git` itself see the
`CC_git` folder.
