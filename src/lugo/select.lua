---@alias lugo.select.CaseKind "send"|"recv"|"default"

---@class lugo.select.Case<R>
---@field kind lugo.select.CaseKind
---@field channel? lugo.Channel<any>
---@field value? any
---@field callback fun(...): R

---@class lugo.select
local select_module = {}

local errors = require("lugo.errors")
local scheduler = require("lugo.scheduler")

select_module.ErrNoCases = errors.new("select requires at least one case", {
    kind = "select_no_cases",
})

select_module.ErrInvalidCase = errors.new("invalid select case", {
    kind = "select_invalid_case",
})

---@generic T, R
---@param ch lugo.Channel<T>
---@param callback fun(value: T|nil, ok: boolean): R
---@return lugo.select.Case<R>
function select_module.recv(ch, callback)
    return {
        kind = "recv",
        channel = ch,
        callback = callback,
    }
end

---@generic T, R
---@param ch lugo.Channel<T>
---@param value T
---@param callback fun(): R
---@return lugo.select.Case<R>
function select_module.send(ch, value, callback)
    return {
        kind = "send",
        channel = ch,
        value = value,
        callback = callback,
    }
end

---@generic R
---@param callback fun(): R
---@return lugo.select.Case<R>
function select_module.default(callback)
    return {
        kind = "default",
        callback = callback,
    }
end

---@param cases lugo.select.Case<any>[]
---@return lugo.Error|nil
local function validate_cases(cases)
    if #cases == 0 then
        return select_module.ErrNoCases
    end

    local default_seen = false
    for i = 1, #cases do
        local case = cases[i]
        if type(case) ~= "table" or type(case.callback) ~= "function" then
            return errors.wrap(select_module.ErrInvalidCase, "select case must have a callback", {
                fields = { case_index = i },
            })
        end

        if case.kind == "default" then
            if default_seen then
                return errors.wrap(select_module.ErrInvalidCase, "select can have at most one default case", {
                    fields = { case_index = i },
                })
            end
            default_seen = true
        elseif case.kind == "send" or case.kind == "recv" then
            if case.channel == nil then
                return errors.wrap(select_module.ErrInvalidCase, "channel select case must have a channel", {
                    fields = { case_index = i },
                })
            end
        else
            return errors.wrap(select_module.ErrInvalidCase, "unknown select case kind", {
                fields = { case_index = i, kind = case.kind },
            })
        end
    end

    return nil
end

---@generic R
---@param cases lugo.select.Case<R>[]
---@return R|nil result
---@return lugo.Error|nil err
function select_module.select(cases)
    local validation_err = validate_cases(cases)
    if validation_err ~= nil then
        return nil, validation_err
    end

    if scheduler.current() == nil then
        return nil, scheduler.ErrNoScheduler
    end

    ---@type lugo.scheduler.SelectOp<any>
    local op = { kind = "select", cases = cases }
    local selected, value, ok, err = coroutine.yield(op)
    if err ~= nil then
        return nil, err
    end

    local case = cases[selected]
    if case.kind == "recv" then
        return case.callback(value, ok), nil
    end

    return case.callback(), nil
end

return select_module
