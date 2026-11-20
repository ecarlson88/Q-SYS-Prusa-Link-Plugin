-- Prusa Connect: Control page (temperatures, jog, home, motors off).

local function mini(state)
  M.loadConnect({})
  M.ctl("Server Address").String = "10.0.0.9"
  M.ctl("API Token").String = "pcl_abc_secret"
  M.advance(1.5); M.settle()
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
  M.press("Printer 2"); M.settle()   -- MINI Lab
  PC.selectedDevice().state["/state"] = state or "IDLE"
end

local function cmd(i)
  local r = M.requests[i or #M.requests]
  assert(r.Url == "http://10.0.0.9:8080/api/v1/devices/dev-mini/commands", r.Url)
  return rapidjson.decode(r.Data)
end

local function answer() M.respond(#M.requests, 200, '{"ok":true}') end

function test_connect_set_nozzle_and_bed()
  mini()
  M.ctl("Nozzle Setpoint").Value = 215; M.press("Set Nozzle")
  local c = cmd()
  assert(c.verb == "core.command.set_nozzle_temperature" and c.args.nozzle_temperature == "215", c.args.nozzle_temperature)
  answer()
  M.ctl("Bed Setpoint").Value = 60.0; M.press("Set Bed")
  c = cmd()
  assert(c.verb == "core.command.set_bed_temperature" and c.args.bed_temperature == "60", c.args.bed_temperature)
end

function test_connect_presets_set_both_temperatures()
  for _, p in ipairs({ { "Preset PLA", 215, 60 }, { "Preset PETG", 240, 85 }, { "Cooldown", 0, 0 } }) do
    mini()
    local first = #M.requests + 1
    M.press(p[1])
    local c1 = cmd(first); answer()
    local c2 = cmd(first + 1)
    assert(c1.verb == "core.command.set_nozzle_temperature" and c1.args.nozzle_temperature == tostring(p[2]), p[1])
    assert(c2.verb == "core.command.set_bed_temperature" and c2.args.bed_temperature == tostring(p[3]), p[1])
    assert(M.ctl("Nozzle Setpoint").Value == p[2] and M.ctl("Bed Setpoint").Value == p[3])
  end
end

function test_connect_temperatures_allowed_while_printing()
  mini("PRINTING")
  M.ctl("Nozzle Setpoint").Value = 220; M.press("Set Nozzle")
  assert(cmd().verb == "core.command.set_nozzle_temperature")
end

function test_connect_step_buttons_are_exclusive_default_1()
  mini()
  assert(PC.State.step == 1 and M.ctl("Step 1").Boolean == true)
  M.press("Step 10")
  assert(PC.State.step == 10 and M.ctl("Step 10").Boolean == true)
  assert(M.ctl("Step 1").Boolean == false and M.ctl("Step 0.1").Boolean == false)
end

function test_connect_jog_xy_and_z()
  mini()
  M.press("X+"); local c = cmd()
  assert(c.verb == "core.command.move" and c.args.x == "1" and c.args.y == nil and c.args.feedrate == "3000")
  answer()
  M.press("Y-"); c = cmd()
  assert(c.verb == "core.command.move" and c.args.y == "-1" and c.args.x == nil)
  answer()
  M.press("Step 0.1"); M.press("Z-"); c = cmd()
  assert(c.verb == "core.command.move_z" and c.args.distance == "-0.1" and c.args.feedrate == "600", c.args.distance)
  answer()
  M.press("Step 10"); M.press("X-"); c = cmd()
  assert(c.args.x == "-10", c.args.x)
end

function test_connect_home_and_motors_off()
  mini()
  M.press("Home All"); local c = cmd()
  assert(c.verb == "core.command.home" and c.args.axis == "XYZ")
  answer()
  M.press("Motors Off"); c = cmd()
  assert(c.verb == "core.command.disable_steppers" and c.args == nil)
end

function test_connect_motion_refused_while_printing_or_paused()
  for _, st in ipairs({ "PRINTING", "PAUSED" }) do
    mini(st)
    local n = #M.requests
    for _, b in ipairs({ "X+", "Z-", "Home All", "Motors Off" }) do M.press(b) end
    assert(#M.requests == n, st)
    assert(M.ctl("Control Status").String == "Busy: " .. st:lower(), M.ctl("Control Status").String)
  end
end

function test_connect_command_result_shown()
  mini()
  M.press("Home All")
  M.respond(#M.requests, 200, '{"command_id":"c9","ok":true}')
  assert(M.ctl("Control Status").String == "Sent: Home all", M.ctl("Control Status").String)
  M.press("Motors Off")
  M.respond(#M.requests, 200, '{"command_id":"c10","ok":false}')
  assert(M.ctl("Control Status").String == "Refused: Motors off")
end

function test_connect_control_needs_a_printer()
  M.loadConnect({})
  M.ctl("Server Address").String = "10.0.0.9"; M.ctl("API Token").String = "t"
  M.press("Home All")
  assert(M.ctl("Control Status").String == "Select a printer first")
  assert(#M.requests == 0)
end
