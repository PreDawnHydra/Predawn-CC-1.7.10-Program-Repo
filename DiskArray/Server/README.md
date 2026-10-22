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
--monitor <side>      draw on a monitor instead of the computer screen
--refresh <secs>      redraw interval, default 1
--rescan  <secs>      local drive re-scan interval, default 10
--discover <secs>     ask the network for host drives, default 5
--host-timeout <secs> drop a host silent this long, default 20
--no-net              ignore modems: only this computer's drives
--help                usage
```

## Running a drive host (drives behind a modem)

On any other computer with Disk Drives and a **wired modem**:

```
cd cc/DiskArray/Server
diskarray_host.lua
```

It needs no UI and loads only `manifest`, `pool` and `net`. It answers the
server's pings, pushes a fresh drive list when a disk goes in or out, and carries
out orders the server sends (eject, label, write a manifest, clear a manifest) —
always with its own copy of the manifest module, so the file format stays in one
place.

```
--beacon <secs>     re-announce the drive list, default 10
--allow <id,id>     only take orders from these computer IDs (default: any)
--once              print what it would report, then exit (a check)
```

`--once` is the quick sanity check: it prints the drives and their manifests
without touching rednet. Any computer on the rednet can send orders, so use
`--allow` if the wire is shared. Ctrl+T stops a host; the server drops its
drives after `--host-timeout` seconds of silence.

A monitor is clickable: 1.75 fires `monitor_touch (side, x, y)` when a player
clicks one — there is no `monitor_click` in this version — and the app loop maps
it onto a left click. Ctrl+T stops the program. Auto-start is deliberately not
installed by this slice.

## Files

```
diskarray_server.lua  entry point: arguments, module load, optional monitor
                      redirect, rednet plumbing, first scan, crash reporting
diskarray_host.lua    the other end: exports this computer's drives over rednet
diskarray/theme       colour roles (MineSwarm framework)
diskarray/widget      base widget + drawing primitives (MineSwarm framework)
diskarray/widgets     button, panel, label, menu, tabs, list, progress, field
diskarray/app         screen manager + one event loop (MineSwarm framework,
                      plus monitor_touch/monitor_resize and an onEvent hook)
diskarray/pool        drives (local + remote), capacity, totals, eject, label,
                      array grouping, slot planning, manifest writes
diskarray/manifest    the .diskarray file: read, write, validate, member ids
diskarray/net         the rednet protocol, both ends: chunking, checksums,
                      batching, host roster, expiry
diskarray/builder     the rules behind the Builder: what may join, what a build
                      would do, join / leave / rename
