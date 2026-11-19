# PrusaLink Plugin Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the PrusaLink Q-SYS plugin on the v1 API with digest auth. Keep the MINI-style look, and add delete confirmation, a file preview panel, and a Monitor page progress picture toggled by the knob.

**Architecture:** The plugin stays one `.qplug` file, so users still install a single file. Runtime logic lives in one global table `PL`, so an offline Lua test harness can load the real `.qplug` with mocked Q-SYS globals (`Controls`, `Timer`, `HttpClient`, `rapidjson`, `EzSVG`, `Crypto`, `Properties`) and drive it. Layout, colors and images come from v09.

**Tech Stack:** Q-SYS plugin Lua (5.3), `rapidjson`, `EzSVG`, `HttpClient` (`Auth = "digest"`). Tests run on `lua5.3` + `lua-dkjson` (apt).

**Spec:** `docs/superpowers/specs/2026-11-19-prusalink-plugin-rework-design.md`

## Global Constraints

- Target: PrusaLink **v1** API on Buddy firmware (MINI/MINI+, MK4/MK4S, Core One, XL). No MK3/Pi legacy API, no SL1.
- Every HTTP request uses `User`, `Password` and `Auth = "digest"`. No `X-Api-Key` anywhere.
- Username defaults to `maker`.
- Old files are moved with `git mv` into `.OLD/` and never edited or deleted.
- The look stays: page names `Monitor`, `Control`, `Setup`, the orange/black frame, images and positions from v09. New controls fit inside the existing frame.
- `PluginInfo.Id` stays `e778394d-6e3d-2489-be94-bcb44ts1c76e`. `Version = "1.0"`. `BuildVersion = "1.0.0.0"`.
- Existing control names are kept. `API Key` is removed.
- Properties: `Poll Interval` (integer seconds, 1–60, default 5) and `Debug` (boolean, default false). `print()` logging only when Debug is on, through `PL.log`.
- Delete confirmation: legend `"Confirm?"`, color `{179,38,30}`, 5 s window.
- Image paths come from the API's `refs.thumbnail`, falling back to `refs.icon`, used as given and never built by the plugin.
- The progress method is chosen by the Task 2 spike: 1 (single SVG), 2 (layered overlay) or 3 (vertical bar). **No ring gauge.**

## Review Focus

1. **Printer offline or timing out** (code 0 / nil body): Online goes off, Status shows `Offline`, there is no Lua error, and polling keeps going. Tested in Task 4.
2. **File names with spaces or special characters** (`my part.bgcode`): URL path segments are percent-encoded on print, delete and picture requests. Tested in Tasks 4 and 5.
3. **Same file name in two folders or storages**: both show up as distinct list entries, and each acts on its own file. Tested in Task 5.
4. **A response from the old printer arriving after the IP or credentials change**: it is ignored and doesn't overwrite fresh state. Tested in Task 4.
5. **Missing or renamed fields in `meta`/`refs`** (real firmware differing from the draft spec): fields are skipped, the details panel still renders, and nothing crashes. Tested in Tasks 5 and 8.

---

## File Structure

```
.OLD/                                  git mv of Prusa-Link_07/08/09.qplug and "Prusa Link Text Controller.qsys"
PrusaLink/PrusaLink.qplug              the plugin (starts as a copy of v09, then reworked)
PrusaLink/README.md                    install, setup, troubleshooting, dev/test instructions
spikes/PictureSpike.qplug              throwaway spike (Task 2), deleted in Task 10
tests/run.lua                          tiny runner: loads every tests/test_*.lua and runs each function
tests/mocks.lua                        mocked Q-SYS globals and helpers
tests/fixtures/*.json                  sample API responses shaped like the spec
tests/test_*.lua                       one file per task area
README.md                              repo overview linking both plugin folders
```

---

### Task 1: Repo reorganization and test harness

**Files:**
- Move: `Prusa-Link_07.qplug`, `Prusa-Link_08.qplug`, `Prusa-Link_09.qplug`, `Prusa Link Text Controller.qsys` → `.OLD/`
- Create: `PrusaLink/PrusaLink.qplug` (copy of `.OLD/Prusa-Link_09.qplug`)
- Create: `tests/run.lua`, `tests/mocks.lua`, `tests/test_load.lua`

