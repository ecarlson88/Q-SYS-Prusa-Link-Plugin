-- Mocked Q-SYS globals so the real PrusaLink.qplug can be loaded and driven offline.
-- Only what the plugin uses is mocked: Controls, Properties, Timer, HttpClient,
-- rapidjson (backed by dkjson), EzSVG (stub), Crypto.Base64Encode and print.

local dkjson = require("dkjson")

local M = {}
M.PLUGIN = "PrusaLink/PrusaLink.qplug"

---------------------------------------------------------------------------
-- rapidjson / EzSVG / Crypto
---------------------------------------------------------------------------

local rapidjson = {
  encode = function(v) return dkjson.encode(v) end,
  decode = function(s)
    local obj, _, err = dkjson.decode(s, 1, nil)
    if err then return nil, err end
    return obj
  end,
}
package.preload["rapidjson"] = function() return rapidjson end

local function svgStub()
  local o
  o = setmetatable({}, { __index = function(_, k)
    if k == "toString" then return function() return "<svg/>" end end
    return function() return o end
  end })
  return o
end
package.preload["EzSVG"] = function() return svgStub() end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(data)
  return ((data:gsub(".", function(x)
    local r, b = "", x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return b64chars:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end
M.base64 = base64

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function newControl(name)
  local store = { Name = name, String = "", Value = 0, Position = 0, Boolean = false,
                  IsInvisible = false, Legend = "", Choices = {} }
  local ctl = {}
  setmetatable(ctl, {
    __index = store,
    __newindex = function(_, k, v)
      store[k] = v
      if k == "Value" then
        store.String = tostring(v)
        store.Boolean = (v ~= 0)
      elseif k == "Boolean" then
        store.Value = v and 1 or 0
      end
    end,
  })
  return ctl
end

---------------------------------------------------------------------------
-- Timer (virtual clock)
---------------------------------------------------------------------------

local clock, oneShots, timers

local function TimerNew()
  local t = { running = false }
  function t:Start(interval) self.interval = interval; self.next = clock + interval; self.running = true end
  function t:Stop() self.running = false end
  timers[#timers + 1] = t
  return t
end

function M.advance(seconds)
  local target = clock + seconds + 1e-9
  while true do
    local best, kind, idx = nil, nil, nil
    for i, s in ipairs(oneShots) do
      if s.at <= target and (not best or s.at < best) then best, kind, idx = s.at, "once", i end
    end
    for i, t in ipairs(timers) do
      if t.running and t.next <= target and (not best or t.next < best) then best, kind, idx = t.next, "timer", i end
    end
    if not best then break end
    clock = best
    if kind == "once" then
      local s = table.remove(oneShots, idx)
      s.fn()
    else
      local t = timers[idx]
      t.next = t.next + t.interval
      if t.EventHandler then t.EventHandler(t) end
    end
  end
  clock = target
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------

local function buildProperties(overrides)
  local props = {}
  if type(GetProperties) == "function" then
    for _, p in ipairs(GetProperties()) do props[p.Name] = { Value = p.Value } end
  end
  for k, v in pairs(overrides or {}) do props[k] = { Value = v } end
  return props
end

function M.load(overrides)
  clock, oneShots, timers = 0, {}, {}
  M.requests, M.logs = {}, {}
  PL, Controls, Properties = nil, nil, nil

  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    M.logs[#M.logs + 1] = table.concat(parts, " ")
  end
  Timer = {
    New = TimerNew,
    CallAfter = function(fn, delay) oneShots[#oneShots + 1] = { at = clock + (delay or 0), fn = fn } end,
  }
  HttpClient = { Download = function(t) M.requests[#M.requests + 1] = t end }
  Crypto = { Base64Encode = base64 }

  -- Pass 1: design-time functions only (Controls is nil, so the runtime block is skipped).
  assert(loadfile(M.PLUGIN, "t", _G))()
  Properties = buildProperties(overrides)

  local ctls = {}
  for _, c in ipairs(GetControls(Properties)) do ctls[c.Name] = newControl(c.Name) end
  Controls = ctls

  -- Pass 2: runtime.
  assert(loadfile(M.PLUGIN, "t", _G))()
end

---------------------------------------------------------------------------
-- Helpers for tests
---------------------------------------------------------------------------

function M.ctl(name)
  local c = Controls[name]
  assert(c, "no control named " .. tostring(name))
  return c
end

function M.press(name)
  local c = M.ctl(name)
  assert(c.EventHandler, "control has no EventHandler: " .. name)
  c.EventHandler(c)
end

function M.respond(i, code, body, headers)
  local r = M.requests[i]
  assert(r, "no request #" .. tostring(i))
  r.EventHandler(r, code, body, code == 0 and "timeout" or nil, headers or {})
end

function M.last() return M.requests[#M.requests] end

function M.fixture(name)
  local f = assert(io.open("tests/fixtures/" .. name, "rb"))
  local s = f:read("a"); f:close()
  return s
end

function M.legendIcon(name)
  local obj = rapidjson.decode(M.ctl(name).Legend)
  return obj and obj.IconData
end

return M
