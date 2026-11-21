# Prusa Connect plugin for Q-SYS

Monitor and control a whole farm of Prusa printers from Q-SYS through a
**Prusa Connect Local** server (Prusa's self-hosted printer server). One plugin
instance covers every printer on the server.

> **Status: untested on real hardware.** This plugin is built from Prusa
> Connect's documentation and checked with offline tests only. Prusa Connect
> is in public beta (0.x), and its API can still change. Reports and fixes are welcome.

For a single printer without a Connect server, use the PrusaLink plugin in
`../PrusaLink/` instead.

## Install

1. Copy `PrusaConnect.qplug` into your Q-SYS plugins folder
   (on Windows: `Documents\QSC\Q-Sys Designer\Plugins`).
2. Restart Q-SYS Designer, then drag **Prusa Connect** into your design.

## Setup

1. In the Prusa Connect web app, open **Settings → API credentials**, create a
   credential with **operate** access, and copy the token (`pcl_…`). Tokens
   expire after 90 days by default, so note the date.
2. In the plugin's **Setup** tab, enter:
   - **Server Address**: `host` or `host:port`. Port 8080 is used if you leave it off.
   - **API Token**: the token from step 1.

The online dot turns on once the server answers.

### Properties

| Property | Default | What it does |
|---|---|---|
| Poll Interval | 5 s | How often the printer list is refreshed (1–60). |
| Printer Slots | 6 | How many printer buttons the Farm tab has (1–8). Extra printers aren't shown. |
| Use HTTPS | off | Turn on if your server uses HTTPS. |
| Debug | off | Writes requests and results to the Q-SYS log. The routine printer-list poll is left out. |

## Pages

- **Farm:** one button per printer, sorted by name, with its status (e.g.
  `PRINTING 42%`, `IDLE`, `OFFLINE`). Press a button to select that printer. The
  orange strip shows the printer count, or a problem such as `Token rejected`.
- **Monitor:** status, job, progress, temperatures and the temperature graph
  for the selected printer. Its name is shown in the orange strip on this page,
  Files and Control.
  - **Click the knob** to swap the graph for the job's **progress picture**: the
    model starts greyed out and fills with colour from the bottom as it prints,
    with an orange line at the current height. The server may send the thumbnail
    as PNG or JPEG; both work.
- **Files:** the selected printer's files. Long names are shortened with "…".
  - Tap a file for a preview (picture and size); tap the preview to close it.
  - **Start Print**, **Pause/Resume** and **Stop** act on that printer.
  - **Delete** needs a second press within 5 seconds, and is blocked while
    printing or for read-only files.
- **Control:**
  - **Temperatures:** set the nozzle and bed targets, or use the **PLA** (215/60),
    **PETG** (240/85) and **Cooldown** presets.
  - **Jog** X/Y/Z by 0.1, 1 or 10 mm.
  - **Home** all axes, or turn the **Motors Off**.
  - Moving, homing and motors-off are refused while a print is running or paused.
  - The line at the bottom shows the result of the last command.

## First test on hardware

The documentation doesn't say whether Prusa Connect's move commands are
relative or absolute. Test jogging carefully the first time:

1. Pick an idle printer, then **Home**.
2. Raise the nozzle well clear of the bed.
3. Jog **Z+** with the **1 mm** step and watch which way it moves, and how far.

## Troubleshooting

| You see | Meaning |
|---|---|
| `Token rejected` | The token is wrong, expired or revoked. Make a new one. |
| `Token needs operate access` | The token is read-only. Make one with **operate** access. |
| `Server offline` | The server didn't answer. Check the address and port. |
| `Not supported by this printer` | That printer doesn't offer the command. |
| `Busy: printing` | Motion controls are blocked while printing. |

Turn on **Debug** to see each request in the Q-SYS log.

## For developers

The plugin is one Lua file, and its runtime code lives in the `PC` table. Offline
tests load the real `.qplug` with mocked Q-SYS globals:

```sh
apt-get install -y lua5.3 lua-dkjson
lua5.3 tests/run.lua          # from the repo root; runs PrusaLink and Prusa Connect tests
```

The design notes are in `docs/superpowers/specs/2026-11-20-prusa-connect-plugin-design.md`.
