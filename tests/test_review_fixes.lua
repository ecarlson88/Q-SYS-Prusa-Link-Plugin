-- Fixes from the final whole-branch review.

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5); M.settle()
end

-- I1: an error inside one reply's callback must not stop all later requests.
function test_review_queue_survives_a_failing_callback()
  setup()
  PL.request{ path = "/a", onOk = function() error("boom") end }
  PL.request{ path = "/b" }
  M.respond(M.find("/a"), 200, "{}")
  assert(M.last().Url == "http://10.0.0.5/b", "queue kept going")
end

-- I2: a file name that isn't valid UTF-8 must not break the list.
function test_review_invalid_utf8_name_is_listed()
  M.load({})
  local out = {}
  PL.walkFolder({ children = { { name = "BAD\255NAME_THAT_IS_RATHER_LONG_X.GCO", type = "PRINT_FILE" } } }, "usb", "", out)
  for _, e in ipairs(out) do PL.State.files[e.key] = e; PL.State.order[#PL.State.order + 1] = e.key end
  local ok, err = pcall(PL.applyFiles)
  assert(ok, tostring(err))
  assert(#M.ctl("Files").Choices == 1 and #M.ctl("Files").Choices[1] <= 24 + 3)
end

-- I3: changing the printer clears what the panel shows, not just internal state.
function test_review_ip_change_clears_the_panel()
  setup()
  PL.parseStatus(rapidjson.decode(M.fixture("status_printing.json")))
  PL.parseJob(200, rapidjson.decode(M.fixture("job_printing.json")))
  M.ctl("Progress Image").Legend = "old picture"
  PL.State.files["x"] = { key = "x", name = "x", storage = "usb", path = "/x.gcode", apiPath = "/X.GCO" }
  PL.State.order = { "x" }; PL.applyFiles()
  M.ctl("Files").String = "x"; M.press("Files")
  M.ctl("Printer IP").String = "10.0.0.6"; M.press("Printer IP")
  assert(M.ctl("Job").String == "No Current Job" and M.ctl("Progress").String == "" and M.ctl("Material").String == "")
  assert(M.ctl("Status").String == "Connecting…", M.ctl("Status").String)
  assert(M.ctl("Online").IsInvisible == true and M.ctl("Preview").IsInvisible == true)
  assert(M.legendIcon("Progress Image") == "")
end

-- M1: a second caller asking for the same GET gets its reply too.
function test_review_shared_get_answers_every_caller()
  setup()
  PL.request{ path = "/busy" }
  local got = {}
  PL.request{ path = "/same", onOk = function() got[#got + 1] = "first" end }
  PL.request{ path = "/same", onOk = function() got[#got + 1] = "second" end }
  M.respond(M.find("/busy"), 200, "")
  M.respond(M.find("/same"), 200, "{}")
  assert(#got == 2 and got[1] == "first" and got[2] == "second", table.concat(got, ","))
  assert(M.count("/same") == 1, "still only one request")
end

-- M2: a second refresh started mid-walk must not leave duplicates.
function test_review_overlapping_refresh_has_no_duplicates()
  setup()
  local STOR = '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}'
  local ROOT = '{"children":[{"name":"a.gcode","type":"PRINT_FILE"},{"name":"SUB","type":"FOLDER"}]}'
  local SUB  = '{"children":[{"name":"b.gcode","type":"PRINT_FILE"}]}'
  PL.refreshFiles()
  M.respondTo("/api/v1/storage", 200, STOR)           -- old walk: root listing now in flight
  PL.refreshFiles()                                    -- second walk queued behind it
  M.respondTo("/api/v1/files/usb/", 200, ROOT)         -- old root -> old SUB listing queued after new storage
  M.respondTo("/api/v1/storage", 200, STOR)            -- new walk clears the list
  M.respondTo("/api/v1/files/usb/SUB/", 200, SUB)      -- OLD walk's sub-folder reply arrives late
  M.respondTo("/api/v1/files/usb/", 200, ROOT)         -- new root
  M.respondTo("/api/v1/files/usb/SUB/", 200, SUB)      -- new sub-folder
  local c = M.ctl("Files").Choices
  assert(#c == 2, table.concat(c, " | "))
end

-- M4: JSON null decodes to a non-nil sentinel in Q-SYS rapidjson; non-numbers
-- and non-strings must be skipped, not written into controls.
function test_review_unexpected_value_types_are_skipped()
  M.load({})
  local null = setmetatable({}, {})
  M.ctl("Z Height").Value = 5
  local ok, err = pcall(PL.parseStatus, { printer = { state = "IDLE", axis_z = null, temp_nozzle = null, speed = "fast" } })
  assert(ok, tostring(err))
  assert(M.ctl("Z Height").Value == 5 and M.ctl("Status").String == "IDLE")
  ok, err = pcall(PL.parseJob, 200, { id = 3, progress = null, file = { display_name = null, name = "A.GCO" } })
  assert(ok, tostring(err))
  assert(M.ctl("Job").String == "A.GCO", M.ctl("Job").String)
end
