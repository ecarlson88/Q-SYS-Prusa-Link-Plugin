# PrusaLink Plugin Rework — Design

Date: 2026-11-19
Status: Draft for approval

## Intent

This repo will hold two Q-SYS plugins:

1. **PrusaLink**: controls one printer directly over its PrusaLink API. This design covers it.
2. **Prusa Connect**: talks to Prusa's self-hosted Prusa Connect Local server, which manages many printers. It will be forked from the finished PrusaLink plugin and designed separately, after this one ships.

The PrusaLink plugin is a personal "fun" project for learning plugin development. It should still **work reliably** and be good enough to publish, so other Q-SYS developers can install it, read the code and experiment with it.

## Goals

- Works against the current **PrusaLink v1 API on Buddy firmware**: MINI/MINI+, MK4/MK4S, Core One and XL. The maintainer can only test on a MINI. Other models are supported by following the spec, not by testing.
- **Digest authentication on every request.** The v1 spec (`Prusa-Link-Web/spec/openapi.yaml`, `1.0.0-draft`) defines only `digestAuth`; `X-Api-Key` is not in it.
- Fix what is broken today: `getKEY()` is undefined, so every request errors; `getPASS()` is defined twice and reads a `Password` control that doesn't exist; read and write requests use mixed auth.
- **Delete asks for confirmation.**
- **Selecting a file shows its thumbnail.**
- Code a developer can read and modify, plus a README with setup instructions.

## Non-goals

- MK3/MK3S with a Raspberry Pi running PrusaLink (legacy API).
- SL1 resin printers.
- Uploading files from Q-SYS.
- Camera feeds.
- Running several printers from one plugin instance. Use one plugin per printer, or the future Connect plugin.

## Anti-goals (the work fails if any of these happen, even if the plugin runs)

- The MINI-style look changes noticeably. Layout, colors, images and page structure stay; additions fit into the existing frame.
- A file gets deleted on a single accidental press.
- The old plugin files are overwritten or deleted.

## Constraints

- It is a single-file Q-SYS `.qplug` (Lua). Available libraries: `rapidjson`, `EzSVG`, `HttpClient`, `Timer`, `Crypto`.
- The PrusaLink API is still a draft spec. Field names, especially in file `meta`, may differ from the spec on real firmware, so read values defensively and confirm them against the MINI.
- No Q-SYS Core or Designer in the dev container. Final checks happen on the maintainer's machine with a real MINI.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | Patch v09 in place | Fastest. The repeated per-request code stays, so the next API change means fixing many places again, and the Connect fork inherits the mess. |
| **B** | **Restructure the runtime code, keep the layout** *(chosen)* | Moderate effort. One request helper and one state table, with clear sections. Keeps the UI. Gives developers and the Connect fork a clean base. |
| C | Full rewrite including the layout | Clean start, but throws away the MINI-style UI the maintainer wants to keep. |

**Chosen: B.** The maintainer picked it. It keeps the look and makes the code something other developers, and the Connect fork, can build on.

## Repository layout

```
.OLD/                      <- existing plugin files moved here unchanged (git mv)
  Prusa-Link_07.qplug
  Prusa-Link_08.qplug
  Prusa-Link_09.qplug
  Prusa Link Text Controller.qsys
PrusaLink/
  PrusaLink.qplug          <- the reworked plugin
  README.md                <- install, setup, troubleshooting
PrusaConnect/              <- later, separate design
imgs/                      <- shared source images (unchanged)
docs/superpowers/specs/    <- design docs
README.md                  <- repo overview pointing at both plugins
```

The maintainer asked for "a .OLD folder or something", so the folder is `.OLD/`. The old `.qsys` test design goes there too because it references the old plugin version. *(My call.)*

## Design decisions

### Authentication and setup

- The Setup page replaces the **API Key** field with **Username** (default `maker`) and **Password**, placed where API Key is now. Printer IP stays.
- Every request goes through one helper that passes `User`/`Password` to `HttpClient`. The builder confirms whether `HttpClient` needs an explicit digest setting (for example an `Auth` parameter) or negotiates digest automatically, and tests it against the MINI.
- Changing IP, Username or Password resets state and triggers a fresh poll and file refresh.
- **Online** reflects whether the last status request returned 200. A 401 shows `Status = "Auth failed"` so a bad password is obvious.

### Runtime code structure (in file order)

