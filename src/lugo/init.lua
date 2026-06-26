---@class lugo
---@field errors lugo.errors
---@field context lugo.context
---@field scheduler lugo.scheduler
---@field channel lugo.channel
---@field testing lugo.testing
---@field new_error fun(message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field wrap_error fun(err: lugo.Error|string, message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field panic fun(err: lugo.Error|string)
local lugo = {}

lugo.errors = require("lugo.errors")
lugo.context = require("lugo.context")
lugo.scheduler = require("lugo.scheduler")
lugo.channel = require("lugo.channel")
lugo.testing = require("lugo.testing")

lugo.new_error = lugo.errors.new
lugo.wrap_error = lugo.errors.wrap
lugo.panic = lugo.errors.panic

---@generic T
---@param value T|nil
---@param err? lugo.Error|string
---@return T
function lugo.check(value, err)
    return lugo.errors.check(value, err)
end

---@generic T
---@param fn fun(): T
---@return T|nil value
---@return lugo.Error|nil err
function lugo.catch(fn)
    return lugo.errors.catch(fn)
end

---@generic T
---@param fn fun(): T
---@param opts? lugo.SchedulerOptions
---@return T|nil value
---@return lugo.Error|nil err
function lugo.run(fn, opts)
    return lugo.scheduler.run(fn, opts)
end

---@generic T
---@overload fun(fn: fun(...), ...: any): lugo.Task<nil>|nil, lugo.Error|nil
---@param fn fun(...): T|nil
---@param ... any
---@return lugo.Task<T>|nil task
---@return lugo.Error|nil err
function lugo.go(fn, ...)
    return lugo.scheduler.go(fn, ...)
end

---@param seconds number
---@return nil
---@return lugo.Error|nil err
function lugo.sleep(seconds)
    return lugo.scheduler.sleep(seconds)
end

---@return nil
---@return lugo.Error|nil err
function lugo.yield()
    return lugo.scheduler.yield()
end

---@return lugo.Task<any>|nil
function lugo.current()
    return lugo.scheduler.current()
end

---@generic T
---@param capacity? integer
---@return lugo.Channel<T>
function lugo.chan(capacity)
    return lugo.channel.new(capacity)
end

return lugo
