---@class lugo_uv.TimerHandle: lugo.TimerHandle
---@field driver lugo_uv.Driver
---@field handle uv.uv_timer_t
---@field active boolean
local TimerHandle = {}
TimerHandle.__index = TimerHandle

---@class lugo_uv.Driver: lugo.SchedulerDriver
---@field uv uv
---@field pending integer
---@field closed boolean
---@field timers lugo_uv.TimerHandle[]
local Driver = {}
Driver.__index = Driver

---@class lugo_uv
---@field driver fun(): lugo_uv.Driver|nil, lugo.Error|nil
local lugo_uv = {}

local errors = require("lugo.errors")

---@return uv|nil uv
---@return lugo.Error|nil err
local function load_uv()
  local ok, loaded = pcall(require, "luv")
  if ok then
    ---@cast loaded uv
    return loaded, nil
  end

  return nil, errors.new("failed to load luv", {
    kind = "uv_load_failed",
    fields = { error = tostring(loaded) },
  })
end

---@param driver lugo_uv.Driver
local function decrement_pending(driver)
    if driver.pending > 0 then
        driver.pending = driver.pending - 1
    end
end

---@return number
function Driver:now()
    return self.uv.hrtime() / 1000000000
end

---@param deadline number
---@param callback fun()
---@return lugo_uv.TimerHandle|nil
---@return lugo.Error|nil
function Driver:call_at(deadline, callback)
  if self.closed then
    error("lugo_uv driver is closed", 2)
  end

  local timer, timer_err = self.uv.new_timer()
  if timer == nil then
    return nil, errors.new("failed to create uv timer", {
      kind = "uv_timer_create_failed",
      fields = { error = timer_err },
    })
  end

  ---@type lugo_uv.TimerHandle
  local timer_handle = setmetatable({
        driver = self,
        handle = timer,
        active = true,
    }, TimerHandle)

    self.pending = self.pending + 1
    self.timers[#self.timers + 1] = timer_handle

    local delay = deadline - self:now()
    if delay < 0 then
        delay = 0
    end

  local delay_ms = math.ceil(delay * 1000)

  local ok, start_err = timer:start(delay_ms, 0, function()
    if not timer_handle.active then
      return
    end

        timer_handle.active = false
        decrement_pending(self)
        timer:stop()
    timer:close()
    callback()
  end)

  if ok == nil then
    timer_handle.active = false
    decrement_pending(self)
    if not timer:is_closing() then
      timer:close()
    end
    return nil, errors.new("failed to start uv timer", {
      kind = "uv_timer_start_failed",
      fields = { error = start_err },
    })
  end

  return timer_handle, nil
end

function Driver:run_once()
    if self.closed or self.pending == 0 then
        return
    end

    self.uv.run("once")
end

---@return boolean
function Driver:has_pending()
    return not self.closed and self.pending > 0
end

function Driver:close()
    if self.closed then
        return
    end

    self.closed = true

    for i = 1, #self.timers do
        self.timers[i]:cancel()
    end

    self.timers = {}
end

function TimerHandle:cancel()
    if not self.active then
        return
    end

    self.active = false
    decrement_pending(self.driver)

    if not self.handle:is_closing() then
        self.handle:stop()
        self.handle:close()
    end
end

---@return lugo_uv.Driver|nil driver
---@return lugo.Error|nil err
function lugo_uv.driver()
    local uv, err = load_uv()
    if uv == nil then
        return nil, err
    end

    return setmetatable({
        uv = uv,
        pending = 0,
        closed = false,
        timers = {},
    }, Driver), nil
end

return lugo_uv
