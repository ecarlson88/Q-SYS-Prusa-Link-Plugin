# Q-SYS Prusa printer plugins

Q-SYS plugins for monitoring and controlling Prusa 3D printers. They started
as a project to learn Q-SYS plugin programming and to try drawing EzSVG graphs
of hotend and bed temperatures.

| Folder | Plugin | Use it when |
|---|---|---|
| [`PrusaLink/`](PrusaLink/) | **Prusa Link** | You want to control one printer directly over its PrusaLink API (MINI, MK4, Core One, XL). |
| [`PrusaConnect/`](PrusaConnect/) | **Prusa Connect** | You run a Prusa Connect Local server and want one panel for the whole farm. *Untested on hardware.* |

Each folder has a README with install and setup steps.

Other folders:

- `imgs/`: source images used in the plugin graphics.
- `tests/`: offline Lua tests for both plugins (`lua5.3 tests/run.lua`).
- `docs/superpowers/`: design notes and build plans.
- `.OLD/`: the earlier versions (v0.7–v0.9) of the PrusaLink plugin, kept for reference.
