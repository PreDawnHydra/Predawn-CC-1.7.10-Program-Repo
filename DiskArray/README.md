# DiskArray

**Status: slice 2 runs.** The server finds the Disk Drives, shows a clickable pool
(totals plus a capacity bar per drive) on the computer screen or a monitor, and
now knows the **array**: each member floppy carries a `.diskarray` manifest, and
the UI reports the array id, its members, and whether it is whole, degraded or
has a duplicated member. Still no user-file striping/mirroring and no rednet;
the rest of this file is the design those steps will implement.

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

## Array identity (slice 2)

Each member floppy carries its own copy of the array metadata at
`<mount>/.diskarray`, written with `textutils.serialize` — RAID-style, so the
array is recognisable from the disks alone and nothing has to survive on the
computer. It holds: the array id, this disk's slot, this disk's member id, the
full member list, the layout mode, and who created it.

**`getDiskID()` is not an identity.** In 1.75 it is the floppy item's *damage
value* (`ItemDiskLegacy.getDiskID` → `ItemStack.func_77960_j`), assigned once
when the floppy is crafted, and it returns `-1` when the damage is 0 or less. It
can be missing and it can collide, so it is displayed as a hint and used to warn
about a likely swap — never used as a key. The member id written in the manifest
is the identity: `<arrayID>#<slot>`, derived rather than random (CC's
`math.random` is not seeded per computer). Two disks claiming the same member id
is the copied-floppy case, and the UI reports it as `duplicate` instead of
pretending not to notice.

**States the pool can be in:** `none` (no manifest anywhere), `ok` (every member
listed is present), `degraded` (a listed slot is missing — the UI names the
slots), `duplicate` (two disks claim one member). Disks that are mounted but
have no manifest, and manifests that exist but cannot be read, are counted
separately so a half-built array is visible.

**Slots are sticky.** Re-running `Init array` never renumbers existing members: a
disk that is already a member keeps its slot and member id, and a fresh disk
takes the lowest free slot. Side-name order only decides the slots of a first,
empty array. Renumbering would be harmless today (mode `plain` places no data),
but once chunks are laid out by slot it would scramble the array, so the rule is
set now.

**Buttons:** `Init array` writes a manifest to every writable mounted disk
(slots follow side-name order, so the same setup gets the same slots; an
existing array id is reused rather than invented again) and says which disks it
skipped and why. `Forget` removes one disk's manifest and leaves its files
alone. The label field on the Drives screen sets the floppy's label (click, type,
Enter).

## Arrays over the network (slice 3)

A Disk Drive does not have to be plugged into the server computer. Run
**`diskarray_host.lua`** on any computer with drives and a wired modem; the
server pings the network and the host answers with a snapshot of its drives,
which then appear in the same lists as local ones, keyed **`#<computerID>:<side>`**
— for example `#7:back`.

Three programs, one folder:

| program | what it does |
|---|---|
| `diskarray_server.lua` | the brain and the UI: pool, arrays, Builder |
| `diskarray_host.lua`   | exports one computer's drives over rednet |
| `Client/` (later)      | a terminal UI for asking the array for files |

**The array definition still lives on the floppies.** Enrolling a remote disk
sends the manifest to *its* host, which writes it with its own copy of the
manifest module. So a server can never invent a format the disks would not
understand, and pulling a host's floppy out of a remote drive still leaves a
readable member disk.

**Protocol v1**, protocol id `diskarray`, plain tables (1.75 rednet carries
tables natively, so there is no JSON anywhere): `ping`, `hosts`, `query`, `act`,
`ack`, `bye`. Drive lists are **batched** (12 per message) with `seq/last/total`,
because this build exposes no small hard packet limit — the only constant in the
modem path is 128 open channels per modem — and nothing proves the limit is
large either. A conversation that got cut short therefore shows up as
`incomplete` instead of quietly losing the drives at the end. That limit still
needs measuring in game.

**Hosts are liveness-tracked**: a host that stops answering for `--host-timeout`
seconds (default 20) is dropped and its drives leave the pool, so a computer
that got blown up does not leave phantom members forever.

## Builder

`Init array` is gone: it enrolled every writable disk it could find and gave you
no way to say "just this one". The Builder tab has three sub-screens:

- **Devices** — every drive on the network, marked `[#]` already in an array,
  `[x]` selected, `[ ]` usable, `[-]` unusable, and the unusable ones say why
  ("read-only disk", "member of DA8.x - Forget it first").
- **New** — mode strip, an optional name, and a **plan**: the exact slot each
  disk will take, its free space, and whether it is behind a modem. The plan is
  produced by the same slot planner the write uses, so it cannot lie.
- **Repair** — the arrays that exist, their members with `-- MISSING --` rows,
  and the free disks that could join. `Join selected`, `Forget member`,
  `Rename array`.

Slots are sticky everywhere: a member keeps its slot, newcomers take the lowest
free one, and a join never renumbers the array.

## UI behaviour

- **No bottom bar.** The body runs to the last row of the screen — there is no
  key-hint row and no `enter=open  tab=focus` legend. Feedback for an action
  ("rescanned: 8 disk(s)", "labelled drive_right", or a failure) appears in the
  **top-right of the title bar** for 8 seconds, then the pool status comes back.
- **One click, every button.** A button lights while the mouse button is held and
  goes back on release; a monitor touch has no release event, so the next redraw
  clears it. A click never leaves focus sitting on the button.
- **The cursor only appears where it means something.** The surface cursor is
  switched off at the end of every frame and parked at 1,1; a focused text field
  is the only thing that turns it on, and it sits on that field's caret. Left
  alone it blinked in the bottom-right corner, wherever the last draw wrote.
- **The view follows the data.** A Rescan, a `disk`/`disk_eject` event, an
  auto-rescan or a rename rebuilds the screen, and the stat rows read the pool at
  draw time — so the numbers never show an older scan until you switch screens.
- **A drive is named `<side>: <floppy label>`** — in the Overview bars, the
  Drives list and the drive panel. Never by mount path, which identifies nothing.
- **Capacity bars** show as many drives as fit, and the panel says
  `CAPACITY  3 of 8 shown` when it cuts the list short. The denominator is an
  estimate (`free + used` from a bounded walk); a truncated walk is marked `~`.

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
2. **Done (slice 2):** manifest read/write at `<mount>/.diskarray`, array
   identity by member id, degraded/duplicate detection, `Init array`, `Forget`,
   and the label field.
3. **Done (slice 3):** the Array Builder (Devices / New / Repair), multi-array
   support, join/leave/rename, and drives behind a wired modem through
   `diskarray_host.lua` and the `diskarray` rednet protocol.
4. Chunked file transfer over that protocol, then `put` / `get` / `ls` and
   `mirror` mode — the first thing that needs bytes to cross the modem.
5. `Client/` program with the terminal UI.
6. `stripe` and `span` modes.

## Tests

Offline, under fengari, with CC 1.75 API stubs (including the strict
`string.format` and the `os.loadAPI` environment semantics from `bios.lua`).
Run it capped and timed, like every other suite here:

```
cd cc-dev/DiskArray/tests && timeout 120 node --max-old-space-size=1024 run.js 2>&1 | tail -25
```

It also refuses to run if any source uses Lua 5.2+/5.3-only syntax, `fs.complete`,
`os.getenv`, or a `monitor_click` string — none of which exist in this jar.
