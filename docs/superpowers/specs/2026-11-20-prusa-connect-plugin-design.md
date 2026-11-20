# Prusa Connect Plugin — Design

Date: 2026-11-20
Status: Building. The maintainer asked for the build to start without approving this doc first; review it when back.

## Intent

This is a Q-SYS plugin for people running **Prusa Connect Local**, Prusa's self-hosted server for a whole printer farm. One plugin instance covers every printer on the server. A **Farm** tab picks the printer, and the other tabs work on the selected one. It's forked from the PrusaLink plugin (`PrusaLink/`), which stays the single-printer option. Like PrusaLink, it's a fun learning project that should work well enough for other Q-SYS developers to use.

## What the maintainer asked for

- **All printers in one plugin.**
- **First tab is Farm:** a list of printers with **one button per printer**. No dropdown or combo box here.
- **After selecting a printer, the Monitor and Files tabs work like PrusaLink's.** Monitor is pretty much unchanged. Files is the PrusaLink Control page (list, preview, print, delete, pause/stop).
- **A clear indicator of which printer you're controlling.**
- **A new Control tab:** hotend and bed temperatures, moving the axes, homing, and similar.
- **The PrusaLink plugin is left alone** while this is built.

## Non-goals (for now)

- The progress picture on Monitor. It waits on the PrusaLink picture spike, and the same method is used here later.
- Uploading files, cameras, the chamber controls on Core One, and filament load/unload.
- The live event stream (SSE). The plugin polls instead (see Approaches).
- Printers on other servers. One plugin instance talks to one server.

## API facts this design relies on

Sources: Prusa Connect docs in `prusa3d/prusa-connect` and the official Home Assistant client. Nothing was tested against a live server, and the API is **beta (0.x)**.

- **Auth:** `Authorization: Bearer pcl_…` on every request.
  - Tokens are made in the web app (Settings → API credentials) and need **`operate`** scope.
  - They expire after 90 days by default.
  - A bad token returns 401 (`core.auth/TOKEN_INVALID`); missing permission returns 403 (`core.auth/ACCESS_DENIED`).
- **Server:** `http://<host>:8080`, base path `/api/v1`.
- **Devices:** `GET /api/v1/devices` returns `{items, total, …}`.
  - Each item has `id`, `name`, `model`, `connected`, `state` (a flat map), `job`, `capabilities`, `verbs`.
  - `state` keys: `/state`, `/tools/0/nozzle_temp`, `/tools/0/nozzle_target_temp`, `/temperature/bed`, `/temperature/bed_target`, `/axis/z`, `/speed`, `/job/progress`, `/job/time_remaining` (s), `/job/path`.
  - `job` has `display_name`, `progress`, `state`.
- **Files:** `GET /api/v1/devices/{id}/storages`, then `GET /api/v1/devices/{id}/files?path=usb/…`.
  - Items have `name` (8.3), `display_name`, `path`, `folder`, `size`, `read_only`.
  - Thumbnails come from `GET /api/v1/devices/{id}/files/thumbnail?path=…`.
- **Print:** `POST /api/v1/devices/{id}/print` with `{"path": "usb/…"}`. A refusal comes back as 200 with `command.ok = false`.
- **Delete:** `DELETE /api/v1/devices/{id}/files?path=…` returns 204.
- **Commands:** `POST /api/v1/devices/{id}/commands` with `{"verb": …, "args": {…strings…}}`. The verbs used:
  - `core.command.pause_print`, `resume_print`, `stop_print`
  - `set_nozzle_temperature` (`nozzle_temperature` 0–300), `set_bed_temperature` (`bed_temperature` 0–120)
  - `move` (`x`, `y`, `feedrate`), `move_z` (`distance`, `feedrate`)
  - `home` (`axis` "XYZ"), `disable_steppers`

  The verb must be listed in the device's `capabilities` or `verbs`.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| A | One printer per plugin instance, with a dropdown | Simplest, but the maintainer wants one farm view with buttons. Rejected. |
| **B** | **One instance for the farm, polling `GET /devices`** *(chosen)* | A single request refreshes every printer's status, which suits Q-SYS's `HttpClient`. |
| C | One instance using the SSE event stream | Instant updates, but Q-SYS would need a hand-rolled HTTP client over a raw TCP socket for a long-lived stream. Too much for v1; possible later. |

## Design

### Pages

`Farm`, `Monitor`, `Files`, `Control`, `Setup`. They use the same orange-and-black MINI frame and knob image as PrusaLink.