**Interfaces:**
- Produces, in `tests/mocks.lua`:
  - `M.load(props)`: resets all globals and loads `PrusaLink/PrusaLink.qplug` with `Properties` built from `props` (a table `{["Poll Interval"]=5, Debug=false}`; missing keys use defaults). Returns nothing; afterwards the global `PL` exists.
  - `M.ctl(name)`: returns the mock control. Fields: `String`, `Value`, `Position`, `Boolean`, `IsInvisible`, `Legend`, `Color`, `Choices`, `EventHandler`. Writing `Value` keeps `String` in sync. `Position = Value / max` for knobs is not needed; tests set `Position` directly.
  - `M.press(name)`: calls the control's `EventHandler(ctl)`.
  - `M.requests`: array of `{Url, Method, User, Password, Auth, Headers, EventHandler}` recorded by `HttpClient.Download`.
  - `M.respond(i, code, body)`: calls request `i`'s `EventHandler(tbl, code, body, err)`. `code = 0` passes `err = "timeout"`.
  - `M.advance(seconds)`: fires due `Timer.CallAfter` callbacks and started `Timer` objects up to the virtual clock + seconds.
  - `M.logs`: array of printed lines.
  - `rapidjson` is mocked with dkjson (`encode`, `decode`), `Crypto.Base64Encode` with a pure-Lua encoder, and `EzSVG` with a stub whose `Document:toString()` returns `"<svg/>"` and whose other methods return self.
- `tests/run.lua`: `lua5.3 tests/run.lua` runs every `test_*` global function in every `tests/test_*.lua`, prints `PASS name`/`FAIL name: msg`, and exits 1 on any failure.

- [ ] **Step 1:** Install the test dependencies: `apt-get install -y lua5.3 lua-dkjson`. Expected: `lua5.3 -v` prints `Lua 5.3`.
- [ ] **Step 2:** Run `git mv` on the four old files into `.OLD/`, then `cp .OLD/Prusa-Link_09.qplug PrusaLink/PrusaLink.qplug`.
- [ ] **Step 3: Write the failing tests** in `tests/test_load.lua`:

```lua
function test_design_functions_run_for_every_page()
  M.load({})
  local ctrls = GetControls({})
  assert(#ctrls > 0)
  for i, page in ipairs({"Monitor","Control","Setup"}) do
    local layout, graphics = GetControlLayout({ page_index = { Value = i } })
    assert(type(layout) == "table" and type(graphics) == "table", page)
  end
end

function test_runtime_loads_and_exposes_PL()
  M.load({})
  assert(type(PL) == "table")
end
```

- [ ] **Step 4:** Run `lua5.3 tests/run.lua`. Expected: `test_runtime_loads_and_exposes_PL` FAILs because `PL` is nil.
- [ ] **Step 5:** Write `tests/run.lua` and `tests/mocks.lua` as specified. In `PrusaLink/PrusaLink.qplug`, add `PL = {}` as the first line inside `if Controls then`.
- [ ] **Step 6:** Run `lua5.3 tests/run.lua`. Expected: both PASS.
- [ ] **Step 7:** Commit: `git add -A && git commit -m "Move old plugins to .OLD, start PrusaLink/ and Lua test harness"`

---

### Task 2: Picture spike on the MINI (throwaway, needs the maintainer)

This task is manual and needs the maintainer's MINI in Q-SYS Designer. It can run in parallel with Tasks 3–7. Its result decides the method used in Task 9.

**Files:**
- Create: `spikes/PictureSpike.qplug`

The spike is a minimal plugin with one page:
- Text inputs: `IP`, `User` (default `maker`), `Password`, `Path`. The maintainer pastes a `refs.thumbnail` value taken from `http://<ip>/api/v1/files/usb/` in a browser.
- A `Fetch` button.
- Three 150×150 buttons, each with `DrawChrome=false` IconData:
  - `Plain`: the PNG as is.
  - `Method1`: a single SVG built by `spikeSvg1(b64, 40)`, with the PNG embedded twice. The grey copy uses `<filter><feColorMatrix type="saturate" values="0"/></filter>`; the orange copy is tinted with `feColorMatrix` and clipped by `<clipPath><rect y="60%" height="40%"/>`.
  - `Method2`: the `Plain` picture with a second same-size button on top, whose IconData is a transparent SVG with a rect `fill="#e05d2d" fill-opacity="0.55"` covering the bottom 40%.
