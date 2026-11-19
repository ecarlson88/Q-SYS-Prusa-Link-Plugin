-- Delete needs a second press within 5 seconds.

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5)
  local s = PL.State
  s.files["bracket_v3_PLA"] = { key = "bracket_v3_PLA", storage = "usb", path = "/bracket_v3_PLA.bgcode" }
  s.files["clip"] = { key = "clip", storage = "usb", path = "/clip.gcode" }
  s.files["ro"] = { key = "ro", storage = "local", path = "/ro.gcode" }
  s.order = { "bracket_v3_PLA", "clip", "ro" }
  s.readOnly = { usb = false, ["local"] = true }
  PL.applyFiles()
  s.state = "IDLE"
end

local function select(key) M.ctl("Files").String = key; M.press("Files") end

local function deletes()
  local n = 0
  for _, r in ipairs(M.requests) do if r.Method == "DELETE" then n = n + 1 end end
  return n
end

function test_first_press_arms_without_request()
  setup(); select("bracket_v3_PLA")
  M.press("Delete")
  assert(M.ctl("Delete").Legend == "Confirm?" and PL.State.deleteArmed == true)
  assert(M.ctl("Delete").Color == "#B3261E")
  assert(deletes() == 0)
end

function test_second_press_deletes_and_removes_from_list()
  setup(); select("bracket_v3_PLA")
  M.press("Delete"); M.press("Delete")
  local r = M.last()
  assert(r.Method == "DELETE" and r.Url == "http://10.0.0.5/api/v1/files/usb/bracket_v3_PLA.bgcode", r.Url)
  assert(M.ctl("Delete").Legend == "Delete" and PL.State.deleteArmed == false)
  M.respond(#M.requests, 204, "")
  for _, c in ipairs(M.ctl("Files").Choices) do assert(c ~= "bracket_v3_PLA") end
  assert(PL.State.files["bracket_v3_PLA"] == nil and PL.State.selected == nil)
end

function test_timeout_disarms()
  setup(); select("clip")
  M.press("Delete")
  M.advance(5.1)
  assert(M.ctl("Delete").Legend == "Delete" and PL.State.deleteArmed == false)
  M.press("Delete")
  assert(deletes() == 0 and PL.State.deleteArmed == true)
end

function test_old_timer_does_not_disarm_a_new_arm()
  setup(); select("clip")
  M.press("Delete"); M.advance(4)
  select("bracket_v3_PLA")          -- disarms
  M.press("Delete"); M.advance(2)   -- first timer would fire here
  assert(PL.State.deleteArmed == true)
end

function test_selection_change_disarms()
  setup(); select("clip")
  M.press("Delete")
  select("bracket_v3_PLA")
  assert(PL.State.deleteArmed == false and M.ctl("Delete").Legend == "Delete")
end

function test_blocked_while_printing_even_if_armed_before()
  setup(); select("clip")
  M.press("Delete")
  PL.State.state = "PRINTING"
  M.press("Delete")
  assert(deletes() == 0 and PL.State.deleteArmed == false)
end

function test_never_arms_while_printing_or_paused()
  setup(); select("clip")
  PL.State.state = "PAUSED"; M.press("Delete")
  assert(PL.State.deleteArmed == false)
end

function test_read_only_storage_never_arms()
  setup(); select("ro")
  M.press("Delete")
  assert(PL.State.deleteArmed == false and deletes() == 0)
end

function test_no_selection_never_arms()
  setup()
  M.press("Delete")
  assert(PL.State.deleteArmed == false)
end

function test_409_keeps_file_in_list()
  setup(); select("clip")
  M.press("Delete"); M.press("Delete")
  M.respond(#M.requests, 409, "")
  assert(PL.State.files["clip"] ~= nil)
end
