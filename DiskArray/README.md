# DiskArray

**Status: slice 1 runs.** The server program shows a clickable pool of the Disk
Drives on its computer — totals plus a capacity bar per drive — on the computer
screen or on a monitor. There is no manifest, no striping/mirroring and no
rednet yet; the rest of this file is the design those steps will implement.

Several **Disk Drives** on one computer, presented as a single volume ("the array"),
and served over **rednet** so other computers can read and write floppies without
owning a drive themselves.

## Roles

| role | folder | owns |
|---|---|---|
| server | `Server/` | the disk drives, the array manifest, all writes to floppies |
| client | `Client/` | nothing on disk — talks the `diskarray` rednet protocol |

One server per array. Many clients. Clients never touch `/disk*` mounts directly;
the server is the only writer, which is what keeps a floppy consistent when several
computers want at it at once.

## Hardware

- ComputerCraft 1.75 on Minecraft 1.7.10 (see `../CC-1.75-QUIRKS.md`).
- N Disk Drives attached to the server computer.
- A modem (wireless or cable) on the server and on each client for rednet.

## Facts this design depends on

All of these were read out of the installed `ComputerCraft1.75.jar`
(`javap -c`), not from modern ComputerCraft docs. They are the reason the design
looks the way it does.

**The `drive` peripheral exposes exactly these methods in 1.75:**
`isDiskPresent()`, `getDiskLabel()`, `setDiskLabel( label )`, `hasData()`,
`getMountPath()`, `hasAudio()`, `getAudioTitle()`, `playAudio()`, `stopAudio()`,
`ejectDisk()`, `getDiskID()`.
There is **no** `getSpace()`, **no** `isReadOnly()`, **no** `unmount()` on the
peripheral — those are modern CC. Capacity and writability come from the `fs` API
instead: `fs.getFreeSpace(path)`, `fs.isReadOnly(path)`, `fs.getDrive(path)`.

**Mount paths are assigned by a probe loop, not by which side the drive is on.**
`TileDiskDrive.mountDisk` tries `disk`, then `disk2`, `disk3`, … and keeps the
first free name; the result is stored per (drive, computer) and depends on the
order drives attach. So **never hard-code "the drive on the left is `/disk2`"**.
Discover the drives at boot and after every `disk` / `disk_eject` event:
`peripheral.getNames()` → `peripheral.getType(name) == "drive"` → `getMountPath()`.
Identify array members by `getDiskID()` plus the disk label, not by mount path.

**`fs` in 1.75 is:** `combine, copy, delete, exists, find, getDir, getDrive,
getFreeSpace, getName, getSize, isDir, isReadOnly, list, makeDir, move, open`.
No `fs.attributes`, no modification times, no `fs.getMountPath`. Binary is fine
locally: `fs.open` accepts `rb` and `wb`.

**Capacity:** `floppySpaceLimit=125000` → **125 KB per floppy** by default. The
computer's own HDD is a separate 1 MB quota (`computerSpaceLimit`).

**rednet in 1.75 is:** `open, close, isOpen, send, broadcast, receive, host,
unhost, lookup, run`. `rednet.host` / `rednet.lookup` mean a client can find the
array by name instead of hard-coding a computer ID.

**Not yet measured:** the maximum rednet message size in this build. Assume any
file has to be chunked; start at ~1 KB of text per message and confirm in game
before tuning it up.

## Running it in game (slice 1)

**Hardware.** One computer with 1-4 Disk Drives attached to any sides. A monitor
is optional. No modem is needed until the rednet slice exists. Floppies: any
CC-formatted floppy mounts; a raw floppy mounts read-only.

**Get the files.** From a computer that already has `git`:

```
git pull cc
cd cc/DiskArray/Server
diskarray_server.lua
```

The `.lua` is required — `shell.resolveProgram` never appends it. The program
finds its own folder from `shell.getRunningProgram()`, so it works from a clone,
from the computer root, or from a floppy (`/disk/diskarray_server.lua`) as long
as the `diskarray/` folder sits next to it.

**Options.**

```
diskarray_server.lua --monitor left    -- draw on the monitor on that side
diskarray_server.lua --refresh 1       -- redraw interval (s)
diskarray_server.lua --rescan 10       -- drive re-scan interval (s)
```

A monitor is clickable too: 1.75 fires `monitor_touch (side, x, y)` when a
player clicks one, and the UI maps that to a left click.