- A `Log` text box. On fetch it prints: response code, body length, the `Content-Type` header if present, and whether `body:sub(1,8) == "\137PNG\r\n\26\n"`.

- [ ] **Step 1:** Write `spikes/PictureSpike.qplug`, check it with `luac5.3 -p spikes/PictureSpike.qplug`, and commit: `git commit -m "spike: picture fetch and progress render test"`.
- [ ] **Step 2 (maintainer):** Load it in Designer (emulate or Core), connect it to the MINI, fetch a thumbnail, and report what each of the three buttons shows plus the Log text.
- [ ] **Step 3:** Record the outcome in the spec under "Spike first": code, PNG yes/no, and which methods rendered. Set the chosen progress method: 1 if Method1 renders correctly, else 2 if Method2 does, else 3. Commit: `git commit -m "spec: record picture spike result"`.

---

### Task 3: Properties, Setup page auth fields, new controls

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug`: `PluginInfo`, `GetProperties`, `GetControls`, `GetControlLayout` (Setup, Control and Monitor branches)
- Test: `tests/test_design.lua`

**Interfaces:**
- Produces these controls (layout positions are inside the existing frame; small nudges allowed):
  - `Username` (Text, Setup, where `API Key` was, `{65,120}` 160×30)
  - `Password` (Text, Setup, below Username, `{65,155}` 160×30)
  - `Preview` (Button Trigger, Control, `{31,66}` 228×217, ZOrder above `Files`, starts invisible): the panel and its tap target
  - `Preview Image` (Button, read-only, inside the panel left `{37,80}` 118×118)
  - `Preview Details` (Text, read-only, inside the panel right `{159,80}` 96×190, no background)
  - `Progress Image` (Button, read-only, Monitor, `{44,160}` 222×155, starts invisible)
  - `Progress Overlay` (Button, read-only, same rect, ZOrder above `Progress Image`, starts invisible; used only by methods 2/3)
  - `View Toggle` (Button Trigger, Monitor, `{99,431}` 87×87, flat, fully transparent, ZOrder above the knob image)

- [ ] **Step 1: Write the failing tests** in `tests/test_design.lua`:

```lua
local function names(ctrls) local s = {} for _, c in ipairs(ctrls) do s[c.Name] = c end return s end

function test_plugin_info()
  M.load({})
  assert(PluginInfo.Version == "1.0" and PluginInfo.BuildVersion == "1.0.0.0")
  assert(PluginInfo.Id == "e778394d-6e3d-2489-be94-bcb44ts1c76e")
end

function test_properties()
  local p = {} for _, x in ipairs(GetProperties()) do p[x.Name] = x end
  assert(p["Poll Interval"].Value == 5 and p["Poll Interval"].Min == 1 and p["Poll Interval"].Max == 60)
  assert(p["Debug"].Value == false)
end

function test_controls_added_and_api_key_removed()
  local s = names(GetControls({}))
  for _, n in ipairs({"Username","Password","Preview","Preview Image","Preview Details",
                      "Progress Image","Progress Overlay","View Toggle"}) do assert(s[n], n) end
  assert(s["API Key"] == nil)
end

function test_existing_controls_kept()
  local s = names(GetControls({}))
  for _, n in ipairs({"Print","Pause","Stop","Delete","Online","nGraph","bGraph","Job","Progress",
                      "Status","Material","Printer IP","Nozzle Temp","Nozzle Target","Bed Temp",
                      "Bed Target","Z Height","Print Speed","Files"}) do assert(s[n], n) end
end

function test_username_defaults_to_maker()
  M.load({})
  assert(M.ctl("Username").String == "maker")
