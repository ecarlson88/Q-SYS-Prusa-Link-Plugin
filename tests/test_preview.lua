-- File preview panel: picture + details over the file list.

local PNG = "\137PNG\r\n\26\nX"

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5)
  local out = {}
  PL.walkFolder(rapidjson.decode(M.fixture("files_usb.json")), "usb", "", out)
  for _, e in ipairs(out) do PL.State.files[e.key] = e; PL.State.order[#PL.State.order + 1] = e.key end
  PL.State.files["bare"] = { key = "bare", name = "bare", storage = "usb", path = "/bare.gcode" }
  PL.State.order[#PL.State.order + 1] = "bare"
  PL.applyFiles()
end

local function select(key) M.ctl("Files").String = key; M.press("Files") end
local function panelOpen()
  return not M.ctl("Preview").IsInvisible and not M.ctl("Preview Image").IsInvisible
     and not M.ctl("Preview Details").IsInvisible
end
local function thumbRequests() return M.count("/thumb/") end

function test_panel_hidden_at_start()
  M.load({})
  assert(M.ctl("Preview").IsInvisible and M.ctl("Preview Image").IsInvisible and M.ctl("Preview Details").IsInvisible)
end

function test_format_duration()
  M.load({})
  assert(PL.formatDuration(6120) == "1h 42m", PL.formatDuration(6120))
  assert(PL.formatDuration(2700) == "45m")
  assert(PL.formatDuration(30) == "<1m")
  assert(PL.formatDuration(nil) == nil)
end

function test_file_details_full()
  setup()
  local d = PL.fileDetails(PL.State.files["bracket_v3_PLA"])
  assert(d == "bracket_v3_PLA\nPLA\n0.20 mm\n1h 42m\n0.4 mm nozzle\n12.6 g", d)
end

function test_file_details_missing_meta()  -- Review Focus 5
  setup()
  assert(PL.fileDetails(PL.State.files["parts/clip"]) == "clip")
  assert(PL.fileDetails({ key = "x", meta = { layer_height = "oops" } }) == "x")
end

function test_select_opens_panel_and_fetches_thumbnail()
  setup(); select("bracket_v3_PLA")
  assert(panelOpen())
  assert(M.ctl("Preview Details").String:find("PLA", 1, true))
  local r = M.last()
  assert(r.Url == "http://10.0.0.5/thumb/l/usb/BRACKE~1.BGC" and r.Auth == "digest", r.Url)
  M.respond(#M.requests, 200, PNG)
  assert(M.legendIcon("Preview Image") == M.base64(PNG))
end

function test_icon_used_when_no_thumbnail()
  setup()
  PL.State.files["parts/clip"].refs = { icon = "/thumb/s/usb/PARTS/CLIP~1.GCO" }
  select("parts/clip")
  assert(M.last().Url:find("/thumb/s/usb/PARTS/CLIP~1.GCO", 1, true))
end

function test_second_select_uses_cache()
  setup(); select("bracket_v3_PLA"); M.respond(#M.requests, 200, PNG)
  local n = thumbRequests()
  M.press("Preview")
  select("bracket_v3_PLA")
  assert(thumbRequests() == n)
  assert(M.legendIcon("Preview Image") == M.base64(PNG))
end

function test_tap_closes_panel()
  setup(); select("bracket_v3_PLA")
  M.press("Preview")
  assert(M.ctl("Preview").IsInvisible and M.ctl("Preview Image").IsInvisible and M.ctl("Preview Details").IsInvisible)
end

function test_no_refs_opens_panel_without_request()
  setup(); local n = thumbRequests()
  select("bare")
  assert(panelOpen() and thumbRequests() == n)
  assert(M.legendIcon("Preview Image") == "")
end

function test_failed_fetch_leaves_picture_blank()
  setup(); select("bracket_v3_PLA")
  M.respond(#M.requests, 404, "")
  assert(panelOpen() and M.legendIcon("Preview Image") == "")
end

function test_late_picture_for_other_file_is_ignored()
  setup(); select("bracket_v3_PLA")
  local first = #M.requests
  M.press("Preview"); select("bare")
  M.respond(first, 200, PNG)
  assert(M.legendIcon("Preview Image") == "")
end

function test_successful_delete_closes_panel()
  setup(); PL.State.state = "IDLE"; PL.State.readOnly = { usb = false }
  select("bracket_v3_PLA")
  M.press("Delete"); M.press("Delete")
  M.respond(M.find("/api/v1/files/usb/BRACKE~1.BGC"), 204, "")
  assert(M.ctl("Preview").IsInvisible)
end
