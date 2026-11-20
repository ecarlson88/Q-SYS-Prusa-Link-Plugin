-- Request helper, polling, status/job parsing, reset.

local function setup(props)
  M.load(props or {})
  M.ctl("Printer IP").String = "10.0.0.5"
  M.ctl("Password").String = "pw"
end

function test_request_uses_digest_auth()
  setup()
  PL.request{ method = "GET", path = "/api/v1/status" }
  local r = M.last()
  assert(r.Url == "http://10.0.0.5/api/v1/status", r.Url)
  assert(r.User == "maker" and r.Password == "pw" and r.Auth == "digest")
  assert(r.Headers == nil or r.Headers["X-Api-Key"] == nil)
end

function test_no_request_without_ip()
  M.load({})
  PL.request{ method = "GET", path = "/api/v1/status" }
  assert(#M.requests == 0)
end

function test_401_shows_auth_failed()
  setup(); PL.poll()
  M.respond(M.find("/api/v1/status"), 401, "")
  assert(M.ctl("Status").String == "Auth failed", M.ctl("Status").String)
  assert(M.ctl("Online").IsInvisible == true)
end

function test_offline_does_not_error_and_polling_continues()  -- Review Focus 1
  setup(); M.advance(5)
  M.respond(M.find("/api/v1/status"), 0, nil)
  assert(M.ctl("Status").String == "Offline")
  M.settle()
  local n = M.count("/api/v1/status")
  M.advance(5)
  assert(M.count("/api/v1/status") > n)
end

function test_status_parse()
  M.load({})
  PL.parseStatus(rapidjson.decode(M.fixture("status_printing.json")))
  assert(M.ctl("Status").String == "PRINTING")
  assert(M.ctl("Nozzle Temp").Value == 215 and M.ctl("Bed Target").Value == 60)
  assert(M.ctl("Z Height").Value == 8.4 and M.ctl("Print Speed").Value == 100)
  assert(M.ctl("Online").IsInvisible == false)
  assert(PL.State.state == "PRINTING")
end

function test_status_poll_end_to_end()
  setup(); PL.poll()
  M.respond(M.find("/api/v1/status"), 200, M.fixture("status_printing.json"))
  assert(M.ctl("Status").String == "PRINTING")
end

function test_job_204_and_200()
  M.load({})
  PL.parseJob(204, nil)
  assert(M.ctl("Job").String == "No Current Job" and PL.State.jobId == nil and PL.State.progress == nil)
  PL.parseJob(200, rapidjson.decode(M.fixture("job_printing.json")))
  assert(PL.State.jobId == 297 and PL.State.progress == 42)
  assert(M.ctl("Progress").String == "42%", M.ctl("Progress").String)
  assert(M.ctl("Job").String == "bracket_v3_PLA.bgcode")
  assert(PL.State.jobRefs.thumbnail == "/thumb/l/usb/BRACKE~1.BGC")
  assert(M.ctl("Material").String == "PLA")
end

function test_stale_response_after_ip_change_is_ignored()  -- Review Focus 4
  setup(); PL.poll()
  local old = M.find("/api/v1/status")
  M.ctl("Printer IP").String = "10.0.0.6"; M.press("Printer IP")
  M.respond(old, 200, M.fixture("status_printing.json"))
  assert(M.ctl("Status").String ~= "PRINTING")
end

function test_credential_change_resets_and_reconnects()
  setup()
  M.ctl("Password").String = "new"; M.press("Password")
  assert(M.requests[M.find("/api/v1/status")].Password == "new")
  M.settle()
  assert(M.count("/api/version") == 1 and M.count("/api/v1/info") == 1)
end

function test_encode_path()  -- Review Focus 2
  M.load({})
  assert(PL.encodePath("/usb/my part (v2).bgcode") == "/usb/my%20part%20%28v2%29.bgcode",
         PL.encodePath("/usb/my part (v2).bgcode"))
  assert(PL.encodePath("/usb/a_b-c.d~e.gcode") == "/usb/a_b-c.d~e.gcode")
end

function test_poll_interval_property()
  setup({ ["Poll Interval"] = 10 })
  M.advance(1.5)
  M.settle()
  local n = M.count("/api/v1/status")
  M.advance(5)
  assert(M.count("/api/v1/status") == n)
  M.advance(5)
  assert(M.count("/api/v1/status") == n + 1)
end

function test_debug_off_is_silent()
  M.load({ Debug = false }); PL.log("x"); assert(#M.logs == 0)
end

function test_debug_on_logs()
  M.load({ Debug = true }); PL.log("x"); assert(#M.logs == 1)
end

-- Hardware feedback: Debug was flooded with the routine status/job polls.
function test_debug_skips_routine_polls_but_logs_other_requests()
  M.load({ Debug = true })
  M.ctl("Printer IP").String = "10.0.0.5"
  PL.poll(); M.settle()
  for _, line in ipairs(M.logs) do
    assert(not line:find("/api/v1/status", 1, true) and not line:find("/api/v1/job", 1, true), line)
  end
  PL.request{ path = "/api/v1/storage" }
  local found = false
  for _, line in ipairs(M.logs) do if line:find("/api/v1/storage", 1, true) then found = true end end
  assert(found, "other requests are still logged")
end

-- Hardware feedback: Material stayed blank. The MINI's job info has no file
-- details, so the job's file is looked up once per job.
local function jobWithoutMeta(id)
  local j = rapidjson.decode(M.fixture("job_printing.json"))
  j.file.meta = nil
  j.id = id or j.id
  return j
end

function test_material_fetched_from_job_file_once_per_job()
  M.load({}); M.ctl("Printer IP").String = "10.0.0.5"; M.advance(1.5); M.settle()
  PL.parseJob(200, jobWithoutMeta())
  M.respondTo("/api/v1/files/usb/BRACKE~1.BGC", 200, '{"meta":{"filament_type":"PETG"}}')
  assert(M.ctl("Material").String == "PETG", M.ctl("Material").String)
  local n = M.count("/api/v1/files/usb/BRACKE~1.BGC")
  PL.parseJob(200, jobWithoutMeta())
  assert(M.count("/api/v1/files/usb/BRACKE~1.BGC") == n, "same job: no new lookup")
  M.settle()   -- the progress picture request is ahead in the queue
  PL.parseJob(200, jobWithoutMeta(298))
  M.settle()
  assert(M.count("/api/v1/files/usb/BRACKE~1.BGC") == n + 1, "new job: look up again")
end

function test_material_cleared_when_no_job()
  M.load({})
  M.ctl("Material").String = "PLA"
  PL.parseJob(204, nil)
  assert(M.ctl("Material").String == "")
end
