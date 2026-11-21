# PrusaLink plugin for Q-SYS

Monitor and control one Prusa printer from Q-SYS over the printer's own
**PrusaLink** API. The panel is styled after the Prusa MINI's screen and knob.

Supported printers: current Prusa printers on Buddy firmware (MINI/MINI+,
MK4/MK4S, Core One, XL) using the PrusaLink **v1** API. It was developed against a MINI
running firmware 8.0.2. Older printers that use a Raspberry Pi for
PrusaLink (MK3/MK3S) and resin printers aren't supported.

For a farm of printers on a Prusa Connect Local server, see `../PrusaConnect/`.

## Install

1. Copy `PrusaLink.qplug` into your Q-SYS plugins folder
   (on Windows: `Documents\QSC\Q-Sys Designer\Plugins`).
2. Restart Q-SYS Designer, then drag **Prusa Link** into your design.

## Setup

In the plugin's **Setup** tab, enter:

- **Printer IP**: the printer's address, e.g. `192.168.0.45`.
- **Username**: `maker` (filled in for you).
- **Password**: the PrusaLink password shown on the printer under
  **Settings → Network → PrusaLink**.

The plugin logs in with HTTP digest authentication, which is what current
firmware uses. The online dot in the corner turns on once the printer answers.

### Properties

| Property | Default | What it does |
|---|---|---|
| Poll Interval | 5 s | How often status and job are refreshed (1–60). |
| Debug | off | Writes requests and results to the Q-SYS log. The routine status/job polls are left out to keep the log readable. |

## Pages

### Monitor

- Status, current job, progress, nozzle and bed temperatures (actual / target),
  Z height, print speed, and the job's filament type.
- The centre area shows either the temperature graph (red nozzle, blue bed) or
  the job's **progress picture**: the model starts greyed out and fills with
  colour from the bottom as it prints, with an orange line at the current height.
- **Click the knob** to switch between the graph and the picture. Temperatures
  keep recording while the picture is showing.

### Control

- **File list:** every print file on the printer's storages, including folders.
  Long names are shortened with "…".
- **Tap a file** to open a preview over the list: the model picture with its
  material, layer height, estimated time, nozzle size and filament weight. Tap
  the preview to close it.
- **Start Print** prints the selected file. **Pause** toggles pause/resume.
  **Stop** cancels the job.
- **Delete** needs a second press within 5 seconds. The button turns red and
  shows "Confirm?". Deleting is blocked while printing or paused, and on read-only storage.

### Setup

Printer IP, Username and Password (see above).

## Troubleshooting

| You see | Meaning |
|---|---|
| Status `Auth failed` | Wrong username or password. |
| Status `Offline` | The printer didn't answer. Check the IP and that PrusaLink is enabled. |
| Blank picture | The file has no thumbnail, or the printer couldn't read it. Turn on Debug to see the request. |
| Graph labels look empty in Designer | They're filled in when the plugin runs. |

Requests go to the printer one at a time. The MINI's small web server drops
connections when several requests arrive together.

## For developers

The plugin is one Lua file, and its runtime code lives in the `PL` table. Offline
tests load the real `.qplug` with mocked Q-SYS globals (Controls, Timer,
HttpClient and more):

```sh
apt-get install -y lua5.3 lua-dkjson
lua5.3 tests/run.lua          # from the repo root
lua5.3 tests/run.lua delete   # only tests whose name contains "delete"
```

The design notes and build plan are in `docs/superpowers/`.
