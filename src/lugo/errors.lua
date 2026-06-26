---@class lugo.Error
---@field message string Human-readable error message.
---@field kind? string Stable machine-readable category.
---@field cause? lugo.Error Wrapped lower-level error.
---@field stack? string Lua stack traceback captured when the error was created.
---@field fields? table<string, any> Additional structured context.
---@field _lugo_error true

---@class lugo.ErrorOptions
---@field kind? string Stable machine-readable category.
---@field cause? lugo.Error|string Wrapped lower-level error.
---@field stack? boolean|string Capture a stack traceback when true, or use the provided traceback string.
---@field fields? table<string, any> Additional structured context.

---@class lugo.Panic
---@field error lugo.Error
---@field _lugo_panic true

---@class lugo.errors
local errors = {}

local Error = {}
Error.__index = Error

local function pack(...)
    return { n = select("#", ...), ... }
end

---@param value any
---@return lugo.Error
local function normalize_error(value)
    if errors.is_error(value) then
        return value
    end

    return errors.new(tostring(value))
end

---@param value any
---@return boolean
function errors.is_error(value)
    return type(value) == "table" and value._lugo_error == true
end

---@param message string
---@param opts? lugo.ErrorOptions
---@return lugo.Error
function errors.new(message, opts)
    opts = opts or {}

    ---@type lugo.Error
    local err = {
        message = message,
        kind = opts.kind,
        cause = opts.cause and normalize_error(opts.cause) or nil,
        fields = opts.fields,
        _lugo_error = true,
    }

    local stack = opts.stack
    if stack == true then
        err.stack = debug.traceback(message, 2)
    elseif type(stack) == "string" then
        err.stack = stack
    end

    return setmetatable(err, Error)
end

---@param err lugo.Error|string
---@param message string
---@param opts? lugo.ErrorOptions
---@return lugo.Error
function errors.wrap(err, message, opts)
    opts = opts or {}
    opts.cause = normalize_error(err)
    return errors.new(message, opts)
end

---@param err lugo.Error|string|nil
---@param target lugo.Error|string
---@return boolean
function errors.is(err, target)
    if err == nil then
        return false
    end

    local current = normalize_error(err)
    local target_error = normalize_error(target)

    while current do
        if current == target_error then
            return true
        end

        if current.kind ~= nil and current.kind == target_error.kind then
            return true
        end

        if current.message == target_error.message then
            return true
        end

        current = current.cause
    end

    return false
end

---@param err lugo.Error|string|nil
---@param kind string
---@return lugo.Error|nil
function errors.as(err, kind)
    if err == nil then
        return nil
    end

    local current = normalize_error(err)
    while current do
        if current.kind == kind then
            return current
        end
        current = current.cause
    end

    return nil
end

---@param ... lugo.Error|string|nil
---@return lugo.Error|nil
function errors.join(...)
    local joined = {}

    for i = 1, select("#", ...) do
        local err = select(i, ...)
        if err ~= nil then
            joined[#joined + 1] = normalize_error(err)
        end
    end

    if #joined == 0 then
        return nil
    end

    if #joined == 1 then
        return joined[1]
    end

    return errors.new("multiple errors", {
        kind = "multiple",
        fields = { errors = joined },
    })
end

---@param err lugo.Error|string
function errors.panic(err)
    error({
        error = normalize_error(err),
        _lugo_panic = true,
    }, 0)
end

---@generic T
---@param value T|nil
---@param err? lugo.Error|string
---@return T
function errors.check(value, err)
    if err ~= nil then
        errors.panic(err)
    end

    return value
end

---@generic T
---@param fn fun(): T
---@return T|nil value
---@return lugo.Error|nil err
function errors.catch(fn)
    local values = pack(xpcall(fn, function(panic)
        if type(panic) == "table" and panic._lugo_panic == true then
            return panic.error
        end

        return errors.new(tostring(panic), {
            kind = "panic",
            stack = debug.traceback(tostring(panic), 2),
        })
    end))

    local ok = values[1]
    if not ok then
        return nil, values[2]
    end

    return values[2], nil
end

---@return string
function Error:__tostring()
    return self.message
end

return errors
