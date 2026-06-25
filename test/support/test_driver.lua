---@class lugo.TestDriver: lugo.SchedulerDriver
---@field time number
local TestDriver = {}
TestDriver.__index = TestDriver

---@return lugo.TestDriver
local function new()
  return setmetatable({ time = 0 }, TestDriver)
end

---@return number
function TestDriver:now()
  return self.time
end

---@param deadline? number
function TestDriver:wait_until(deadline)
  if deadline ~= nil and deadline > self.time then
    self.time = deadline
  end
end

function TestDriver:wake()
end

---@param seconds number
function TestDriver:advance(seconds)
  self.time = self.time + seconds
end

return {
  new = new,
}