1. **Config and state**: one `State` table (job id, printer state, file lookup, read-only storages, selected file, pending-delete flag).
2. **Request helper**: `request{ method, path, headers, onOk, onError }`. It builds the URL from the IP, adds auth, logs when debug is on, decodes JSON safely, and routes by status code.
3. **Polling**: `/api/v1/status` and `/api/v1/job` on a timer. `/api/v1/info` and `/api/version` run once at connect. Info goes to the debug log and could later fill a model label.
4. **Parsers**: one function per endpoint. Each takes decoded JSON and writes to controls.
5. **Files**: `/api/v1/storage` → `/api/v1/files/{storage}/` → recursive folder walk. Keeps the current `display_name` handling. Each file entry also stores its `refs` and `meta`.
6. **Job actions**: print, pause/resume, stop.
7. **Delete with confirmation** (below).
8. **Thumbnail** (below).
9. **Temperature graphs**: existing EzSVG code, kept as is apart from tidying.
10. **Startup.**

### Plugin Properties (new)

- **Poll Interval** (seconds, default 5).
- **Debug** (on/off). Controls `print()` logging. Off by default so logs stay clean for users.

### Delete confirmation

There's no popup in Q-SYS plugins, so the Delete button confirms itself:
- First press: the Delete button's legend changes to **"Confirm?"** and turns red. Nothing is deleted.
- A second press within **5 s** sends the delete.
- If 5 s pass, or a different file is selected, the button goes back to normal.
- The existing checks stay: no deleting while printing or paused, and no deleting on read-only storage.

This adds no new controls and doesn't change the layout. *(My call. The maintainer asked for confirmation but didn't specify the mechanism.)*

### File thumbnail

- When a file is selected in the Files list, read that entry's `refs.thumbnail`, falling back to `refs.icon`. Use the path exactly as the API returns it. Don't build it: the spec example (`/api/thumbnails/...`) may differ from real firmware.
- Fetch it with the same digest auth, base64-encode the PNG and set it as `IconData` on a new read-only button **`Thumbnail`**. This is the same technique the temperature graphs use.
- Placement on the Control page is the empty area to the right of Pause/Stop, about `{140,323}` × `{102,71}`:

  ```
  ┌──────────── Files list ────────────┐
  │                                    │
  └────────────────────────────────────┘
  [ Start Print ] [ Delete    ]
  [ Pause       ] ┌──────────┐
  [ Stop        ] │ thumbnail│
                  └──────────┘
  ```
- If there's no thumbnail or the fetch fails, the button is blank. Log the failure only when Debug is on.
- Cache thumbnails per file path for the session, so re-selecting a file doesn't fetch it again.
- **Open risk:** the maintainer's earlier attempt at thumbnails hit a dead end, possibly over image format. The spec implies PNG. The first build step is a minimal spike that fetches one thumbnail from the MINI and displays it, before the rest is built on top.

### Versioning and identity

- `PluginInfo.Version` becomes `1.0`. `BuildVersion` is `1.0.0.0`.
- Keep the existing `PluginInfo.Id`, so designs using the old plugin can upgrade in place. The Connect plugin will get a new Id.
- Control names that already exist keep their names, so existing pins and UCI links survive. The exception is `API Key`, which is removed.

## Testing

- **In the container:** a Lua syntax check (`luac -p`) of the plugin. Offline tests of the parser, folder-walk and delete-confirmation functions, using mock `Controls`/`Timer`/`HttpClient` and sample JSON shaped like the spec.
- **On the maintainer's machine:** load the plugin in Q-SYS Designer and test against the MINI: connect, bad password, file list, thumbnail, print, pause/resume, stop, delete (confirm and timeout), and graphs.

## Left to the builder

- The exact `HttpClient` digest parameter and how the response body arrives for binary PNGs.
- Whether Q-SYS offers a masked or password text style for the Password field. Use it if available.
- Which real JSON keys the MINI returns for `refs` and `meta`, and adjusting the parsers to match.
- Small layout nudges needed to fit Username/Password and the thumbnail. No restyling.

## Out of scope / later

- Showing the current job's thumbnail on the Monitor page (`job.file.refs`). It's cheap once the thumbnail code exists, but it isn't in v1.0.
- Showing file metadata (estimated time, filament, layer height) next to the thumbnail.
- The Prusa Connect plugin (its own design).
