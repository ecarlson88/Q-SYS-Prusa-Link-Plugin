-- The MINI's web server drops connections when two requests arrive together
-- (hardware log: thumbnail + file-info GETs in the same ms -> thumbnail code 0).
-- So requests go out one at a time.

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
end

function test_requests_go_one_at_a_time()
  setup()
  PL.request{ path = "/a" }
  PL.request{ path = "/b" }
  assert(#M.requests == 1 and M.last().Url == "http://10.0.0.5/a")
  M.respond(1, 200, "")
  assert(#M.requests == 2 and M.last().Url == "http://10.0.0.5/b")
end

function test_next_request_sent_after_failure_too()
  setup()
  PL.request{ path = "/a" }
  PL.request{ path = "/b" }
  M.respond(1, 0, nil)
  assert(#M.requests == 2)
end

function test_same_get_already_waiting_is_not_queued_twice()
  setup()
  PL.request{ path = "/a" }
  PL.request{ path = "/api/v1/status" }
  PL.request{ path = "/api/v1/status" }
  M.respond(1, 200, "")
  M.respond(2, 200, "")
  assert(#M.requests == 2)
end

function test_reset_drops_waiting_requests_for_old_printer()
  setup()
  PL.request{ path = "/a" }
  PL.request{ path = "/old" }
  M.ctl("Printer IP").String = "10.0.0.6"; M.press("Printer IP")
  M.respond(1, 200, "")
  assert(M.count("/old") == 0)
  assert(M.last().Url:find("10.0.0.6", 1, true))
end

function test_lost_reply_does_not_stall_the_queue()
  setup(); M.advance(1.5); M.settle()
  local before = #M.requests
  PL.request{ path = "/a" }
  PL.request{ path = "/b" }
  assert(#M.requests == before + 1)
  M.advance(8)
  assert(M.requests[before + 2] and M.requests[before + 2].Url == "http://10.0.0.5/b")
end

-- Only the status poll decides whether the printer is online; a failed
-- picture or file request must not flip the panel to "Offline".
function test_failed_picture_does_not_mark_printer_offline()
  setup(); M.advance(1.5); M.settle()
  PL.parseStatus(rapidjson.decode(M.fixture("status_printing.json")))
  PL.fetchPicture({ thumbnail = "/thumb/l/usb/X.GCO" }, function() end)
  M.respondTo("/thumb/l/usb/X.GCO", 0, nil)
  assert(M.ctl("Status").String == "PRINTING", M.ctl("Status").String)
  assert(M.ctl("Online").IsInvisible == false)
end