**Stopping it.** Ctrl+T. Auto-start is deliberately not installed by this slice —
it would write `/startup`, a computer-wide change, for a program that so far
only reads.

## Design

**Membership.** Each member floppy carries a manifest at `/disk*/.diskarray`
(written with `textutils.serialize`, not JSON — 1.75 has no JSON decoder). The
manifest holds the array UUID, the member's disk ID, its slot number, and the
layout mode. A disk without a manifest is not in the array and is never written
to. Note `.diskarray` is invisible to `ls` (the ROM `list` skips dotfiles) but
real to `fs.*`.

**Layout modes.**
- `mirror` — every chunk written to every member. Capacity = smallest disk.
  Survives any one disk dying. Default.
- `stripe` — chunks round-robin across members. Capacity = sum of members.
  Losing one disk loses the whole volume.
- `span` — members concatenated in slot order. Capacity = sum, and one lost disk
  loses only the files that lived on it.

**Chunking.** Files are split into fixed-size chunks; each chunk carries a 31-bit
rolling checksum (`h = (h*31 + byte) % 2147483647`, the same trick `git.lua` uses,
because CC has no hashing library and Lua 5.1 doubles must stay under 2^31 to be
exact). A file table maps path → chunk list → member slots + checksums.

**Protocol.** rednet protocol `diskarray`. Requests: `hello`, `status`, `ls`,
`get`, `put`, `rm`, `mkdir`, `label`, `rescan`. Every reply carries the request id
so a client can match them. Long transfers are chunked request/response pairs with
a `seq` and an `eof` flag, and the server `os.queueEvent`/`sleep` yields between
chunks so one big upload does not freeze every other client.

**Failure handling.** A missing or swapped disk is reported as degraded, and the
array refuses `put` in `stripe` mode until it is whole. Because floppies are
removable, the server re-reads membership on `disk` and `disk_eject` events rather
than trusting a cached list.

## Layout

```
DiskArray/
  README.md              this file
  Server/
    diskarray_server.lua the program that owns the drives        (slice 1: works)
    diskarray/           modules: theme, widget, widgets, app, pool, screens
  Client/
    diskarray_client.lua the rednet client + terminal UI         (not written yet)
    diskarray/           modules: client, app, screens, theme, widget, widgets
  tests/                 offline suite (run.js + stubs.lua + tests.lua)
```

`theme`, `widget`, `widgets` and `app` are the MineSwarm UI framework, copied so
a clone of one role folder is self-contained; `app` in this copy adds
`monitor_touch`/`monitor_resize` handling and an `onEvent` catch-all.

Modules stay **extension-less** and are loaded with `os.loadAPI("/diskarray/core")`
style paths — `os.loadAPI` names the global from `fs.getName()`, so
`diskarray/core.lua` would create a global called `core.lua` and leave `core` nil.
Each role folder carries its own copy of the shared modules, the same way MineSwarm
ships a `swarm/` folder per role, so a clone of one role folder is self-contained.

## Limitations

- 125 KB per floppy. A 50 KB program fits; a repo clone does not.
- Floppies are removable: the array's identity is the set of disk IDs, so pulling a
  disk out is a real failure mode, not a hypothetical.
- The server is one computer running one Lua loop. Throughput is bounded by rednet,
  not by the drives.
- No real hashes, so corruption detection is a 31-bit checksum, not a digest.

## Roadmap

1. **Done (slice 1):** `Server/diskarray_server.lua` — drive discovery, pool
   totals, a capacity bar per drive, clickable Overview and Drives screens,
   Rescan and single-click Eject, monitor support. Offline suite in `tests/`.
2. Manifest read/write (`/disk*/.diskarray`), degraded detection, `label`.
3. `put` / `get` / `ls` over rednet with chunking and checksums, `mirror` mode only.
4. `Client/` program with the terminal UI.
5. `stripe` and `span` modes.

## Tests

Offline, under fengari, with CC 1.75 API stubs (including the strict
`string.format` and the `os.loadAPI` environment semantics from `bios.lua`).
Run it capped and timed, like every other suite here:

```
cd cc-dev/DiskArray/tests && timeout 120 node --max-old-space-size=1024 run.js 2>&1 | tail -25
```

It also refuses to run if any source uses Lua 5.2+/5.3-only syntax, `fs.complete`,
`os.getenv`, or a `monitor_click` string — none of which exist in this jar.
