---@class lugo
---@field errors lugo.errors
---@field context lugo.context
---@field scheduler lugo.scheduler
---@field testing lugo.testing
---@field new_error fun(message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field wrap_error fun(err: lugo.Error|string, message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field check fun(value: any, err?: lugo.Error|string): any
---@field catch fun(fn: fun(): any): any, lugo.Error|nil
---@field panic fun(err: lugo.Error|string)
local lugo = {}

lugo.errors = require("lugo.errors")
lugo.context = require("lugo.context")
lugo.scheduler = require("lugo.scheduler")
lugo.testing = require("lugo.testing")

lugo.new_error = lugo.errors.new
lugo.wrap_error = lugo.errors.wrap
lugo.check = lugo.errors.check
lugo.catch = lugo.errors.catch
lugo.panic = lugo.errors.panic

---@param fn fun(...): any
---@param opts? lugo.SchedulerOptions
---@return any value
---@return lugo.Error|nil err
function lugo.run(fn, opts)
    return lugo.scheduler.run(fn, opts)
end

---@param fn fun(...): any
---@param ... any
---@return lugo.Task|nil task
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

---@return lugo.Task|nil
function lugo.current()
    return lugo.scheduler.current()
end

return lugo
