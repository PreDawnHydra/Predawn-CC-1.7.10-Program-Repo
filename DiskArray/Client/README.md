# DiskArray — Client

*Nothing here runs yet — see `../README.md` for the design.*

A client computer with a modem and no disk drives. It finds the array with
`rednet.lookup("diskarray", <name>)`, then does its file work through the server.
It never opens `/disk*` paths itself.

Planned files:

```
diskarray_client.lua   entry point: find the array, terminal UI
diskarray/             extension-less modules, loaded with os.loadAPI
  client               protocol client: requests, request ids, chunk reassembly
  app, screens, theme, widget, widgets
```

Rules the client code has to keep:

- Re-look-up the server if a request times out — the server may have rebooted and
  its computer ID is not something to cache forever.
- Reassemble chunks by `seq`, verify each chunk's checksum, and fail the whole
  file rather than writing a partial one.
- `rednet.receive` takes a protocol filter and an optional timeout; always pass a
  timeout so a dead server cannot hang the client forever.
