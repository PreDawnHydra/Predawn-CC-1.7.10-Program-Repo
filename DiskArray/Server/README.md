# DiskArray — Server

The server is the thing that owns the Disk Drives. **Slice 1 works:** it finds
the drives, reports what is in them and how much room the pool has, and lets you
click around it. It does not yet write files to the floppies, and it does not
talk to other computers — that is the rednet slice.

## Run it

```
cd cc/DiskArray/Server
diskarray_server.lua
```

The `.lua` is required: `shell.resolveProgram` never appends it. Nothing about
the program's own location is hard-coded — it takes its folder from
`shell.getRunningProgram()` and `fs.getDir()` (which returns `""` for a file at
the root), so a clone, the computer root and a floppy all work as long as the
`diskarray/` folder sits next to the program.

```
--monitor <side>   draw on a monitor instead of the computer screen
--refresh <secs>   redraw interval, default 1
--rescan  <secs>   drive re-scan interval, default 10
--help             usage
```

A monitor is clickable: 1.75 fires `monitor_touch (side, x, y)` when a player
clicks one — there is no `monitor_click` in this version — and the app loop maps
it onto a left click. Ctrl+T stops the program. Auto-start is deliberately not
installed by this slice.

## Files

```
diskarray_server.lua  entry point: arguments, module load, optional monitor
                      redirect, first scan, crash reporting
diskarray/theme       colour roles (MineSwarm framework)
diskarray/widget      base widget + drawing primitives (MineSwarm framework)
diskarray/widgets     button, panel, label, menu, tabs, list, progress, field
diskarray/app         screen manager + one event loop (MineSwarm framework,
                      plus monitor_touch/monitor_resize and an onEvent hook)
diskarray/pool        drive discovery, capacity, totals, eject, label
diskarray/screens     the Overview and Drives screens
```

## What the screens show

- **Overview** — pool totals (drives, disks in, mounted, writable, free total,
  smallest free, files, used, layout, last scan) and one capacity bar per drive.
- **Drives** — a clickable list; the detail panel shows side, mount path, label,
  disk id, free, and file count. `Rescan` re-reads the drives, `Eject` needs two
  clicks within 5 seconds.

Capacity is an **estimate**: 1.75 exposes no total size for a floppy, only
`fs.getFreeSpace`. Used bytes come from a bounded walk of the mount, and a walk
that hits its entry or depth cap is marked `~` / "truncated" instead of being
presented as exact.

## Rules this code keeps

- Discover drives at boot, on every `disk` / `disk_eject` event, and on the
  Rescan button. Mount paths (`disk`, `disk2`, …) are probed in attach order, so
  they are never treated as identifiers for a physical drive — the side name and
  `getDiskID()` are.
- Capacity and writability come from `fs.getFreeSpace` / `fs.isReadOnly`; the
  1.75 drive peripheral has no such method.
- Every `fs.*` and `peripheral.*` call is wrapped: `fs.list` raises on a missing
  path or a file, and a drive method can raise on a non-CC disk.
- Every loop is bounded (`MAX_WALK_ENTRIES`, `MAX_WALK_DEPTH`) and reports
  truncation, so a weird disk cannot spin the computer or grow memory.
- Modules are loaded extension-less (`os.loadAPI` names the global from
  `fs.getName()`).

## Tests

```
cd cc-dev/DiskArray/tests && timeout 120 node --max-old-space-size=1024 run.js 2>&1 | tail -25
```

Covers discovery, totals, the bounded walk (huge and deep trees), read-only and
blank drives, methods that raise, both screens drawing without tripping the Lua
5.1 `string.format("%s", nil)` rule, `monitor_touch` and `mouse_click` argument
order, the two-step eject, and a drive disappearing mid-session.
