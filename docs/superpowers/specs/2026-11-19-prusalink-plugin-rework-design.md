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
- **Tapping a file shows a preview** (picture plus print details) over the list.
- **The Monitor page shows print progress as the model picture filling with orange**, and clicking the knob switches between that and the temperature graph.
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
8. **Pictures**: file preview panel, progress picture, knob view toggle (below).
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
- A successful delete closes the preview panel if it is open, and removes the file from the list.

This adds no new controls and doesn't change the layout. *(My call. The maintainer asked for confirmation but didn't specify the mechanism.)*

### File preview (Control page): mockup option B

Mockups: https://claude.ai/artifact/GbpbgzY3Mhxi5bxevy1W27. The maintainer picked **1B**.

- Tapping a file in the Files list selects it and opens a **preview panel over the list area** (same position and size as the list, `{31,66}` × `{228,217}`). The panel shows:
  - the model picture on the left (about 118 × 118),
  - file details on the right: name, `filament_type`, `layer_height`, estimated time (`estimated_print_time`, formatted as h/m), `nozzle_diameter`, and filament grams. Any field the printer doesn't send is left out.
- **Tapping the panel closes it** and brings back the list. Start Print and Delete stay where they are and act on the previewed file.
- Picture source: the entry's `refs.thumbnail`, falling back to `refs.icon`. Use the path exactly as the API returns it; don't build it, because the spec example (`/api/thumbnails/...`) may differ from real firmware. Fetch it with digest auth, base64-encode the PNG and set it as `IconData` on a read-only button. This is the same technique the temperature graphs use.
- No picture, or a failed fetch: the panel still opens with the details and a blank picture area. Log the failure only when Debug is on.
- Cache pictures per file path for the session.
- Implementation hint (builder's call): the panel can be a full-size button (the tap target, with visibility toggled), plus a picture button and a details text control layered on top. Check `IsInvisible`/z-order behavior in Q-SYS for overlapping controls.

### Print progress (Monitor page): mockup option A, with a knob toggle

The maintainer picked **2A**: the current job's model picture is shown greyed out and **fills with orange from the bottom** as the print progresses, like PrusaLink's own web page. The percentage sits underneath.

- It uses the same area as the temperature graph (`{44,160}` × `{222,155}`).
- **Clicking the knob toggles** between the progress view and the EzSVG temperature graph. On the Monitor page the knob is only an image graphic today, so add a transparent, flat **`View Toggle`** button the same size as the knob image (`{99,431}`, 87 × 87), layered over it. The knob image stays; only the click target is new.
- Picture source: the current job's `job.file.refs.thumbnail`/`icon`, fetched like the file preview and cached per job.
- Redraw when progress changes, not on every poll.
- **Default and idle behavior *(my call)*:** the plugin starts on the graph view. The toggle remembers whichever view was chosen last. When there's no job, the progress view shows "No job" and no picture.
- Temperature samples keep being recorded while the progress view is showing, so the graph has no gap when you switch back.

**How to draw it.** It is unknown what Q-SYS's SVG renderer supports, so the builder tries these in order and keeps the first that renders correctly on the MINI:

1. **One SVG with everything.** An EzSVG document embeds the PNG twice as `<image href="data:image/png;base64,...">`. The bottom copy is greyed with an `feColorMatrix` filter. The top copy is tinted orange and clipped to a rectangle whose height is `progress%` of the model's height. This is the truest to the web page; it needs SVG `<image>`, filters and `clipPath`.
2. **Two layered controls.** The normal-color picture goes on a button via `IconData`. On top of it sits a second button with a transparent EzSVG overlay: a semi-transparent orange rectangle rising from the bottom. This needs no image embedding; it needs only a transparent SVG over another control.
3. **Fallback: vertical progress bar.** Show the picture as is, with a vertical orange bar beside it (left or right) that fills from the bottom. The bar can be a Q-SYS meter control or an EzSVG rectangle. Use this only if neither of the above renders. Tell the maintainer before switching. *(No ring gauge: the maintainer ruled it out.)*

### Versioning and identity

- `PluginInfo.Version` becomes `1.0`. `BuildVersion` is `1.0.0.0`.
- Keep the existing `PluginInfo.Id`, so designs using the old plugin can upgrade in place. The Connect plugin will get a new Id.
- Control names that already exist keep their names, so existing pins and UCI links survive. The exception is `API Key`, which is removed.

## Testing

- **In the container:** a Lua syntax check (`luac -p`) of the plugin. Offline tests of the parser, folder-walk and delete-confirmation functions, using mock `Controls`/`Timer`/`HttpClient` and sample JSON shaped like the spec.
- **On the maintainer's machine:** load the plugin in Q-SYS Designer and test against the MINI: connect, bad password, file list, thumbnail, print, pause/resume, stop, delete (confirm and timeout), file preview open and close, the progress picture filling during a print, the knob toggle, and graphs.

## Left to the builder

- The exact `HttpClient` digest parameter and how the response body arrives for binary PNGs.
- Whether Q-SYS offers a masked or password text style for the Password field. Use it if available.
- Which real JSON keys the MINI returns for `refs` and `meta`, and adjusting the parsers to match.
- Small layout nudges needed to fit Username/Password, the preview panel and the knob toggle. No restyling.

## Out of scope / later

- The Prusa Connect plugin (its own design).
