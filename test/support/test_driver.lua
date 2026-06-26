---@class lugo.TestDriver: lugo.SchedulerDriver
---@field time number
---@field timers lugo.TestTimerHandle[]
local TestDriver = {}
TestDriver.__index = TestDriver

---@class lugo.TestTimerHandle: lugo.TimerHandle
---@field driver lugo.TestDriver
---@field deadline number
---@field callback fun()
---@field canceled boolean
local TestTimerHandle = {}
TestTimerHandle.__index = TestTimerHandle

---@return lugo.TestDriver
local function new()
  return setmetatable({ time = 0, timers = {} }, TestDriver)
end

---@return number
function TestDriver:now()
  return self.time
end

---@param deadline number
---@param callback fun()
---@return lugo.TimerHandle
function TestDriver:call_at(deadline, callback)
  local handle = setmetatable({
    driver = self,
    deadline = deadline,
    callback = callback,
    canceled = false,
  }, TestTimerHandle)

  self.timers[#self.timers + 1] = handle
  return handle
end

function TestTimerHandle:cancel()
  self.canceled = true
end

---@param seconds number
function TestDriver:advance(seconds)
  self.time = self.time + seconds
  self:fire_due()
end

function TestDriver:fire_due()
  local remaining = {}
  for i = 1, #self.timers do
    local timer = self.timers[i]
    if timer.canceled then
      -- drop it
    elseif timer.deadline <= self.time then
      timer.canceled = true
      timer.callback()
    else
      remaining[#remaining + 1] = timer
    end
  end
  self.timers = remaining
end

---@return lugo.TestTimerHandle|nil
function TestDriver:next_timer()
  local next_timer = nil
  for i = 1, #self.timers do
    local timer = self.timers[i]
    if not timer.canceled and (next_timer == nil or timer.deadline < next_timer.deadline) then
      next_timer = timer
    end
  end
  return next_timer
end

function TestDriver:run_once()
  local timer = self:next_timer()
  if timer ~= nil then
    if timer.deadline > self.time then
      self.time = timer.deadline
    end
    self:fire_due()
  end
end

---@return boolean
function TestDriver:has_pending()
  return self:next_timer() ~= nil
end

return {
  new = new,
}
