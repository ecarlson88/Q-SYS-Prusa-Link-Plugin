-- Design-time pieces: plugin info, properties, controls.

local function names(ctrls)
  local s = {}
  for _, c in ipairs(ctrls) do s[c.Name] = c end
  return s
end

function test_plugin_info()
  M.load({})
  assert(PluginInfo.Version == "1.0" and PluginInfo.BuildVersion == "1.0.0.0")
  assert(PluginInfo.Id == "e778394d-6e3d-2489-be94-bcb44ts1c76e")
end

function test_properties()
  M.load({})
  local p = {}
  for _, x in ipairs(GetProperties()) do p[x.Name] = x end
  assert(p["Poll Interval"], "Poll Interval missing")
  assert(p["Poll Interval"].Value == 5 and p["Poll Interval"].Min == 1 and p["Poll Interval"].Max == 60)
  assert(p["Debug"] and p["Debug"].Value == false)
end

function test_controls_added_and_api_key_removed()
  M.load({})
  local s = names(GetControls({}))
  for _, n in ipairs({ "Username", "Password", "Preview", "Preview Image", "Preview Details",
                       "Progress Image", "Progress Overlay", "View Toggle" }) do
    assert(s[n], n)
  end
  assert(s["API Key"] == nil, "API Key should be removed")
end

function test_existing_controls_kept()
  M.load({})
  local s = names(GetControls({}))
  for _, n in ipairs({ "Print", "Pause", "Stop", "Delete", "Online", "nGraph", "bGraph", "Job", "Progress",
                       "Status", "Material", "Printer IP", "Nozzle Temp", "Nozzle Target", "Bed Temp",
                       "Bed Target", "Z Height", "Print Speed", "Files" }) do
    assert(s[n], n)
  end
end

function test_new_controls_laid_out_on_their_pages()
  M.load({})
  local want = { Setup = { "Username", "Password" },
                 Control = { "Preview", "Preview Image", "Preview Details" },
                 Monitor = { "Progress Image", "Progress Overlay", "View Toggle" } }
  for i, page in ipairs({ "Monitor", "Control", "Setup" }) do
    local layout = GetControlLayout({ page_index = { Value = i } })
    for _, n in ipairs(want[page]) do assert(layout[n], page .. ": " .. n) end
  end
end

function test_username_defaults_to_maker()
  M.load({})
  assert(M.ctl("Username").String == "maker")
end

-- Hardware check: the progress controls drew a black box over the graph's
-- °C axis labels (graphics at ZOrder 101-105) on the Monitor page.
function test_progress_controls_hidden_at_start()
  M.load({})
  assert(M.ctl("Progress Image").IsInvisible == true)
  assert(M.ctl("Progress Overlay").IsInvisible == true)
end

function test_progress_controls_sit_below_axis_labels()
  M.load({})
  local layout = GetControlLayout({ page_index = { Value = 1 } })
  assert(layout["Progress Image"].ZOrder < 101 and layout["Progress Overlay"].ZOrder < 101)
  assert(layout["Progress Overlay"].ZOrder > layout["Progress Image"].ZOrder)
end

-- Hidden-by-default controls are hidden in the layout too, so they never flash
-- on screen (or show in Designer) before the runtime script hides them.
function test_hidden_controls_start_invisible_in_layout()
  M.load({})
  local mon = GetControlLayout({ page_index = { Value = 1 } })
  local ctl = GetControlLayout({ page_index = { Value = 2 } })
  for _, n in ipairs({ "Progress Image", "Progress Overlay" }) do assert(mon[n].IsInvisible == true, n) end
  for _, n in ipairs({ "Preview", "Preview Image", "Preview Details" }) do assert(ctl[n].IsInvisible == true, n) end
end

-- The graph's °C axis labels are controls (not graphics) so the progress
-- view can hide them. Same text, positions and style as the old graphics.
local AXIS = {
  { "Axis 300C", "300°C", { 23, 153 } },
  { "Axis 225C", "225°C", { 22, 190 } },
  { "Axis 150C", "150°C", { 22, 228 } },
  { "Axis 75C",  "75°C",  { 22, 266 } },
  { "Axis 0C",   "0°C",   { 22, 303 } },
}

function test_axis_labels_are_controls_not_graphics()
  M.load({})
  local layout, graphics = GetControlLayout({ page_index = { Value = 1 } })
  for _, a in ipairs(AXIS) do
    local l = layout[a[1]]
    assert(l, a[1] .. " missing from layout")
    assert(l.Position[1] == a[3][1] and l.Position[2] == a[3][2], a[1] .. " moved")
    assert(l.IsReadOnly == true and l.TextBoxStyle == "NoBackground")
  end
  for _, g in ipairs(graphics) do
    assert(not (g.Type == "Text" and tostring(g.Text):find("°C$") and g.FontSize == 9),
           "axis label still a graphic: " .. tostring(g.Text))
  end
end

function test_axis_labels_show_their_text_at_start()
  M.load({})
  for _, a in ipairs(AXIS) do
    assert(M.ctl(a[1]).String == a[2], a[1] .. " = " .. M.ctl(a[1]).String)
    assert(M.ctl(a[1]).IsInvisible == false)
  end
end