end
```

- [ ] **Step 2:** Run `lua5.3 tests/run.lua`. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement the changes. Username's default is set at runtime start: if empty, set it to `"maker"`. Remove the dead `getUSER`/`getPASS`/`getKEY` helpers and the `API Key` handlers.
- [ ] **Step 4:** Run the tests. Expected: all PASS.
- [ ] **Step 5:** Commit: `git commit -am "Add properties, digest auth fields and new controls"`

---

### Task 4: Request helper, state, polling, status/job parsing

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug` runtime: replace `Printer`/`Info`/`Job`/`Poll`/`PrinterParse`/`JobParse`/`InfoParse`
- Create: `tests/fixtures/status_printing.json`, `tests/fixtures/job_printing.json`
- Test: `tests/test_core.lua`

**Interfaces:**
- Produces:
  - `PL.State`: `{ gen=int, jobId=int|nil, state=string, progress=number|nil, jobRefs=table|nil, files={}, readOnly={}, selected=string|nil, deleteArmed=bool, view="graph"|"progress", pictures={} }`
  - `PL.log(...)`: prints only when the `Debug` property is true.
  - `PL.encodePath(path) -> string`: percent-encodes each `/`-separated segment (RFC 3986 unreserved chars kept), keeping the slashes.
  - `PL.request{ method, path, raw, onOk, onError }`:
    - Url is `"http://"..ip..path`, with `User`, `Password`, `Auth="digest"` and `Timeout=5`.
    - Callbacks are dropped if `PL.State.gen` changed since the call.
    - 401: Status `"Auth failed"`, Online hidden, `onError(401)`.
    - code 0/nil: Status `"Offline"`, Online hidden, `onError(0)`.
    - 2xx: `onOk(code, json_or_nil, body)`. JSON is decoded with pcall unless `raw` is set or the body is empty.
    - Other codes: `onError(code)`.
  - `PL.poll()`: GETs `/api/v1/status` and `/api/v1/job`.
  - `PL.parseStatus(json)`: sets Status/temps/targets/speed/Z (`printer.state`, `temp_nozzle`, `target_nozzle`, `temp_bed`, `target_bed`, `speed`, `axis_z`) and shows Online.
  - `PL.parseJob(code, json)`:
    - 204: Job `"No Current Job"`, Progress `""`, `jobId=nil`, `progress=nil`, `jobRefs=nil`.
    - 200: `jobId=id`, Job = `file.display_name or file.name`, Progress `"%.0f%%"`, `progress`, `jobRefs = file.refs`, and Material = `file.meta.filament_type` when present.
    - Calls `PL.onProgress()` if it is defined (Task 9 defines it).
  - `PL.reset()`: `gen+1`, clears state (keeps `view`), clears Files choices and the picture cache, then `PL.poll()`, `PL.connectInfo()` and `PL.refreshFiles()` (refreshFiles comes in Task 5; guard with `if PL.refreshFiles`).
  - `PL.connectInfo()`: GETs `/api/version` and `/api/v1/info` and logs both.
  - The poll timer interval is `Properties["Poll Interval"].Value`.
  - `Printer IP`, `Username` and `Password` EventHandlers call `PL.reset()`.

- [ ] **Step 1: Write the failing tests** in `tests/test_core.lua`:

