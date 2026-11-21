-- Offline test runner for the PrusaLink plugin.
-- Usage (from the repo root): lua5.3 tests/run.lua [pattern]
-- Runs every test_* function in every tests/test_*.lua and exits 1 on any failure.

package.path = "./tests/?.lua;" .. package.path
M = require("mocks")
local function say(s) io.stdout:write(s, "\n") end

local filter = arg and arg[1]
local files = {}
local p = io.popen('ls tests/test_*.lua 2>/dev/null')
for f in p:lines() do files[#files + 1] = f end
p:close()
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
  local env = setmetatable({}, { __index = _G })
  local chunk, err = loadfile(file, "t", env)
  if not chunk then
    say("FAIL " .. file .. ": " .. err); failed = failed + 1
  else
    chunk()
    local names = {}
    for k, v in pairs(env) do
      if type(v) == "function" and k:match("^test_") and (not filter or k:find(filter, 1, true)) then
        names[#names + 1] = k
      end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local ok, msg = xpcall(env[name], debug.traceback)
      if ok then
        passed = passed + 1; say("PASS " .. name)
      else
        failed = failed + 1; say("FAIL " .. name .. ": " .. tostring(msg))
      end
    end
  end
end

say(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
