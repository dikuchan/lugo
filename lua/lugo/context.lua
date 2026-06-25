---@class lugo.Done
---@field closed boolean
local Done = {}
Done.__index = Done

---@return lugo.Done
local function new_done()
  return setmetatable({ closed = false }, Done)
end

---@return boolean
function Done:is_closed()
  return self.closed
end

function Done:close()
  self.closed = true
end

---@class lugo.Context
---@field parent? lugo.Context
---@field done_signal lugo.Done
---@field err_value? lugo.Error
---@field deadline_value? number
---@field values? table<any, any>
---@field children lugo.Context[]
local Context = {}
Context.__index = Context

local errors = require("lugo.errors")

---@class lugo.context
---@field CANCELED lugo.Error
---@field DEADLINE_EXCEEDED lugo.Error
local context = {}

context.CANCELED = errors.new("context canceled", { kind = "context_canceled" })
context.DEADLINE_EXCEEDED = errors.new("context deadline exceeded", {
  kind = "context_deadline_exceeded",
})

---@param ctx lugo.Context
---@param err lugo.Error
local function cancel_context(ctx, err)
  if ctx.err_value ~= nil then
    return
  end

  ctx.err_value = err
  ctx.done_signal:close()

  for i = 1, #ctx.children do
    cancel_context(ctx.children[i], err)
  end
end

---@param parent? lugo.Context
---@param deadline? number
---@param values? table<any, any>
---@return lugo.Context
local function new_context(parent, deadline, values)
  ---@type lugo.Context
  local ctx = {
    parent = parent,
    done_signal = new_done(),
    deadline_value = deadline,
    values = values,
    children = {},
  }

  setmetatable(ctx, Context)

  if parent ~= nil then
    parent.children[#parent.children + 1] = ctx
    local parent_err = parent:err()
    if parent_err ~= nil then
      cancel_context(ctx, parent_err)
    end
  end

  return ctx
end

---@return lugo.Error|nil
function Context:err()
  if self.err_value ~= nil then
    return self.err_value
  end

  if self.parent ~= nil then
    local parent_err = self.parent:err()
    if parent_err ~= nil then
      cancel_context(self, parent_err)
      return parent_err
    end
  end

  if self.deadline_value ~= nil and os.time() >= self.deadline_value then
    cancel_context(self, context.DEADLINE_EXCEEDED)
    return self.err_value
  end

  return nil
end

---@return lugo.Done
function Context:done()
  self:err()
  return self.done_signal
end

---@param key any
---@return any
function Context:value(key)
  local values = self.values
  if values ~= nil and values[key] ~= nil then
    return values[key]
  end

  if self.parent ~= nil then
    return self.parent:value(key)
  end

  return nil
end

---@return number|nil
function Context:deadline()
  return self.deadline_value
end

---@return lugo.Context
function context.background()
  return new_context()
end

---@return lugo.Context
function context.todo()
  return new_context()
end

---@alias lugo.CancelFunc fun()

---@param parent lugo.Context
---@return lugo.Context ctx
---@return lugo.CancelFunc cancel
function context.with_cancel(parent)
  local ctx = new_context(parent)

  return ctx, function()
    cancel_context(ctx, context.CANCELED)
  end
end

---@param parent lugo.Context
---@param deadline number Unix timestamp in seconds.
---@return lugo.Context ctx
---@return lugo.CancelFunc cancel
function context.with_deadline(parent, deadline)
  local ctx = new_context(parent, deadline)

  if os.time() >= deadline then
    cancel_context(ctx, context.DEADLINE_EXCEEDED)
  end

  return ctx, function()
    cancel_context(ctx, context.CANCELED)
  end
end

---@param parent lugo.Context
---@param seconds number
---@return lugo.Context ctx
---@return lugo.CancelFunc cancel
function context.with_timeout(parent, seconds)
  return context.with_deadline(parent, os.time() + seconds)
end

---@param parent lugo.Context
---@param key any
---@param value any
---@return lugo.Context
function context.with_value(parent, key, value)
  return new_context(parent, nil, { [key] = value })
end

---@param err lugo.Error|nil
---@return boolean
function context.is_canceled(err)
  return errors.is(err, context.CANCELED)
end

---@param err lugo.Error|nil
---@return boolean
function context.is_deadline_exceeded(err)
  return errors.is(err, context.DEADLINE_EXCEEDED)
end

return context
