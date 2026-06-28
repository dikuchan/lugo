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

local select_module = require("lugo.select")
local struct_module = require("lugo.struct")

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

---@generic T, R
---@param ch lugo.Channel<T>
---@param callback fun(value: T|nil, ok: boolean): R
---@return lugo.select.Case<R>
function lugo.recv(ch, callback)
    return select_module.recv(ch, callback)
end

---@generic T, R
---@param ch lugo.Channel<T>
---@param value T
---@param callback fun(): R
---@return lugo.select.Case<R>
function lugo.send(ch, value, callback)
    return select_module.send(ch, value, callback)
end

---@generic R
---@param callback fun(): R
---@return lugo.select.Case<R>
function lugo.default(callback)
    return select_module.default(callback)
end

---@generic R
---@param cases lugo.select.Case<R>[]
---@return R|nil result
---@return lugo.Error|nil err
function lugo.select(cases)
    return select_module.select(cases)
end

lugo.any = struct_module.any
lugo.string = struct_module.string
lugo.number = struct_module.number
lugo.boolean = struct_module.boolean
lugo.table = struct_module.table
lugo.function_ = struct_module.function_

---@generic T
---@param validator lugo.Validator<T>
---@return lugo.Validator<T|nil>
function lugo.optional(validator)
    return struct_module.optional(validator)
end

---@generic T
---@param name string
---@param fields lugo.StructFields
---@return lugo.Struct<T>
function lugo.struct(name, fields)
    return struct_module.struct(name, fields)
end

---@generic T
---@param name string
---@param members lugo.StructFields
---@return lugo.Interface<T>
function lugo.interface(name, members)
    return struct_module.interface(name, members)
end

return lugo
