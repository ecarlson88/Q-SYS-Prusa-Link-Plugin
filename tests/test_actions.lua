-- Print, pause/resume, stop.

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.advance(1.5)  -- let the startup reset run before seeding state
  M.settle()
  PL.State.files["my part"] = { key = "my part", storage = "usb", path = "/my part.bgcode", apiPath = "/MYPART~1.BGC" }
  PL.State.order = { "my part" }
end

local function select(key)   -- opening a file also fetches its details; let that finish
  M.ctl("Files").String = key
  M.press("Files")
  M.settle()
end

function test_print_posts_encoded_path()
  setup(); select("my part")
  M.press("Print")
  local r = M.last()
  assert(r.Method == "POST" and r.Url == "http://10.0.0.5/api/v1/files/usb/MYPART~1.BGC", r.Url)
  assert(r.Auth == "digest")
end

function test_print_success_polls_again()
  setup(); select("my part"); M.press("Print")
  M.respond(#M.requests, 204, "")
  local n = M.count("/api/v1/status")
  M.advance(0.5)
  assert(M.count("/api/v1/status") == n + 1)
end

function test_pause_resume_by_state()
  setup(); PL.State.jobId = 297
  PL.State.state = "PRINTING"; M.press("Pause")
  assert(M.last().Method == "PUT" and M.last().Url == "http://10.0.0.5/api/v1/job/297/pause", M.last().Url)
  M.respond(#M.requests, 204, "")
  PL.State.state = "PAUSED"; M.press("Pause")
  assert(M.last().Method == "PUT" and M.last().Url == "http://10.0.0.5/api/v1/job/297/resume")
  local n = #M.requests
  PL.State.state = "IDLE"; M.press("Pause")
  assert(#M.requests == n)
end

function test_stop_deletes_job_and_refreshes_files()
  setup(); PL.State.jobId = 297
  M.press("Stop")
  assert(M.last().Method == "DELETE" and M.last().Url == "http://10.0.0.5/api/v1/job/297")
  M.respond(#M.requests, 204, "")
  local n = M.count("/api/v1/storage")
  M.advance(1.1)
  M.settle()
  assert(M.count("/api/v1/storage") == n + 1)
end

function test_stop_without_job_does_nothing()
  setup(); local n = #M.requests
  M.press("Stop")
  assert(#M.requests == n)
end

function test_no_selection_no_request()
  setup(); local n = #M.requests
  M.press("Print")
  assert(#M.requests == n)
end

function test_selected_entry()
  setup(); select("my part")
  assert(PL.selectedEntry().path == "/my part.bgcode")
end