### Selected-printer indicator *(my call)*

A read-only text control, **`Selected Printer`**, sits in the orange strip above the black screen (`{25,8}` × `240×24`, white, bold) on Monitor, Files and Control. It shows the printer's name, or "No printer selected".

### Farm page *(my calls on layout)*

- A property **`Printer Slots`** (1–8, default 6) sets how many printer buttons the plugin has. Q-SYS plugins can't add controls at runtime.
- Each slot `i` is a button **`Printer i`** whose legend is the printer's name, plus a read-only text **`Printer i Status`**, e.g. `PRINTING 42%`, `IDLE` or `OFFLINE`.
- Rows are 46 px apart inside the black screen.
- Printers are sorted by name. Unused slots are hidden. The selected printer's button is highlighted (`Boolean = true`).
- If the server has more printers than slots, the extras are left out, and the bottom status line says so.
- A **`Farm Status`** line at the bottom shows `3 printers`, `Token rejected`, `Token needs operate access` or `Server offline`.
- **Selection is kept by device `id`** across polls. If the selected printer disappears, the selection clears.

### Monitor page

Same as PrusaLink: status, job name, progress, temperatures and targets, Z, speed, and the EzSVG temperature graphs. All of it comes from the selected device's `state` map and `job`. Material isn't in the documented state keys, so it's left blank.

### Files page (PrusaLink's Control page)

- **List:** storages, then files for the selected printer, walking into folders. The list shows long names; requests use the item's `path`.
- **Preview panel:** tap a file to open it, tap the panel to close.
  - The picture comes from the thumbnail endpoint.
  - Details are the name and size; listings carry no print time or filament.
- **Buttons:** Start Print, Pause/Resume, Stop, and Delete with the same 5 s two-press confirmation.
- Changing printer clears the list and reloads it.

### Control page (new)

Each command checks that the printer supports the verb. If it doesn't, the command isn't sent and `Control Status` says so.

- **Temperatures:**
  - `Nozzle Setpoint` and `Bed Setpoint` knobs (0–300 / 0–120), each with a **Set** button.
  - Presets **PLA** (215/60), **PETG** (240/85) and **Cooldown** (0/0).
  - Current temperatures are shown alongside.
- **Jog:**
  - Step buttons **0.1 / 1 / 10 mm**, one lit at a time; the default is 1.
  - **X−, X+, Y−, Y+, Z−, Z+** buttons.
  - Feedrates: XY 3000 mm/min, Z 600.
  - X/Y use `move`, Z uses `move_z`.
- **Home All** (`home`, axis `XYZ`) and **Motors Off** (`disable_steppers`).
- **Safety *(my call)*:** jog, home and motors-off are refused while the printer is PRINTING or PAUSED. Temperatures can still be changed.
- **⚠️ Unverified:** the docs don't say whether `move` and `move_z` are relative. The first hardware test should jog by 1 mm with the hotend clear of the bed.
- A **`Control Status`** line shows the last result, e.g. `Sent: Home all`, `Busy: printing` or `Not supported`.

### Setup page

- **Server Address** (`host` or `host:port`; the port defaults to 8080 when left off) and **API Token**.
- Property **Use HTTPS** (default off).
- The same Online indicator as PrusaLink.

### Properties

`Poll Interval` (1–60 s, default 5), `Debug`, `Printer Slots` (1–8, default 6), `Use HTTPS` (false).

### Code

- One file: `PrusaConnect/PrusaConnect.qplug`, with a new `PluginInfo.Id` and runtime table `PC`.
- It reuses PrusaLink's request queue, stale-response guard, delete confirmation and preview code, adapted to Bearer auth and device paths.
- Tests go in `tests/test_connect_*.lua`, using the same harness via `M.load(props, "PrusaConnect/PrusaConnect.qplug")`.

## Build order

1. Scaffold: plugin info, properties, pages, controls and layout.
2. Request helper (Bearer), farm polling, printer buttons, selection and indicator.
3. Monitor from the selected device.
4. Files: listing, preview and thumbnail, print, pause/resume/stop, delete with confirmation.
5. Control page commands.
6. README.

## Left for hardware/server testing

- Whether arg values must be strings (the docs say they're sent as text).
- Whether `move` is relative.
- The real `/state` values and their casing.
- The shape of the storages response.
- Whether Q-SYS `HttpClient` accepts a self-signed certificate when HTTPS is on.
