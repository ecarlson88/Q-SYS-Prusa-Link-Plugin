-- Prusa Connect: PrusaLink fixes carried over after the fork.

local PNG_HDR = function(w, h)
  local function be32(n) return string.char((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255) end
  return "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(w) .. be32(h) .. "\8\6\0\0\0" .. "XXXX"
end
local JPEG = "\255\216\255\224" .. "JFIFDATA"
local AXIS = { "Axis 300C", "Axis 225C", "Axis 150C", "Axis 75C", "Axis 0C" }

local function connect(props)
  M.loadConnect(props or {})
  M.ctl("Server Address").String = "10.0.0.9"
  M.ctl("API Token").String = "pcl_abc_secret"
  M.advance(1.5); M.settle()
end

local function farm(props)
  connect(props)
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
end

local function layout(pageName)
  local idx = ({ Farm = 1, Monitor = 2, Files = 3, Control = 4, Setup = 5 })[pageName]
  return GetControlLayout({ page_index = { Value = idx }, ["Printer Slots"] = { Value = 6 } })
end

-- Queue -------------------------------------------------------------------

function test_cport_queue_survives_a_failing_callback()
  connect()
  PC.request{ path = "/a", onOk = function() error("boom") end }
  PC.request{ path = "/b" }
  M.respondTo("/a", 200, "{}")
  assert(M.last().Url == "http://10.0.0.9:8080/b")
end

function test_cport_shared_get_answers_every_caller()
  connect()
  PC.request{ path = "/busy" }
  local got = 0
  PC.request{ path = "/same", onOk = function() got = got + 1 end }
  PC.request{ path = "/same", onOk = function() got = got + 1 end }
  M.respondTo("/busy", 200, ""); M.respondTo("/same", 200, "{}")
  assert(got == 2 and M.count("/same") == 1)
end

function test_cport_debug_skips_routine_farm_poll()
  connect({ Debug = true })
  PC.pollFarm(); M.settle()
  for _, l in ipairs(M.logs) do assert(not l:find("/api/v1/devices?limit", 1, true), l) end
end

-- Layout ------------------------------------------------------------------

function test_cport_layout_fixes()
  M.loadConnect({})
  local mon, files = layout("Monitor"), layout("Files")
  assert(mon["Print Speed"].Size[1] >= 46 and mon["Print Speed"].FontSize <= 14)
  local z
  for _, c in ipairs(GetControls({})) do if c.Name == "Z Height" then z = c end end
  assert(z.ControlUnit == "Float" and z.Max >= 400)
  local list, panel = files["Files"], files["Preview"]
  assert(panel.Position[1] < list.Position[1] and panel.Position[2] < list.Position[2])
  assert(panel.Position[1] + panel.Size[1] > list.Position[1] + list.Size[1])
  assert(panel.Position[2] + panel.Size[2] > list.Position[2] + list.Size[2])
end

-- Files -------------------------------------------------------------------

function test_cport_long_names_shortened_and_open_the_right_file()
  farm(); M.press("Printer 3"); M.settle()   -- MK4 Left
  for _, k in ipairs({ "Benchy_0.15mm_PLA_MINI_1h12m_final_v3", "Benchy_0.15mm_PLA_MINI_1h12m_final_v4", "bad\255name_that_is_quite_long" }) do
    PC.State.files[k] = { key = k, name = k, storage = "usb", path = "usb/" .. k .. ".bgcode" }
    PC.State.order[#PC.State.order + 1] = k
  end
  PC.applyFiles()
  local c = M.ctl("Files").Choices
  assert(c[1] ~= c[2] and utf8.len(c[1]) <= 24 and utf8.len(c[2]) <= 24, c[1] .. " / " .. c[2])
  M.ctl("Files").String = c[2]; M.press("Files")
  assert(PC.State.selected == "Benchy_0.15mm_PLA_MINI_1h12m_final_v4")
end

function test_cport_overlapping_refresh_has_no_duplicates()
  farm(); M.press("Printer 3"); M.settle()   -- MK4 Left, initial walk done
  local STOR = '{"items":[{"name":"usb","path":"usb"}]}'
  local ROOT = '{"items":[{"name":"A.GCO","display_name":"a.gcode","path":"usb/A.GCO","folder":false},{"name":"SUB","display_name":"sub","path":"usb/SUB","folder":true}]}'
  local SUB  = '{"items":[{"name":"B.GCO","display_name":"b.gcode","path":"usb/SUB/B.GCO","folder":false}]}'
  local subs = M.count("/dev-mk4/files?path=usb/SUB/")
  PC.refreshFiles()
  M.respondTo("/dev-mk4/storages", 200, STOR)
  PC.refreshFiles()                                   -- second walk starts mid-way
  M.respondTo("/dev-mk4/files?path=usb/", 200, ROOT)  -- old walk's root: ignored
  M.respondTo("/dev-mk4/storages", 200, STOR)
  M.respondTo("/dev-mk4/files?path=usb/", 200, ROOT)
  M.respondTo("/dev-mk4/files?path=usb/SUB/", 200, SUB)
  local c = M.ctl("Files").Choices
  assert(#c == 2, table.concat(c, " | "))
  assert(M.count("/dev-mk4/files?path=usb/SUB/") == subs + 1, "old walk never lists its sub-folder")
end

-- Monitor -----------------------------------------------------------------

function test_cport_unexpected_value_types_are_skipped()
  M.loadConnect({})
  local null = setmetatable({}, {})
  local dev = { id = "x", name = "X", connected = true, state = { ["/state"] = null, ["/axis/z"] = null },
                job = { display_name = null, path = "/usb/A.GCO", progress = null } }
  local ok, err = pcall(PC.showMonitor, dev)
  assert(ok, tostring(err))
  assert(M.ctl("Job").String == "A.GCO", M.ctl("Job").String)
  assert(PC.statusLine(dev) == "UNKNOWN", PC.statusLine(dev))
end

function test_cport_address_change_clears_the_panel()
  farm(); M.press("Printer 2"); M.settle()   -- MINI Lab printing
  M.ctl("Progress Image").Legend = "old"
  M.ctl("Server Address").String = "10.0.0.10"; M.press("Server Address")
  assert(M.ctl("Selected Printer").String == "No printer selected")
  assert(M.ctl("Status").String == "No printer selected" and M.ctl("Job").String == "")
  assert(M.ctl("Farm Status").String == "Connecting…", M.ctl("Farm Status").String)
  assert(M.ctl("Online").IsInvisible == true and M.ctl("Preview").IsInvisible == true)
  assert(M.legendIcon("Progress Image") == "")
end

-- Progress picture + knob toggle --------------------------------------------

local function graphShown()
  if M.ctl("nGraph").IsInvisible or M.ctl("bGraph").IsInvisible then return false end
  for _, a in ipairs(AXIS) do if M.ctl(a).IsInvisible then return false end end
  return M.ctl("Progress Image").IsInvisible == true
end

function test_cport_knob_toggles_views()
  M.loadConnect({})
  assert(graphShown() and PC.State.view == "graph")
  M.press("View Toggle")
  assert(not graphShown() and M.ctl("Progress Image").IsInvisible == false and M.ctl("nGraph").IsInvisible == true)
  for _, a in ipairs(AXIS) do assert(M.ctl(a).IsInvisible == true, a) end
  M.press("View Toggle")
  assert(graphShown())
end

function test_cport_progress_picture_for_selected_job()
  farm(); M.press("Printer 2")   -- MINI Lab printing 42%, job path /usb/BRACKE~1.BGC
  M.answerUntil("/api/v1/devices/dev-mini/files/thumbnail?path=usb/BRACKE~1.BGC", 200, PNG_HDR(220, 124))
  M.settle()
  assert(PC.lastProgressSvg and PC.lastProgressSvg:find('y1="87.5"', 1, true), "progress drawn at 42%")
  assert(M.legendIcon("Progress Image") ~= "")
end

function test_cport_progress_picture_png_and_jpeg()
  M.loadConnect({})
  local png = PC.progressSvg("QUJD", 40, "image/png", 220, 124)
  assert(png:find("data:image/png;base64,QUJD", 1, true) and png:find('y1="90"', 1, true), png)
  local jpg = PC.progressSvg("QUJD", 40, "image/jpeg")
  assert(jpg:find("data:image/jpeg;base64,QUJD", 1, true))
  assert(jpg:find('id="done"><rect x="0" y="93" width="222" height="62"', 1, true))
  assert(PC.imageInfo(PNG_HDR(220, 124)) == "image/png")
  local mime, w, h = PC.imageInfo(PNG_HDR(220, 124))
  assert(w == 220 and h == 124)
  assert(PC.imageInfo(JPEG) == "image/jpeg")
end

function test_cport_same_progress_no_redraw_and_cleared_on_printer_change()
  farm(); M.press("Printer 2"); M.settle()
  M.ctl("Progress Image").Legend = "unchanged"
  PC.pollFarm(); M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
  assert(M.ctl("Progress Image").Legend == "unchanged", "same progress: no redraw")
  M.press("Printer 3"); M.settle()   -- MK4 Left, no job
  assert(M.legendIcon("Progress Image") == "")
end

-- A printer already printing when the plugin connects: selecting it draws the picture.
function test_cport_progress_picture_for_print_running_at_connect()
  M.loadConnect({})
  M.ctl("Server Address").String = "10.0.0.9"; M.ctl("API Token").String = "pcl_abc_secret"
  M.advance(1.5)                                    -- startup reset polls the farm
  M.answerUntil("/api/v1/devices", 200, M.fixture("connect_devices.json"))
  assert(PC.lastProgressSvg == nil, "nothing selected yet")
  M.press("Printer 2")                              -- MINI Lab, printing 42%
  M.answerUntil("/files/thumbnail?path=usb/BRACKE~1.BGC", 200, PNG_HDR(220, 124))
  assert(PC.lastProgressSvg and PC.lastProgressSvg:find('y1="87.5"', 1, true))
end