```lua
function test_request_uses_digest_auth()
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; M.ctl("Password").String = "pw"
  PL.request{ method="GET", path="/api/v1/status" }
  local r = M.requests[#M.requests]
  assert(r.Url == "http://10.0.0.5/api/v1/status" and r.User == "maker" and r.Password == "pw" and r.Auth == "digest")
  assert(r.Headers == nil or r.Headers["X-Api-Key"] == nil)
end

function test_401_shows_auth_failed()
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; PL.poll()
  M.respond(1, 401, "")
  assert(M.ctl("Status").String == "Auth failed" and M.ctl("Online").IsInvisible == true)
end

function test_offline_does_not_error_and_polling_continues()  -- Review Focus 1
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; M.advance(5)
  local n = #M.requests
  M.respond(1, 0, nil)
  assert(M.ctl("Status").String == "Offline")
  M.advance(5); assert(#M.requests > n)
end

function test_status_parse()
  M.load({}); PL.parseStatus(rapidjson.decode(M.fixture("status_printing.json")))
  assert(M.ctl("Status").String == "PRINTING" and M.ctl("Nozzle Temp").Value == 215 and M.ctl("Bed Target").Value == 60)
  assert(M.ctl("Online").IsInvisible == false)
end

function test_job_204_and_200()
  M.load({}); PL.parseJob(204, nil)
  assert(M.ctl("Job").String == "No Current Job" and PL.State.jobId == nil)
  PL.parseJob(200, rapidjson.decode(M.fixture("job_printing.json")))
  assert(PL.State.jobId == 297 and M.ctl("Progress").String == "42%" and PL.State.jobRefs.thumbnail)
end

function test_stale_response_after_ip_change_is_ignored()  -- Review Focus 4
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; PL.poll()
  M.ctl("Printer IP").String = "10.0.0.6"; M.press("Printer IP")
  M.respond(1, 200, M.fixture("status_printing.json"))
  assert(M.ctl("Status").String ~= "PRINTING")
end

function test_encode_path()  -- Review Focus 2
  assert(PL.encodePath("/usb/my part (v2).bgcode") == "/usb/my%20part%20%28v2%29.bgcode")
end

function test_poll_interval_property()
  M.load({["Poll Interval"]=10}); M.ctl("Printer IP").String = "10.0.0.5"
  local n = #M.requests; M.advance(5); assert(#M.requests == n); M.advance(5); assert(#M.requests > n)
end

function test_debug_off_is_silent()
  M.load({Debug=false}); PL.log("x"); assert(#M.logs == 0)
end
```

`M.fixture(name)` (add it to mocks) reads `tests/fixtures/<name>`. Fixture `status_printing.json`: `printer.state="PRINTING"`, `temp_nozzle=215`, `target_nozzle=215`, `temp_bed=60`, `target_bed=60`, `speed=100`, `axis_z=8.4`. Fixture `job_printing.json`: `id=297`, `progress=42`, `state="PRINTING"`, `file.display_name="bracket_v3_PLA.bgcode"`, `file.refs.thumbnail="/thumb/l/usb/BRACKE~1.BGC"`, `file.refs.icon="/thumb/s/usb/BRACKE~1.BGC"`.

- [ ] **Step 2:** Run the tests. Expected: the new tests FAIL.
- [ ] **Step 3:** Implement as specified in Interfaces. Remove the old functions this replaces.
- [ ] **Step 4:** Run the tests. Expected: all PASS.
- [ ] **Step 5:** Commit: `git commit -am "Core: digest request helper, state, polling, status/job parsing"`

---

### Task 5: File listing

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug` runtime: replace `Files`/`StorageParse`/`FilesParse`/`processFolder`
- Create: `tests/fixtures/storage.json`, `tests/fixtures/files_usb.json`, `tests/fixtures/files_local.json`
- Test: `tests/test_files.lua`

**Interfaces:**
- Consumes: `PL.request`, `PL.State`.
- Produces:
  - `PL.refreshFiles()`: GET `/api/v1/storage`, then for each `available` storage GET `/api/v1/files` + `encodePath(storage.path)` + `/`. It records `readOnly[storageName] = read_only`.
  - `PL.walkFolder(node, storage, base, out)`: appends `{ key, storage, path, refs, meta, name }` for each `PRINT_FILE`, recursing into folders.
    - `path` uses `display_name or name` per segment.
    - `key` = relative path without `.gcode`/`.bgcode` (`"parts/bracket"`; root files are just `"bracket"`).
  - `PL.applyFiles()`: rebuilds `Files.Choices` from `PL.State.files` in insertion order. If a key already exists from another storage, the later one gets the suffix `" (" .. storage .. ")"`.
  - Entries are stored in `PL.State.files[key]`.

- [ ] **Step 1: Write the failing tests:**

```lua
function test_walk_folder_nested_keys_and_refs()
  M.load({}); local out = {}
  PL.walkFolder(rapidjson.decode(M.fixture("files_usb.json")), "usb", "", out)
  assert(out[1].key == "bracket_v3_PLA" and out[1].path == "/bracket_v3_PLA.bgcode" and out[1].refs.thumbnail)
  assert(out[2].key == "parts/clip" and out[2].path == "/parts/clip.gcode")
