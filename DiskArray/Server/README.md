# DiskArray — Server

*Nothing here runs yet — see `../README.md` for the design.*

The server is the only thing in the array that touches the floppies. It owns the
Disk Drives, keeps the manifest and the file table, and answers `diskarray`
requests from clients over rednet.

Planned files:

```
diskarray_server.lua   entry point: drive discovery, rednet loop, terminal UI
diskarray/             extension-less modules, loaded with os.loadAPI
  core                 config, logging, the request loop
  raid                 mirror / stripe / span, chunk placement, checksums
  net                  the diskarray protocol, chunking, request ids
  app, screens, theme, widget, widgets
```

Rules the server code has to keep:

- Discover drives every boot and on every `disk` / `disk_eject` event. Mount paths
  (`disk`, `disk2`, …) are assigned by attach order, so they are not stable
  identifiers — use `getDiskID()` and the label.
- Check `fs.isReadOnly(path)` and `fs.getFreeSpace(path)` before any write; the
  drive peripheral has no capacity or writability method in 1.75.
- `fs.makeDir`, `fs.delete`, `fs.copy` return nothing and **raise** on failure —
  wrap them in `pcall` and verify with `fs.isDir` / `fs.exists`.
- Yield between chunks so one client's upload does not starve the others.
