---@class lugo
---@field errors lugo.errors
---@field context lugo.context
---@field new_error fun(message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field wrap_error fun(err: lugo.Error|string, message: string, opts?: lugo.ErrorOptions): lugo.Error
---@field check fun(value: any, err?: lugo.Error|string): any
---@field catch fun(fn: fun(): any): any, lugo.Error|nil
---@field panic fun(err: lugo.Error|string)
local lugo = {}

lugo.errors = require("lugo.errors")
lugo.context = require("lugo.context")

lugo.new_error = lugo.errors.new
lugo.wrap_error = lugo.errors.wrap
lugo.check = lugo.errors.check
lugo.catch = lugo.errors.catch
lugo.panic = lugo.errors.panic

return lugo
