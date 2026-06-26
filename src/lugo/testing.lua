---@class lugo.testing.Failure
---@field message string

---@class lugo.testing.Expectation
---@field called boolean
---@field message string

---@class lugo.testing.T
---@field name string
---@field failures lugo.testing.Failure[]
---@field logs string[]
---@field cleanups fun()[]
---@field expectations lugo.testing.Expectation[]
local T = {}
T.__index = T

---@class lugo.testing.Case
---@field name string
---@field fn lugo.testing.TestFunc

---@class lugo.testing.Runner
---@field tests lugo.testing.Case[]
local Runner = {}
Runner.__index = Runner

---@alias lugo.testing.TestFunc fun(t: lugo.testing.T)
---@alias lugo.testing.RegisterFunc fun(name: string, fn: lugo.testing.TestFunc)
---@alias lugo.testing.Register fun(test: lugo.testing.RegisterFunc)

---@class lugo.testing
---@field new fun(fn: lugo.testing.Register): lugo.testing.Runner
---@field run fun(module_names: string[]): boolean
local testing = {}

local errors = require("lugo.errors")
local unpack = _G["unpack"] or rawget(table, "unpack")

local FATAL = errors.new("fatal test failure", { kind = "testing_fatal" })

---@param value any
---@return boolean
local function is_fatal(value)
    return type(value) == "table" and value._lugo_panic == true and errors.is(value.error, FATAL)
end

---@param value any
---@return string
local function format_value(value)
    if type(value) == "string" then
        return ("%q"):format(value)
    end

    return tostring(value)
end

---@param ... any
---@return string
local function format_message(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

---@param name string
---@return lugo.testing.T
local function new_t(name)
    return setmetatable({
        name = name,
        failures = {},
        logs = {},
        cleanups = {},
        expectations = {},
    }, T)
end

---@param message? string
function T:fail(message)
    self.failures[#self.failures + 1] = {
        message = message or "failed",
    }
end

---@param message? string
function T:error(message)
    self:fail(message)
end

---@param message? string
function T:fatal(message)
    self:fail(message)
    errors.panic(FATAL)
end

---@param message? string
function T:pass(message)
    if message ~= nil then
        self:log(message)
    end
end

---@param value any
---@param message? string
function T:assert(value, message)
    if not value then
        self:fatal(message or "assertion failed")
    end
end

---@param value any
---@param message? string
function T:is_true(value, message)
    if value ~= true then
        self:fail(message or ("expected true, got " .. format_value(value)))
    end
end

---@param value any
---@param message? string
function T:is_false(value, message)
    if value ~= false then
        self:fail(message or ("expected false, got " .. format_value(value)))
    end
end

---@param actual any
---@param expected any
---@param message? string
function T:equal(actual, expected, message)
    if actual ~= expected then
        self:fail(message or ("expected " .. format_value(expected) .. ", got " .. format_value(actual)))
    end
end

---@param actual any
---@param expected any
---@param message? string
function T:not_equal(actual, expected, message)
    if actual == expected then
        self:fail(message or ("expected value different from " .. format_value(expected)))
    end
end

---@param value any
---@param message? string
function T:is_nil(value, message)
    if value ~= nil then
        self:fail(message or ("expected nil, got " .. format_value(value)))
    end
end

---@param value any
---@param message? string
function T:not_nil(value, message)
    if value == nil then
        self:fail(message or "expected non-nil value")
    end
end

---@param err lugo.Error|string|nil
---@param message? string
function T:no_error(err, message)
    if err ~= nil then
        self:fail(message or ("expected no error, got " .. tostring(err)))
    end
end

---@param err lugo.Error|string|nil
---@param target lugo.Error|string
---@param message? string
function T:error_is(err, target, message)
    if not errors.is(err, target) then
        self:fail(message or ("expected error " .. tostring(target) .. ", got " .. tostring(err)))
    end
end

---@param err lugo.Error|string|nil
---@param kind string
---@param message? string
function T:error_as(err, kind, message)
    if errors.as(err, kind) == nil then
        self:fail(message or ("expected error kind " .. kind .. ", got " .. tostring(err)))
    end
end

---@param ... any
function T:log(...)
    self.logs[#self.logs + 1] = format_message(...)
end

---@param fn fun()
function T:cleanup(fn)
    self.cleanups[#self.cleanups + 1] = fn
end

---@generic T
---@param fn fun(...): T
---@param message? string
---@return fun(...): T|nil
function T:expect(fn, message)
    ---@type lugo.testing.Expectation
    local expectation = {
        called = false,
        message = message or "expected callback was not called",
    }
    self.expectations[#self.expectations + 1] = expectation

    return function(...)
        local args = { n = select("#", ...), ... }
        expectation.called = true
        local ok, result = xpcall(function()
            return fn(unpack(args, 1, args.n))
        end, debug.traceback)

        if not ok then
            self:fail(result)
            return nil
        end

        return result
    end
end

---@return boolean
function T:failed()
    return #self.failures > 0
end

---@param t lugo.testing.T
local function check_expectations(t)
    for i = 1, #t.expectations do
        local expectation = t.expectations[i]
        if not expectation.called then
            t:fail(expectation.message)
        end
    end
end

---@param t lugo.testing.T
local function run_cleanups(t)
    for i = #t.cleanups, 1, -1 do
        local ok, err = xpcall(t.cleanups[i], debug.traceback)
        if not ok then
            t:fail(err)
        end
    end
end

---@param fn lugo.testing.Register
---@return lugo.testing.Runner
function testing.new(fn)
    local runner = setmetatable({ tests = {} }, Runner)

    ---@type lugo.testing.RegisterFunc
    local function register(name, test_fn)
        runner.tests[#runner.tests + 1] = {
            name = name,
            fn = test_fn,
        }
    end

    fn(register)
    return runner
end

---@param module_names string[]
---@return boolean ok
function testing.run(module_names)
    return testing.new(function(test)
        for i = 1, #module_names do
            local module_name = module_names[i]
            local ok, register = xpcall(function()
                return require(module_name)
            end, debug.traceback)

            if not ok then
                test(module_name .. ": require", function(t)
                    t:fatal(register)
                end)
            elseif type(register) ~= "function" then
                test(module_name .. ": require", function(t)
                    t:fatal("test module must return a registration function")
                end)
            else
                ---@type lugo.testing.Register
                local typed_register = register
                typed_register(function(name, fn)
                    test(module_name .. ": " .. name, fn)
                end)
            end
        end
    end):run()
end

---@return boolean ok
function Runner:run()
    print("1.." .. tostring(#self.tests))

    local ok = true
    for i = 1, #self.tests do
        local test_case = self.tests[i]
        local t = new_t(test_case.name)

        local ran, err = xpcall(function()
            test_case.fn(t)
        end, debug.traceback)

        if not ran and not is_fatal(err) then
            t:fail(err)
        end

        check_expectations(t)
        run_cleanups(t)

        if t:failed() then
            ok = false
            print("not ok " .. tostring(i) .. " - " .. test_case.name)
            for j = 1, #t.failures do
                print("# " .. t.failures[j].message)
            end
        else
            print("ok " .. tostring(i) .. " - " .. test_case.name)
        end

        for j = 1, #t.logs do
            print("# " .. t.logs[j])
        end
    end

    return ok
end

---@param fn lugo.testing.Register
---@return boolean ok
local function call(_, fn)
    return testing.new(fn):run()
end

return setmetatable(testing, {
    __call = call,
})
