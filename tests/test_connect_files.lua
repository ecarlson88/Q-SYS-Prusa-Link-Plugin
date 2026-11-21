-- Prusa Connect: Files page for the selected printer.

local PNG = "\137PNG\r\n\26\nX"
local STORAGES = '{"items":[{"name":"usb","path":"usb","read_only":false}]}'
local ROOT = [[{"directory":{"name":"usb","path":"usb","folder":true},"items":[
  {"name":"BRACK~1.BGC","display_name":"bracket v3.bgcode","path":"usb/BRACK~1.BGC","folder":false,"size":1250000,"read_only":false},
  {"name":"MODELS","display_name":"models","path":"usb/MODELS","folder":true},
  {"name":"README.TXT","display_name":"readme.txt","path":"usb/README.TXT","folder":false,"size":10}]}]]
local MODELS = [[{"directory":{"name":"MODELS","path":"usb/MODELS","folder":true},"items":[
  {"name":"CLIP~1.GCO","display_name":"clip.gcode","path":"usb/MODELS/CLIP~1.GCO","folder":false,"size":2048,"read_only":true}]}]]

local function farm()
  M.loadConnect({})
  M.ctl("Server Address").String = "10.0.0.9"
  M.ctl("API Token").String = "pcl_abc_secret"
  M.advance(1.5); M.settle()
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
end

-- Selects MINI Lab (slot 2) and answers its file listing.
local function miniFiles()
  farm(); M.press("Printer 2")
  M.respondTo("/api/v1/devices/dev-mini/storages", 200, STORAGES)
  M.respondTo("/api/v1/devices/dev-mini/files?path=usb/", 200, ROOT)
  M.respondTo("/api/v1/devices/dev-mini/files?path=usb/MODELS/", 200, MODELS)
end

local function open(key) M.ctl("Files").String = key; M.press("Files") end
local function last() return M.last() end
local function body(r) return rapidjson.decode(r.Data) end

function test_connect_selecting_printer_lists_its_files()
  miniFiles()
  local c = M.ctl("Files").Choices
  assert(#c == 2 and c[1] == "bracket v3" and c[2] == "models/clip", table.concat(c, ","))
  assert(PC.State.files["bracket v3"].path == "usb/BRACK~1.BGC")
end

function test_connect_storage_listing_failure_falls_back_to_usb()
  farm(); M.press("Printer 2")
  M.respondTo("/api/v1/devices/dev-mini/storages", 404, "")
  assert(M.last().Url:find("/api/v1/devices/dev-mini/files?path=usb/", 1, true), M.last().Url)
end

function test_connect_changing_printer_clears_files()
  miniFiles()
  M.press("Printer 3")
  assert(#M.ctl("Files").Choices == 0 and PC.State.files["bracket v3"] == nil)
  assert(M.last().Url:find("/api/v1/devices/dev-mk4/storages", 1, true))
end

function test_connect_offline_printer_not_listed()
  farm(); local n = #M.requests
  M.press("Printer 1")   -- Core One, disconnected
  assert(#M.requests == n)
end

function test_connect_preview_fetches_thumbnail_by_path()
  miniFiles(); open("bracket v3")
  assert(not M.ctl("Preview").IsInvisible)
  assert(last().Url == "http://10.0.0.9:8080/api/v1/devices/dev-mini/files/thumbnail?path=usb/BRACK~1.BGC", last().Url)
  M.respond(#M.requests, 200, PNG)
  assert(M.legendIcon("Preview Image") == M.base64(PNG))
  assert(M.ctl("Preview Details").String == "bracket v3\n1.2 MB", M.ctl("Preview Details").String)
  M.press("Preview")
  assert(M.ctl("Preview").IsInvisible)
end

function test_connect_print_selected_file()
  miniFiles(); open("bracket v3"); M.respond(#M.requests, 200, PNG)
  M.press("Print")
  local r = last()
  assert(r.Method == "POST" and r.Url == "http://10.0.0.9:8080/api/v1/devices/dev-mini/print", r.Url)
  assert(body(r).path == "usb/BRACK~1.BGC")
  M.respond(#M.requests, 200, '{"command":{"command_id":"c1","ok":false},"path":"usb/BRACK~1.BGC"}')
  assert(M.ctl("Control Status").String == "Print refused by printer", M.ctl("Control Status").String)
end

function test_connect_pause_resume_stop_use_commands()
  miniFiles()   -- MINI Lab is PRINTING
  M.press("Pause")
  assert(last().Url == "http://10.0.0.9:8080/api/v1/devices/dev-mini/commands", last().Url)
  assert(body(last()).verb == "core.command.pause_print")
  M.respond(#M.requests, 200, '{"command_id":"c2","ok":true}')
  PC.selectedDevice().state["/state"] = "PAUSED"
  M.press("Pause")
  assert(body(last()).verb == "core.command.resume_print")
  M.respond(#M.requests, 200, '{"ok":true}')
  M.press("Stop")
  assert(body(last()).verb == "core.command.stop_print")
end

function test_connect_unsupported_verb_not_sent()
  farm(); M.press("Printer 3"); M.settle()   -- MK4 Left: no stop_print verb
  local n = #M.requests
  M.press("Stop")
  assert(#M.requests == n and M.ctl("Control Status").String == "Not supported by this printer",
         M.ctl("Control Status").String)
end

function test_connect_delete_needs_confirmation()
  miniFiles(); open("bracket v3"); M.respond(#M.requests, 200, PNG)
  PC.selectedDevice().state["/state"] = "IDLE"
  M.press("Delete")
  assert(M.ctl("Delete").Legend == "Confirm?")
  M.press("Delete")
  local r = last()
  assert(r.Method == "DELETE" and r.Url:find("/api/v1/devices/dev-mini/files?path=usb/BRACK~1.BGC", 1, true), r.Url)
  M.respond(#M.requests, 204, "")
  assert(PC.State.files["bracket v3"] == nil and M.ctl("Preview").IsInvisible)
end

function test_connect_delete_blocked_while_printing_and_on_read_only()
  miniFiles(); open("bracket v3"); M.respond(#M.requests, 200, PNG)
  M.press("Delete")   -- MINI Lab is PRINTING
  assert(PC.State.deleteArmed == false)
  PC.selectedDevice().state["/state"] = "IDLE"
  open("models/clip"); M.settle()
  M.press("Delete")   -- read-only file
  assert(PC.State.deleteArmed == false)
end

function test_connect_delete_times_out()
  miniFiles(); open("bracket v3"); M.respond(#M.requests, 200, PNG)
  PC.selectedDevice().state["/state"] = "IDLE"
  M.press("Delete"); M.advance(5.1)
  assert(M.ctl("Delete").Legend == "Delete" and PC.State.deleteArmed == false)
end

function test_connect_file_names_with_spaces_are_encoded()
  miniFiles()
  PC.State.files["x"] = { key = "x", path = "usb/my part.bgcode", name = "my part" }
  open("x")
  assert(last().Url:find("thumbnail?path=usb/my%20part.bgcode", 1, true), last().Url)
end
