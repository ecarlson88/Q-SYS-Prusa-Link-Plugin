-- Prusa Connect: Monitor page shows the selected printer.

local function farm()
  M.loadConnect({})
  M.ctl("Server Address").String = "10.0.0.9"
  M.ctl("API Token").String = "pcl_abc_secret"
  M.advance(1.5); M.settle()   -- let the startup reset run first
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
end

function test_connect_monitor_shows_selected_printer()
  farm(); M.press("Printer 2")   -- MINI Lab, printing
  assert(M.ctl("Status").String == "PRINTING")
  assert(M.ctl("Job").String == "bracket_v3_PLA.bgcode")
  assert(M.ctl("Progress").String == "42%")
  assert(M.ctl("Nozzle Temp").Value == 214.6 and M.ctl("Nozzle Target").Value == 215)
  assert(M.ctl("Bed Temp").Value == 59.8 and M.ctl("Bed Target").Value == 60)
  assert(M.ctl("Z Height").Value == 8.4 and M.ctl("Print Speed").Value == 100)
end

function test_connect_monitor_idle_printer_has_no_job()
  farm(); M.press("Printer 3")   -- MK4 Left, idle
  assert(M.ctl("Status").String == "IDLE")
  assert(M.ctl("Job").String == "No Current Job" and M.ctl("Progress").String == "")
end

function test_connect_monitor_offline_printer()
  farm(); M.press("Printer 1")   -- Core One, disconnected
  assert(M.ctl("Status").String == "OFFLINE")
end

function test_connect_monitor_updates_on_next_poll()
  farm(); M.press("Printer 2"); M.settle()
  local d = rapidjson.decode(M.fixture("connect_devices.json"))
  d.items[2].state["/tools/0/nozzle_temp"] = 215.0
  d.items[2].job.progress = 43
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, rapidjson.encode(d))
  assert(M.ctl("Nozzle Temp").Value == 215.0 and M.ctl("Progress").String == "43%")
end

function test_connect_monitor_blank_without_selection()
  farm()
  assert(M.ctl("Status").String == "No printer selected", M.ctl("Status").String)
  assert(M.ctl("Job").String == "")
end

function test_connect_monitor_extras_carried_over()
  M.loadConnect({})
  assert(M.ctl("Axis 300C").String == "300°C" and M.ctl("Axis 0C").String == "0°C")
  assert(M.ctl("Progress Image").IsInvisible == true and M.ctl("Progress Overlay").IsInvisible == true)
  assert(M.ctl("nGraph").Legend ~= "" and M.ctl("bGraph").Legend ~= "", "graphs drawn")
end

function test_connect_graph_samples_selected_printer()
  farm(); M.press("Printer 2")
  local before = #PC.nozzleSamples
  M.ctl("Nozzle Temp").Position = 0.7
  M.advance(1)
  assert(PC.nozzleSamples[#PC.nozzleSamples] == 0.7)
  assert(#PC.nozzleSamples == before)  -- capped window
end

function test_connect_graph_clears_when_printer_changes()
  farm(); M.press("Printer 2")
  M.ctl("Nozzle Temp").Position = 0.7; M.advance(1)
  M.press("Printer 3")
  for _, v in ipairs(PC.nozzleSamples) do assert(v ~= 0.7, "old printer's samples kept") end
end
