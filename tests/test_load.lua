-- The plugin file loads cleanly in both the design-time and runtime contexts.

function test_design_functions_run_for_every_page()
  M.load({})
  local ctrls = GetControls({})
  assert(#ctrls > 0)
  for i, page in ipairs({ "Monitor", "Control", "Setup" }) do
    local layout, graphics = GetControlLayout({ page_index = { Value = i } })
    assert(type(layout) == "table" and type(graphics) == "table", page)
  end
end

function test_runtime_loads_and_exposes_PL()
  M.load({})
  assert(type(PL) == "table", "PL global table missing")
end