diskarray/screens     Overview, Drives and Builder screens
```

## If a member goes missing

**Pulling the floppy** (or pressing `Eject`): the drive fires `disk_eject`, the
server rescans immediately, and the Overview goes `state: degraded` with
`missing slots: 2`. Nothing is lost — every member floppy carries the full
member list, so the definition of the array survives on the disks that are still
there.

**Pulling the drive block itself**: that fires `peripheral_detach`, not a disk
event, and the server rescans on that too — the drive just leaves the list and
the array shows the same hole.

**Restore it**: put the same floppy back in **any** drive. Membership lives on
the floppy, not on the drive, so it comes back as the same member in the same
slot and the state returns to `ok`. It does not have to go back into the drive it
came out of — the side name is only where a floppy happens to be plugged in right
now.

**Replace it**: put a blank, CC-formatted floppy in and press **Init array**.
Slots are sticky: the surviving members keep their slot and member id, and the
blank takes the lowest free slot — the hole. The message reads
`initialised 8 disk(s) as DA8.x (4 kept, 4 joined)`.

Two things to know about `Init array`:

- it enrols **every writable mounted disk**, so take out any floppy you do *not*
  want in the array first — or press **Forget** on it afterwards, which clears
  its manifest and leaves its files alone;
- a read-only floppy is skipped and named in the message, which is why an array
  can come out one disk short.

If a **copy** of a member floppy turns up (a backup you put back in), the state
becomes `duplicate` instead of quietly accepting two disks that claim to be one
member: select the one you want and press `Forget` on the other.

There is no per-disk **Join** yet, so adding one member means letting `Init array`
sweep the drives. That is the next thing this slice would grow.

## Setting up an array in game

1. Put a CC-formatted floppy in each drive you want in the array. For drives on
   another computer, run `diskarray_host.lua` there and press `Ping hosts`.
2. **Builder → Devices**: click each floppy you want (it turns `[x]`). A disk that
   will not be taken says why. `Add free disks` picks every usable one.
3. **Builder → New**: type a name if you want one, pick a mode, and read the
   plan — it shows the slot every disk will take before anything is written.
   Press `Create array`.
4. The Overview shows `array`, `members` (present/expected) and `state`. Pull a
   member out and the state becomes `degraded`, naming the missing slot.
5. **Builder → Repair**: select the array, select a free disk, press
   `Join selected` — it lands in the hole and nobody else moves. `Forget member`
   takes one out and leaves its files alone. `Rename array` rewrites the name on
   every member disk.

`.diskarray` is a dotfile, so `ls` will not show it — `type .diskarray` from the
shell, or `fs.list()` from `lua`, will.

## Files: put, get, ls

Open a pool on the **Arrays** screen and its FILES panel lists what it holds and
which members hold it:

```
+ FILES  (mirror) --------------------------------+
|  both.txt     [8/8]                             |
|  second.txt   [1/8]   not on every member       |
+-------------------------------------------------+
   Back    Get file    Delete    Repair

```

* Click a file to select it; `Get file` copies it onto **this computer** at
  `/hdd/dcget/<name>`. `hdd` is not a guess: 1.75 resolves a path by its first
  segment against a mounted drive name, and `Computer` builds its filesystem
  with `new FileSystem("hdd", rootMount)`, so a relative `dcget/x` resolves to
  nothing at all.
* `Delete` is **two clicks** — the first arms (the row gets a `!` and the
  note says so), the second removes it from every member. Deleting user data is
  not a single click, unlike ejecting a floppy.
* Type a short note in the field and press enter to put a small file in. Anything
  longer goes through `files.put(name, text, arrayID)` from `lua`.

A file lives at **`<mount>/files/<name>`** on each member that holds it, so a
floppy pulled out of any computer still carries its own copy of everything the
array put on it. That is also why `files` never touches rednet itself: it takes a
transport (`files.setTransport`) which the server entry fills in with a
request/answer round trip, and the *host* is the only thing that touches its own
filesystem. Paths on the wire are `"<side>/files/<name>"` — the side name, because
`#7:back` means nothing to computer 7.

**Layout modes**

| mode | what a put does | a member dies |
|---|---|---|
| `plain` | written to the member with the most free space | you lose the files on that member |
| `mirror` | written to **every** member that is present | nothing is lost |
| `span` | not implemented — the Builder refuses it rather than pretending | — |

A `mirror` read compares the copies. If one disk holds different bytes you are
told (`1 copy(ies) disagree with #77:top`) and given a readable copy, rather than
whichever one the scan happened to reach first.

**Why a transfer cannot silently corrupt.** 1.75's `fs.open(path,"r")` gives only
`readLine`/`readAll`/`close`, and `readAll` drops newlines, so a file travels as a
list of lines plus a `trailing` flag and is rejoined with `\n`. Writes go
`fwipe` (truncate, creating the folder first) then `fchunk` pieces of 400
characters, each carrying a 31-bit checksum that the **host** verifies before it
writes. A bad piece is refused, the partial file is deleted, and the failure is
reported — a file that exists but is wrong is worse than one that is missing.

## What the screens show

