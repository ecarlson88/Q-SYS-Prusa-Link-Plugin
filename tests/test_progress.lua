-- Monitor page: progress picture (method 1) and the knob view toggle.

local AXIS = { "Axis 300C", "Axis 225C", "Axis 150C", "Axis 75C", "Axis 0C" }

-- 220x124 PNG header (signature + IHDR) followed by filler bytes.
local function png(w, h)
  local function be32(n) return string.char((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255) end
  return "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(w) .. be32(h) .. "\8\6\0\0\0" .. "XXXX"
end

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5); M.settle()
end

local function job(progress, id)
  local j = rapidjson.decode(M.fixture("job_printing.json"))
  j.progress = progress; j.id = id or j.id
  return j
end

local function graphShown()
  if M.ctl("nGraph").IsInvisible or M.ctl("bGraph").IsInvisible then return false end
  for _, a in ipairs(AXIS) do if M.ctl(a).IsInvisible then return false end end
  return true
end

local function graphHidden()
  if not M.ctl("nGraph").IsInvisible or not M.ctl("bGraph").IsInvisible then return false end
  for _, a in ipairs(AXIS) do if not M.ctl(a).IsInvisible then return false end end
  return true
end

function test_toggle_switches_views()
  setup()
  assert(graphShown() and M.ctl("Progress Image").IsInvisible == true and PL.State.view == "graph")
  M.press("View Toggle")
  assert(graphHidden() and M.ctl("Progress Image").IsInvisible == false and PL.State.view == "progress")
  M.press("View Toggle")
  assert(graphShown() and M.ctl("Progress Image").IsInvisible == true)
  assert(M.ctl("Progress Overlay").IsInvisible == true, "method 1 doesn't use the overlay")
end

function test_progress_svg_geometry_full_box()
  M.load({})
  local svg = PL.progressSvg("QUJD", 40)
  assert(svg:find('id="done"><rect x="0" y="93" width="222" height="62"', 1, true), svg)
  assert(svg:find('id="todo"><rect x="0" y="0" width="222" height="93"', 1, true), svg)
  assert(PL.progressSvg("QUJD", 0):find('id="done"><rect x="0" y="155" width="222" height="0"', 1, true))
  assert(PL.progressSvg("QUJD", 100):find('id="done"><rect x="0" y="0" width="222" height="155"', 1, true))
end

function test_progress_svg_tracks_picture_height()
  M.load({})
  -- 220x124 fits 222x155 as 222 x 125.1, centred: top 14.9, bottom 170-ish -> 50% edge at 77.5
  local svg = PL.progressSvg("QUJD", 50, 220, 124)
  assert(svg:find('id="done"><rect x="0" y="77.5"', 1, true), svg)
  assert(svg:find('<line x1="0" y1="77.5" x2="222" y2="77.5"', 1, true), "orange edge line")
end

function test_progress_svg_style_is_pronounced()
  M.load({})
  local svg = PL.progressSvg("QUJD", 40)
  assert(svg:find('feColorMatrix type="saturate" values="0"', 1, true), "unprinted part greyscale")
  assert(svg:find('opacity="0.35"', 1, true), "unprinted part dimmed")
  assert(svg:find('data:image/png;base64,QUJD', 1, true))
  assert(not PL.progressSvg("QUJD", 0):find("<line", 1, true), "no edge line at 0%")
  assert(not PL.progressSvg("QUJD", 100):find("<line", 1, true), "no edge line at 100%")
end

function test_job_progress_renders_picture()
  setup()
  PL.parseJob(200, job(40))
  M.respondTo("/thumb/l/usb/BRACKE~1.BGC", 200, png(220, 124))
  local icon = M.legendIcon("Progress Image")
  assert(icon and icon ~= "", "picture drawn")
  assert(PL.lastProgressSvg and PL.lastProgressSvg:find('y1="90"', 1, true), PL.lastProgressSvg)
end

function test_same_progress_does_not_refetch_or_rerender()
  setup()
  PL.parseJob(200, job(40))
  M.respondTo("/thumb/l/usb/BRACKE~1.BGC", 200, png(220, 124))
  M.settle()
  local n = M.count("/thumb/")
  M.ctl("Progress Image").Legend = "unchanged"
  PL.parseJob(200, job(40))
  assert(M.count("/thumb/") == n and M.ctl("Progress Image").Legend == "unchanged")
  PL.parseJob(200, job(41))
  assert(M.count("/thumb/") == n, "picture is cached")
  assert(M.ctl("Progress Image").Legend ~= "unchanged", "new progress redraws")
end

function test_no_job_clears_picture()
  setup()
  PL.parseJob(200, job(40))
  M.respondTo("/thumb/l/usb/BRACKE~1.BGC", 200, png(220, 124))
  PL.parseJob(204, nil)
  assert(M.legendIcon("Progress Image") == "")
end

function test_samples_continue_in_progress_view()
  setup()
  M.press("View Toggle")
  M.ctl("Nozzle Temp").Position = 0.66
  M.advance(1)
  assert(nvalues[#nvalues] == 0.66)
end

-- A print already running when the plugin connects: the first job poll draws
-- the progress picture without waiting for the progress to change.
function test_progress_picture_drawn_for_print_already_running_at_connect()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5)                                    -- startup reset: status, job, version, info, files
  M.answerUntil("/api/v1/job", 200, M.fixture("job_printing.json"))
  M.answerUntil("/thumb/l/usb/BRACKE~1.BGC", 200, png(220, 124))
  M.settle()
  assert(M.ctl("Progress").String == "42%")
  assert(PL.lastProgressSvg and PL.lastProgressSvg:find('y1="87.5"', 1, true), "drawn at 42%")
  M.press("View Toggle")
  assert(M.ctl("Progress Image").IsInvisible == false and M.legendIcon("Progress Image") ~= "")
end