end

function test_duplicate_names_across_storages_are_distinct()  -- Review Focus 3
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; PL.refreshFiles()
  M.respond(1, 200, M.fixture("storage.json"))   -- usb + local
  M.respond(2, 200, M.fixture("files_usb.json")); M.respond(3, 200, M.fixture("files_local.json"))
  local c = M.ctl("Files").Choices
  assert(PL.State.files["bracket_v3_PLA"].storage == "usb" and PL.State.files["bracket_v3_PLA (local)"].storage == "local")
end

function test_missing_refs_and_meta_do_not_crash()  -- Review Focus 5
  M.load({}); local out = {}
  PL.walkFolder({ children = { { name = "a.gcode", type = "PRINT_FILE" } } }, "usb", "", out)
  assert(out[1].key == "a" and out[1].refs == nil)
end

function test_storage_folder_url_is_encoded()
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; PL.refreshFiles()
  M.respond(1, 200, '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}')
  assert(M.requests[2].Url == "http://10.0.0.5/api/v1/files/usb/")
end
```

Fixture `files_usb.json` holds the root file `bracket_v3_PLA.bgcode` (with `refs` and `meta`: `filament_type="PLA"`, `layer_height=0.2`, `estimated_print_time=6120`, `nozzle_diameter=0.4`, `"filament used [g]"=12.6`), and a folder `parts` containing `clip.gcode`. Fixture `files_local.json` holds `bracket_v3_PLA.bgcode`.

- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "Files: storage walk with refs/meta, distinct keys, encoded URLs"`

---

### Task 6: Job actions (print, pause/resume, stop)

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug`: `Print`, `Pause`, `Stop` handlers
- Test: `tests/test_actions.lua`

**Interfaces:**
- Consumes: `PL.request`, `PL.State.files`, `PL.State.selected`, `PL.State.jobId`, `PL.State.state`, `PL.encodePath`.
- Produces: `PL.selectedEntry() -> entry|nil` (from `PL.State.selected`, which Task 8 sets on file selection; for now set by the `Files` EventHandler to `Files.String`).
  - Print: `POST /api/v1/files/{storage}{encoded path}`.
  - Pause: `PUT /api/v1/job/{id}/pause` when PRINTING; `PUT /api/v1/job/{id}/resume` when PAUSED; otherwise no request.
  - Stop: `DELETE /api/v1/job/{id}`.
  - After any 2xx, call `PL.poll()` 0.3 s later. After Stop, call `PL.refreshFiles()` 1 s later.

- [ ] **Step 1: Write the failing tests:**
  - `test_print_posts_encoded_path`: with an entry for `"/my part.bgcode"` on `usb` selected, press Print. The last request is `POST http://10.0.0.5/api/v1/files/usb/my%20part.bgcode`.
  - `test_pause_resume_by_state`: with state `PRINTING` and jobId 297, the request is `PUT .../job/297/pause`. With `PAUSED`, it is `.../resume`. With `IDLE`, no request.
  - `test_stop_deletes_job`: with jobId 297, the request is `DELETE .../job/297`.
  - `test_no_selection_no_request`: Print with nothing selected → the request count is unchanged.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "Job actions via request helper"`

---

### Task 7: Delete with confirmation

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug`: `Delete` handler
- Test: `tests/test_delete.lua`

**Interfaces:**
- Consumes: `PL.selectedEntry`, `PL.State`, `PL.request`, `PL.closePreview` (defined in Task 8; call it only if present).
- Produces:
  - `PL.disarmDelete()`: restores legend `"Delete"` and the original color, and sets `deleteArmed=false`.
  - First press (with a selection, not PRINTING/PAUSED, storage not read-only): arm. Set legend `"Confirm?"`, color `{179,38,30}`, and start a 5 s timer that disarms.
  - Second press while armed: **re-check the same guards**, then `DELETE /api/v1/files/{storage}{encoded path}`, then disarm.
  - On 204: remove the entry from `PL.State.files` and `Files.Choices`, then close the preview.
  - Changing the file selection disarms.

