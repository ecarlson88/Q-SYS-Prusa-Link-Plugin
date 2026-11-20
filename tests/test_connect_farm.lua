-- Prusa Connect: server requests, farm polling, printer buttons, selection.

local function setup(props)
  M.loadConnect(props or {})
  M.ctl("Server Address").String = "10.0.0.9"
  M.ctl("API Token").String = "pcl_abc_secret"
end

local function loadFarm(props)
  setup(props)
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, M.fixture("connect_devices.json"))
end

function test_connect_request_uses_bearer_token_and_default_port()
  setup()
  PC.request{ path = "/api/v1/devices" }
  local r = M.last()
  assert(r.Url == "http://10.0.0.9:8080/api/v1/devices", r.Url)
  assert(r.Headers and r.Headers["Authorization"] == "Bearer pcl_abc_secret")
  assert(r.User == nil and r.Auth == nil, "no digest auth on Connect")
end

function test_connect_address_with_port_and_https()
  setup({ ["Use HTTPS"] = true })
  M.ctl("Server Address").String = "connect.lan:9000"
  PC.request{ path = "/api/v1/devices" }
  assert(M.last().Url == "https://connect.lan:9000/api/v1/devices", M.last().Url)
end

function test_connect_no_request_without_address_or_token()
  M.loadConnect({})
  PC.request{ path = "/x" }
  M.ctl("Server Address").String = "10.0.0.9"
  PC.request{ path = "/x" }
  assert(#M.requests == 0)
end

function test_connect_auth_errors_are_explained()
  setup(); PC.pollFarm()
  M.respondTo("/api/v1/devices", 401, '{"code":"core.auth/TOKEN_INVALID"}')
  assert(M.ctl("Farm Status").String == "Token rejected", M.ctl("Farm Status").String)
  assert(M.ctl("Online").IsInvisible == true)
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 403, '{"code":"core.auth/ACCESS_DENIED"}')
  assert(M.ctl("Farm Status").String == "Token needs operate access", M.ctl("Farm Status").String)
end

function test_connect_server_offline()
  setup(); PC.pollFarm()
  M.respondTo("/api/v1/devices", 0, nil)
  assert(M.ctl("Farm Status").String == "Server offline")
  assert(M.ctl("Online").IsInvisible == true)
end

function test_connect_farm_buttons_sorted_by_name_with_status()
  loadFarm()
  assert(M.ctl("Printer 1").Legend == "Core One" and M.ctl("Printer 2").Legend == "MINI Lab"
         and M.ctl("Printer 3").Legend == "MK4 Left", M.ctl("Printer 1").Legend)
  assert(M.ctl("Printer 1 Status").String == "OFFLINE")
  assert(M.ctl("Printer 2 Status").String == "PRINTING 42%", M.ctl("Printer 2 Status").String)
  assert(M.ctl("Printer 3 Status").String == "IDLE")
  assert(M.ctl("Farm Status").String == "3 printers")
  assert(M.ctl("Online").IsInvisible == false)
end

function test_connect_unused_slots_hidden()
  loadFarm()
  for i = 1, 3 do assert(M.ctl("Printer " .. i).IsInvisible == false) end
  for i = 4, 6 do
    assert(M.ctl("Printer " .. i).IsInvisible == true and M.ctl("Printer " .. i .. " Status").IsInvisible == true)
  end
end

function test_connect_more_printers_than_slots()
  loadFarm({ ["Printer Slots"] = 2 })
  assert(M.ctl("Farm Status").String == "3 printers (2 shown)", M.ctl("Farm Status").String)
end

function test_connect_select_printer()
  loadFarm()
  M.press("Printer 2")
  assert(PC.State.selectedId == "dev-mini")
  assert(M.ctl("Selected Printer").String == "MINI Lab")
  assert(M.ctl("Printer 2").Boolean == true and M.ctl("Printer 1").Boolean == false and M.ctl("Printer 3").Boolean == false)
end

function test_connect_nothing_selected_at_start()
  loadFarm()
  assert(PC.State.selectedId == nil and M.ctl("Selected Printer").String == "No printer selected")
end

function test_connect_selection_follows_printer_when_order_changes()
  loadFarm(); M.press("Printer 3")   -- MK4 Left
  PC.pollFarm()
  local d = rapidjson.decode(M.fixture("connect_devices.json"))
  table.insert(d.items, { id = "dev-new", name = "Alpha", connected = true, state = { ["/state"] = "IDLE" } })
  M.respondTo("/api/v1/devices", 200, rapidjson.encode(d))
  assert(M.ctl("Printer 4").Legend == "MK4 Left" and M.ctl("Printer 4").Boolean == true)
  assert(M.ctl("Printer 3").Boolean == false)
  assert(PC.State.selectedId == "dev-mk4")
end

function test_connect_selected_printer_removed()
  loadFarm(); M.press("Printer 2")
  PC.pollFarm()
  M.respondTo("/api/v1/devices", 200, '{"items":[{"id":"dev-mk4","name":"MK4 Left","connected":true,"state":{}}]}')
  assert(PC.State.selectedId == nil and M.ctl("Selected Printer").String == "No printer selected")
end

function test_connect_empty_slot_press_does_nothing()
  loadFarm()
  M.press("Printer 5")
  assert(PC.State.selectedId == nil)
end

function test_connect_polls_on_interval()
  setup({ ["Poll Interval"] = 10 })
  M.advance(1.5); M.settle()
  local n = M.count("/api/v1/devices")
  M.advance(5); assert(M.count("/api/v1/devices") == n)
  M.advance(5); assert(M.count("/api/v1/devices") == n + 1)
end

function test_connect_stale_reply_after_address_change_ignored()
  setup(); PC.pollFarm()
  local old = M.find("/api/v1/devices")
  M.ctl("Server Address").String = "10.0.0.10"; M.press("Server Address")
  M.respond(old, 200, M.fixture("connect_devices.json"))
  assert(M.ctl("Printer 1").Legend ~= "Core One")
end
