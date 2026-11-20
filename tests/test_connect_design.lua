-- Prusa Connect plugin: design-time pieces (info, properties, pages, controls, layout).

local function names(ctrls)
  local s = {}
  for _, c in ipairs(ctrls) do s[c.Name] = c end
  return s
end

local PAGES = { "Farm", "Monitor", "Files", "Control", "Setup" }
local function page(name)
  for i, p in ipairs(PAGES) do if p == name then return i end end
end
local function layoutFor(name, props)
  return GetControlLayout({ page_index = { Value = page(name) },
                            ["Printer Slots"] = { Value = (props or {}).slots or 6 } })
end

function test_connect_plugin_info()
  M.loadConnect({})
  assert(PluginInfo.Name == "Prusa Connect")
  assert(PluginInfo.Version == "1.0")
  assert(PluginInfo.Id == "a7a231d2-d4ba-4590-a9d5-5fb832fb9007")
end

function test_connect_pages_in_order()
  M.loadConnect({})
  local pages = GetPages({})
  assert(#pages == 5)
  for i, n in ipairs(PAGES) do assert(pages[i].name == n, pages[i].name) end
end

function test_connect_properties()
  M.loadConnect({})
  local p = {}
  for _, x in ipairs(GetProperties()) do p[x.Name] = x end
  assert(p["Poll Interval"].Value == 5 and p["Poll Interval"].Min == 1 and p["Poll Interval"].Max == 60)
  assert(p["Debug"].Value == false)
  assert(p["Printer Slots"].Value == 6 and p["Printer Slots"].Min == 1 and p["Printer Slots"].Max == 8)
  assert(p["Use HTTPS"].Value == false)
end

function test_connect_printer_slot_controls_follow_property()
  M.loadConnect({})
  local s = names(GetControls({ ["Printer Slots"] = { Value = 3 } }))
  for i = 1, 3 do
    assert(s["Printer " .. i] and s["Printer " .. i].ControlType == "Button", "Printer " .. i)
    assert(s["Printer " .. i .. " Status"], "Printer " .. i .. " Status")
  end
  assert(s["Printer 4"] == nil)
end

function test_connect_controls_present()
  M.loadConnect({})
  local s = names(GetControls({ ["Printer Slots"] = { Value = 6 } }))
  for _, n in ipairs({
    -- setup / farm
    "Server Address", "API Token", "Online", "Farm Status", "Selected Printer",
    -- monitor (as PrusaLink)
    "Status", "Job", "Progress", "Nozzle Temp", "Nozzle Target", "Bed Temp", "Bed Target",
    "Z Height", "Print Speed", "Material", "nGraph", "bGraph",
    "Axis 300C", "Axis 225C", "Axis 150C", "Axis 75C", "Axis 0C",
    "Progress Image", "Progress Overlay", "View Toggle",
    -- files (PrusaLink's control page)
    "Files", "Print", "Pause", "Stop", "Delete", "Preview", "Preview Image", "Preview Details",
    -- new control page
    "Nozzle Setpoint", "Bed Setpoint", "Set Nozzle", "Set Bed", "Preset PLA", "Preset PETG",
    "Cooldown", "Step 0.1", "Step 1", "Step 10", "X-", "X+", "Y-", "Y+", "Z-", "Z+",
    "Home All", "Motors Off", "Control Status" }) do
    assert(s[n], n)
  end
  for _, gone in ipairs({ "Printer IP", "Username", "Password", "API Key" }) do
    assert(s[gone] == nil, gone .. " should not exist")
  end
end

function test_connect_farm_layout_has_one_row_per_slot()
  M.loadConnect({})
  local l = layoutFor("Farm", { slots = 4 })
  for i = 1, 4 do
    assert(l["Printer " .. i] and l["Printer " .. i .. " Status"], "row " .. i)
  end
  assert(l["Printer 5"] == nil)
  assert(l["Printer 2"].Position[2] - l["Printer 1"].Position[2] == 46)
  assert(l["Farm Status"])
end

function test_connect_selected_printer_shown_on_printer_pages()
  M.loadConnect({})
  for _, p in ipairs({ "Monitor", "Files", "Control" }) do
    assert(layoutFor(p)["Selected Printer"], p)
  end
  assert(layoutFor("Farm")["Selected Printer"] == nil)
end

function test_connect_page_contents()
  M.loadConnect({})
  local want = {
    Monitor = { "Status", "Job", "Nozzle Temp", "nGraph", "View Toggle" },
    Files   = { "Files", "Print", "Delete", "Pause", "Stop", "Preview" },
    Control = { "Set Nozzle", "Set Bed", "Preset PLA", "Cooldown", "Step 1", "X+", "Z-", "Home All", "Motors Off", "Control Status" },
    Setup   = { "Server Address", "API Token", "Online" },
  }
  for p, ns in pairs(want) do
    local l = layoutFor(p)
    for _, n in ipairs(ns) do assert(l[n], p .. ": " .. n) end
  end
end

function test_connect_runtime_loads()
  M.loadConnect({})
  assert(type(PC) == "table")
  assert(PL == nil, "Connect plugin uses its own PC namespace")
end
