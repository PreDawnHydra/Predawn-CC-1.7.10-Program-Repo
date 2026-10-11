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

## Auto-start

Each program writes `/startup` (no extension — that is the exact name the ROM looks
for) on every run, which relaunches it at boot. `Quit` on the Settings tab writes
`/halt`, which stops the loop; delete `/halt` to re-enable it. The generated
`/startup` also puts `/usr` on the shell path, which is where `git` lives.

`/startup` itself is not in this repo — it is generated. For `git` itself see the
`CC_git` folder.
