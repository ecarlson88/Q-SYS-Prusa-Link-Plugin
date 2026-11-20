-- Storage and file listing.

local function setup()
  M.load({})
  M.ctl("Printer IP").String = "10.0.0.5"
end

function test_walk_folder_nested_keys_and_refs()
  M.load({})
  local out = {}
  PL.walkFolder(rapidjson.decode(M.fixture("files_usb.json")), "usb", "", out)
  assert(#out == 2, "firmware files are skipped, got " .. #out)
  assert(out[1].key == "bracket_v3_PLA" and out[1].path == "/bracket_v3_PLA.bgcode" and out[1].storage == "usb")
  assert(out[1].refs.thumbnail == "/thumb/l/usb/BRACKE~1.BGC" and out[1].meta.filament_type == "PLA")
  assert(out[2].key == "parts/clip" and out[2].path == "/parts/clip.gcode", out[2].key .. " " .. out[2].path)
end

-- Prusa's own web UI addresses files by their short `name`, never `display_name`.
-- Using the long name for actions crashed a MINI on DELETE, so API paths use `name`.
function test_api_path_uses_short_names()
  M.load({})
  local out = {}
  PL.walkFolder(rapidjson.decode(M.fixture("files_usb.json")), "usb", "", out)
  assert(out[1].apiPath == "/BRACKE~1.BGC", tostring(out[1].apiPath))
  assert(out[2].apiPath == "/PARTS/CLIP~1.GCO", tostring(out[2].apiPath))
end

function test_refresh_lists_available_storages_only()
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200, M.fixture("storage.json"))
  M.settle()
  assert(M.count("/api/v1/files/usb/") == 1 and M.count("/api/v1/files/local/") == 1)
  assert(M.count("/api/v1/files/sdcard/") == 0)
  assert(PL.State.readOnly["local"] == true and PL.State.readOnly["usb"] == false)
end

function test_duplicate_names_across_storages_are_distinct()  -- Review Focus 3
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200, M.fixture("storage.json"))
  M.respond(M.find("/api/v1/files/usb/"), 200, M.fixture("files_usb.json"))
  M.respond(M.find("/api/v1/files/local/"), 200, M.fixture("files_local.json"))
  assert(PL.State.files["bracket_v3_PLA"].storage == "usb")
  assert(PL.State.files["bracket_v3_PLA (local)"].storage == "local")
  local c = M.ctl("Files").Choices
  assert(#c == 3 and c[1] == "bracket_v3_PLA" and c[2] == "parts/clip" and c[3] == "bracket_v3_PLA (local)",
         table.concat(c, ","))
end

function test_folder_without_children_is_fetched()
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200,
    '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}')
  M.respond(M.find("/api/v1/files/usb/"), 200,
    '{"name":"usb","type":"FOLDER","children":[{"name":"MYPART~1","display_name":"my parts","type":"FOLDER"}]}')
  local i = M.find("/api/v1/files/usb/MYPART~1/")
  M.respond(i, 200, '{"name":"MYPART~1","type":"FOLDER","children":[{"name":"a b.gcode","type":"PRINT_FILE"}]}')
  local e = PL.State.files["my parts/a b"]
  assert(e and e.path == "/my parts/a b.gcode" and e.apiPath == "/MYPART~1/a b.gcode")
end

function test_missing_refs_and_meta_do_not_crash()  -- Review Focus 5
  M.load({})
  local out = {}
  PL.walkFolder({ children = { { name = "a.gcode", type = "PRINT_FILE" } } }, "usb", "", out)
  assert(out[1].key == "a" and out[1].refs == nil)
  PL.walkFolder({}, "usb", "", out)  -- no children at all
  assert(#out == 1)
end

function test_storage_folder_url_is_encoded()
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200,
    '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}')
  assert(M.last().Url == "http://10.0.0.5/api/v1/files/usb/", M.last().Url)
  assert(M.last().Auth == "digest")
end

function test_refresh_replaces_old_list()
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200, M.fixture("storage.json"))
  M.respond(M.find("/api/v1/files/usb/"), 200, M.fixture("files_usb.json"))
  M.respond(M.find("/api/v1/files/local/"), 200, M.fixture("files_local.json"))
  PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200,
    '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}')
  M.respond(M.find("/api/v1/files/usb/"), 200, '{"children":[{"name":"new.gcode","type":"PRINT_FILE"}]}')
  local c = M.ctl("Files").Choices
  assert(#c == 1 and c[1] == "new", table.concat(c, ","))
end

-- Hardware feedback: long names made the list scroll sideways.
local LONG1 = "Benchy_0.15mm_PLA_MINI_1h12m_final_v3"
local LONG2 = "Benchy_0.15mm_PLA_MINI_1h12m_final_v4"

local function listOf(keys)
  M.load({})
  for _, k in ipairs(keys) do
    PL.State.files[k] = { key = k, name = k, storage = "usb", path = "/" .. k .. ".bgcode" }
    PL.State.order[#PL.State.order + 1] = k
  end
  PL.applyFiles()
  return M.ctl("Files").Choices
end

function test_long_names_are_shortened_in_the_list()
  local c = listOf({ LONG1, "short" })
  assert(utf8.len(c[1]) <= 24 and c[1]:sub(-3) == "…", c[1])
  assert(c[2] == "short")
end

function test_shortened_names_stay_distinct_and_open_the_right_file()
  local c = listOf({ LONG1, LONG2 })
  assert(c[1] ~= c[2] and utf8.len(c[2]) <= 24, c[1] .. " / " .. c[2])
  M.ctl("Files").String = c[2]; M.press("Files")
  assert(PL.State.selected == LONG2)
end
