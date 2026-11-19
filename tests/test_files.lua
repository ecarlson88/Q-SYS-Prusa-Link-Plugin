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

function test_refresh_lists_available_storages_only()
  setup(); PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200, M.fixture("storage.json"))
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
    '{"name":"usb","type":"FOLDER","children":[{"name":"my parts","type":"FOLDER"}]}')
  local i = M.find("/api/v1/files/usb/my%20parts/")
  M.respond(i, 200, '{"name":"my parts","type":"FOLDER","children":[{"name":"a b.gcode","type":"PRINT_FILE"}]}')
  local e = PL.State.files["my parts/a b"]
  assert(e and e.path == "/my parts/a b.gcode")
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
  PL.refreshFiles()
  M.respond(M.find("/api/v1/storage"), 200,
    '{"storage_list":[{"path":"/usb","name":"usb","available":true,"read_only":false}]}')
  M.respond(M.find("/api/v1/files/usb/"), 200, '{"children":[{"name":"new.gcode","type":"PRINT_FILE"}]}')
  local c = M.ctl("Files").Choices
  assert(#c == 1 and c[1] == "new", table.concat(c, ","))
end