- **Overview** — the array rows first (array, members present/expected, state,
  and missing slots / duplicates / disks-without-manifest / bad manifests when
  they are not zero), then the pool totals (drives, disks in, mounted, writable,
  free total, smallest free, files, used), then one capacity bar per drive. If
  the terminal is too short, rows are dropped from the **bottom** — the array
  warnings survive, the totals are what give way — and the bars panel says
  `CAPACITY  N of M shown` when it cannot show them all.
- **Drives** — a clickable list; the detail panel opens with the drive's name
  (`drive_right: MyFloppy`) and then mount, disk id, free, file count and the
  manifest (slot + member id, or why there is none). `Rescan` re-reads the
  drives, `Eject` ejects the disk in the selected drive, `Forget` clears its
  manifest, and the field at the bottom sets the floppy label (click, type,
  Enter — the cursor blinks there while the field has focus, and nowhere else).
  Every button acts on a **single click**: it lights up while the mouse button is
  held and goes back on release (a monitor touch has no release event, so the
  next redraw clears it).
- **Builder** — three sub-screens behind a tab strip:
  - **Devices**: every drive on the network, sorted local first. `[#]` already in
    an array, `[x]` selected for a new one, `[ ]` usable, `[-]` refused — and a
    refused drive always says why. Buttons: `Rescan`, `Ping hosts`,
    `Add free disks`, `Clear`.
  - **New**: mode strip (`plain` today; `mirror` and `span` are shown as *not
    implemented* rather than offered as working buttons), an optional name, and
    the **plan** — the slot each disk would take, its free space, and whether it
    sits behind a modem. The plan comes from the same slot planner the write
    uses, so it cannot disagree with what happens next. Button: `Create array`.
  - **Repair**: the arrays that exist, their member rows (a hole reads
    `-- MISSING --`), and the free disks that could join. Buttons:
    `Join selected`, `Forget member`, `Rename array`, `Rescan`.
- **No status bar.** The body spans the whole screen. An action's note appears in
  the top-right of the title bar for 8 seconds, then the pool status returns.
- **`Init array` is gone.** It enrolled every writable disk it could find; the
  Builder's selection model replaces it. `pool.initArray` still exists as the
  low-level writer, but it now takes an explicit key list and an array id.

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
order, single-click eject with press/release feedback, the cursor being off
except inside a focused field, the body spanning the screen with no status bar,
notes going to the title bar, a Rescan refreshing the view in place, capacity
bars that render their caption instead of a closure, and a drive disappearing
mid-session. The network half runs both ends of the protocol in one Lua state:
chunking and its checksums (a corrupted or missing piece is refused, never
passed through), file reads and writes through a real host object (`fstat`,
`fread`, `fwipe`+`fchunk`, `fdir`, `fdel`), and a `put` whose chunk is corrupted
en route leaving **no** half-written file behind, batching a 25-drive host into three messages and reassembling
them, orders getting an ack plus a fresh drive list, a foreign protocol version
refused, and a silent host dropped out of the pool. The Builder half covers the
rules (read-only refused, mirror mode refused until it writes anything, a member
of another array refused with "Forget it first", names cleaned), the plan showing
the slot it will take, a remote disk enrolled through the network route, rename
and leave, and all three Builder sub-screens drawing. The array half
covers manifest round-trips, re-init keeping the array id, garbage / foreign
version / oversized manifests being refused rather than evaluated, degraded and
duplicate detection, Forget, and the label path. The recovery half covers the
things that matter when hardware moves: a member pulled out degrades the array
and names the hole, the same floppy in a different drive comes back as the same
member in the same slot, breaking the drive block (`peripheral_detach`) refreshes
the pool too, and a blank disk joining never renumbers the members.

The suite loads the **real** `rom/apis/{colors,keys,textutils}` (vendored in
`tests/rom/`, see the note there) instead of hand-written stubs, so colour
values, key codes and `serialize`/`unserialize` behaviour are the 1.75 ones.