- [ ] **Step 1: Write the failing tests:**
  - `test_first_press_arms_without_request`: legend is `"Confirm?"`, no new request.
  - `test_second_press_deletes_and_removes_from_list`: request is `DELETE .../files/usb/bracket_v3_PLA.bgcode`; respond 204 → the key is gone from `Files.Choices` and the legend is back to `"Delete"`.
  - `test_timeout_disarms`: `M.advance(5.1)` → legend `"Delete"`; the next press only arms again.
  - `test_selection_change_disarms`.
  - `test_blocked_while_printing_even_if_armed_before`: arm, set state to PRINTING, press again → no DELETE request.
  - `test_read_only_storage_never_arms`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "Delete requires confirmation within 5 s"`

---

### Task 8: File preview panel (Control page)

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug`: `Files` and `Preview` handlers, picture fetch
- Test: `tests/test_preview.lua`

**Interfaces:**
- Consumes: `PL.State.files`, `PL.request{raw=true}`, `PL.disarmDelete`.
- Produces:
  - `PL.formatDuration(sec) -> string`: `6120 → "1h 42m"`, `2700 → "45m"`, `30 → "<1m"`, `nil → nil`.
  - `PL.fileDetails(entry) -> string`: newline-joined lines, each only if its value is present, in this order:
    - name (`entry.key`'s last segment),
    - `meta.filament_type`,
    - `string.format("%.2f mm", meta.layer_height)`,
    - `formatDuration(meta.estimated_print_time)`,
    - `string.format("%.1f mm nozzle", meta.nozzle_diameter)`,
    - `string.format("%.1f g", meta["filament used [g]"])`.
  - `PL.fetchPicture(refs, cb)`: picks `refs.thumbnail or refs.icon`. If it's nil, calls `cb(nil)`. If the path is cached in `PL.State.pictures`, calls `cb(b64)` with no request. Otherwise it GETs the path with `raw=true` and caches and returns `Crypto.Base64Encode(body)`; on error it calls `cb(nil)`.
  - `PL.setIcon(ctlName, b64)`: sets `Legend = rapidjson.encode({DrawChrome=false, IconData=b64 or ""})`.
  - `PL.openPreview(key)`: sets `selected=key`, disarms delete, makes `Preview`, `Preview Image` and `Preview Details` visible, sets the details text, then fetches the picture into `Preview Image`.
  - `PL.closePreview()`: hides the three panel controls.
  - The `Files` EventHandler calls `PL.openPreview(Files.String)`; the `Preview` EventHandler calls `PL.closePreview()`.
  - `PL.applyFiles` (Task 5) calls `closePreview()` if the selected key no longer exists.

- [ ] **Step 1: Write the failing tests:**
  - `test_format_duration` with the four values above.
  - `test_file_details_full`: for the `bracket_v3_PLA` fixture → `"bracket_v3_PLA\nPLA\n0.20 mm\n1h 42m\n0.4 mm nozzle\n12.6 g"`.
  - `test_file_details_missing_meta` (Review Focus 5): an entry with no `meta` → `"bracket_v3_PLA"`.
  - `test_select_opens_panel_and_fetches_thumbnail`: request Url ends with `/thumb/l/usb/BRACKE~1.BGC`. Respond `200` with body `"\137PNG\r\n\26\nX"` → the `Preview Image` Legend decodes to `IconData == Crypto.Base64Encode(body)`.
  - `test_second_select_uses_cache`: no new request.
  - `test_tap_closes_panel`.
  - `test_no_refs_opens_panel_without_request`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "File preview panel with picture and details"`

---

### Task 9: Progress picture and knob toggle (Monitor page)

Implement **only the method recorded by Task 2**. If Task 2 hasn't finished, stop and wait.

**Files:**
- Modify: `PrusaLink/PrusaLink.qplug`: graph and timer section, Monitor runtime
- Test: `tests/test_progress.lua`

**Interfaces:**
- Consumes: `PL.State.progress`, `PL.State.jobRefs`, `PL.fetchPicture`, `PL.setIcon`.
- Produces:
  - `PL.setView(v)`, where `v` is `"graph"` or `"progress"`:
    - `"graph"`: `nGraph`/`bGraph` visible; `Progress Image`/`Progress Overlay` hidden, along with the graph's °C axis labels if they are controls. (They are graphics, so they stay visible. Accept that.)
    - `"progress"`: the reverse.
    - Stores the view in `PL.State.view`.
  - `View Toggle` EventHandler flips the view. The initial view is `"graph"`.
  - `PL.onProgress()` (called by `parseJob`): if `progress` and `jobRefs` haven't changed since the last render, it does nothing. Otherwise it fetches the picture and renders it with the chosen method:
    - **Method 1:** `PL.progressSvg(b64, pct) -> string`: the SVG from the spike, with a clip rect `y = H*(1-pct/100)` and `height = H*pct/100`, where H = 155. Set it on `Progress Image` via `setIcon(…, Crypto.Base64Encode(svg))`.
    - **Method 2:** the picture goes on `Progress Image`. `PL.overlaySvg(pct) -> string`: a transparent 222×155 SVG with an orange rect (`#e05d2d`, opacity 0.55) of the same clip geometry, set on `Progress Overlay`.
    - **Method 3:** the picture goes on `Progress Image`, scaled into the left 190 px. `PL.barSvg(pct) -> string`: a 222×155 SVG with a vertical bar at `x=200..216` (track `#333`, fill `#e05d2d` from the bottom, height `155*pct/100`), set on `Progress Overlay`.
  - No job: `Progress Image` is cleared, and the `Job` text already shows `"No Current Job"`.
  - The temperature sampling timers keep running regardless of view.

- [ ] **Step 1: Write the failing tests:**
  - `test_toggle_switches_views`: initially `nGraph.IsInvisible == false` and `Progress Image.IsInvisible == true`; press `View Toggle` → reversed; press again → back.
  - `test_progress_svg_geometry` (for the chosen method's function): at 40% the SVG string contains `y="93"` and `height="62"`; at 0%, `height="0"`; at 100%, `y="0"`.
  - `test_same_progress_does_not_refetch_or_rerender`: calling `parseJob` twice with the same fixture → one picture request and one Legend write.
  - `test_samples_continue_in_progress_view`: in progress view, after `M.advance(3)` the nozzle samples array has grown by 3.
  - `test_no_job_clears_picture`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement the chosen method only.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `git commit -am "Monitor progress picture (method N) with knob toggle"`

---

### Task 10: Docs, cleanup and hardware check

**Files:**
- Create: `PrusaLink/README.md`
- Modify: `README.md`
- Delete: `spikes/`

- [ ] **Step 1:** Write `PrusaLink/README.md`. Cover:
  - supported printers and firmware (v1 API, Buddy firmware),
  - install (copy `PrusaLink.qplug` to the Q-SYS plugins folder),
  - setup: IP, the username `maker`, and where to find the password on the printer (Settings → Network → PrusaLink),
  - the Properties,
  - each page and its controls, including delete confirmation, the preview tap and the knob toggle,
  - troubleshooting: Auth failed, Offline, no picture,
  - dev: `apt-get install lua5.3 lua-dkjson` and `lua5.3 tests/run.lua`.
- [ ] **Step 2:** Update the root `README.md`: what's in the repo (`PrusaLink/`, the planned `PrusaConnect/`, `.OLD/`).
- [ ] **Step 3:** `git rm -r spikes/`. Then run `luac5.3 -p PrusaLink/PrusaLink.qplug && lua5.3 tests/run.lua`. Expected: no syntax errors, all PASS.
- [ ] **Step 4:** Commit: `git commit -am "Docs and cleanup for PrusaLink 1.0"`
- [ ] **Step 5 (maintainer):** Run the spec's hardware checklist on the MINI: connect, bad password, file list, preview open and close plus picture, print, pause/resume, stop, delete (confirm and timeout), the progress picture filling during a print, the knob toggle, and graphs. Report failures. Each one becomes a fix with a regression test in the relevant test file.
