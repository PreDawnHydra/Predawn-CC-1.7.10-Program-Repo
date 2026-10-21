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
diskarray/pool        drive discovery, capacity, totals, eject, label,
                      array summary, Init array, Forget
diskarray/manifest    the .diskarray file: read, write, validate, member ids
diskarray/screens     the Overview and Drives screens
```

## Setting up an array in game

1. Put a CC-formatted floppy in each drive you want in the array.
2. On the Overview screen, click **Init array**. Every writable mounted disk gets
   a `.diskarray` manifest; the status bar names the array id and says which
   disks were skipped (a read-only floppy is skipped, and says so).
3. The Overview now shows `array`, `members` (present/expected) and `state`.
   Pull a member out and the state becomes `degraded`, naming the missing slot.
   Put a copy of a member floppy in and it becomes `duplicate`.
4. On the Drives screen, select a drive and use the field at the bottom to set
   its floppy label (click, type, Enter). **Forget** removes that disk's manifest
   and leaves its files alone.

`.diskarray` is a dotfile, so `ls` will not show it — `type .diskarray` from the
shell, or `fs.list()` from `lua`, will.

## What the screens show

- **Overview** — pool totals (drives, disks in, mounted, writable, free total,
  smallest free, files, used) plus the array rows (array, members, state, and
  missing slots / duplicates / disks-without-manifest / bad manifests when they
  are not zero), and one capacity bar per drive showing its slot.
- **Drives** — a clickable list; the detail panel shows side, mount path, label,
  disk id, free, file count, and the manifest (slot + member id, or why there is
  none). `Rescan` re-reads the drives, `Eject` ejects the disk in the selected
  drive, `Forget` clears its manifest. Every button acts on a **single click**:
  it lights up while the mouse button is held and goes back on release (a monitor
  touch has no release event, so the next redraw clears it).

**Free space is live and follows the server config.** `fs.getFreeSpace` answers
with the mount's configured limit minus what it holds (`FileMount`
`getRemainingSpace`, and a floppy mount is created with `floppySpaceLimit`). So a
server whose floppies are set to 1 GB shows roughly 1 GB free per floppy, and one
set to 1 KB shows roughly 1 KB — the numbers are not baked into this program. The
figures refresh on a `disk`/`disk_eject` event, on the Rescan button, and on the
`--rescan` timer, not continuously.

Capacity (the bar's denominator) is an **estimate**: 1.75 exposes no total size,
so it is `free + used`, and used comes from a bounded walk of the mount. A walk
that hits its entry or depth cap is marked `~` / "truncated" instead of being
presented as exact. CC also charges a minimum block per file, so `used` from
`fs.getSize` can read slightly lower than the space the mount has taken.

## Rules this code keeps

- Discover drives at boot, on every `disk` / `disk_eject` event, and on the
  Rescan button. Mount paths (`disk`, `disk2`, …) are probed in attach order, so
  they are never treated as identifiers for a physical drive — the side name is,
  and inside the array the member id from the manifest is. `getDiskID()` is the
  floppy item's damage value: a hint, never a key.
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
order, single-click eject with press/release feedback, the status bar keeping the
note clear of the hint, and a drive disappearing mid-session. The array half
covers manifest round-trips, re-init keeping the array id, garbage / foreign
version / oversized manifests being refused rather than evaluated, degraded and
duplicate detection, Forget, and the label path.

The suite loads the **real** `rom/apis/{colors,keys,textutils}` (vendored in
`tests/rom/`, see the note there) instead of hand-written stubs, so colour
values, key codes and `serialize`/`unserialize` behaviour are the 1.75 ones.
