package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

---@class lugo.test.User
---@field id string
---@field name string
---@field age? number
---@field cached? boolean
---@field greet fun(self: lugo.test.User): string

---@class lugo.test.UserStruct: lugo.Struct<lugo.test.User>
---@field greet fun(self: lugo.test.User): string

---@class lugo.test.Greeter
---@field greet fun(self: lugo.test.Greeter): string

---@type lugo.testing.Register
local function register(test)
    test("struct: new validates and attaches methods", function(t)
        ---@type lugo.test.UserStruct
        local User = lugo.struct("User", {
            id = lugo.string,
            name = lugo.string,
            age = lugo.optional(lugo.number),
        })

        function User:greet()
            return "hello " .. self.name
        end

        local user, err = User:new({
            id = "1",
            name = "Alice",
        })

        t:no_error(err)
        t:not_nil(user)
        if user == nil then
            return
        end

        t:equal(user:greet(), "hello Alice")
        t:is_true(User:is(user))
        t:equal(lugo.check(User:check(user)), user)
    end)

    test("struct: unknown fields are allowed", function(t)
        ---@type lugo.Struct<lugo.test.User>
        local User = lugo.struct("User", {
            id = lugo.string,
            name = lugo.string,
        })

        local user, err = User:new({
            id = "1",
            name = "Alice",
            cached = true,
        })

        t:no_error(err)
        t:not_nil(user)
        if user == nil then
            return
        end

        t:is_true(user.cached)
    end)

    test("struct: new reports missing and invalid fields", function(t)
        ---@type lugo.Struct<lugo.test.User>
        local User = lugo.struct("User", {
            id = lugo.string,
            name = lugo.string,
        })

        local missing, missing_err = User:new({
            id = "1",
        })
        t:is_nil(missing)
        t:error_as(missing_err, "contract_missing_field")

        local invalid, invalid_err = User:new({
            id = 1,
            name = "Alice",
        })
        t:is_nil(invalid)
        t:error_as(invalid_err, "contract_invalid_field")
    end)

    test("struct: check does not adopt raw tables", function(t)
        ---@type lugo.Struct<lugo.test.User>
        local User = lugo.struct("User", {
            id = lugo.string,
            name = lugo.string,
        })

        local raw = {
            id = "1",
            name = "Alice",
        }

        local checked, err = User:check(raw)
        t:is_nil(checked)
        t:error_as(err, "struct_not_instance")
        t:is_false(User:is(raw))
    end)

    test("struct: new rejects foreign metatable", function(t)
        ---@type lugo.Struct<lugo.test.User>
        local User = lugo.struct("User", {
            id = lugo.string,
            name = lugo.string,
        })

        local raw = setmetatable({
            id = "1",
            name = "Alice",
        }, {})

        local user, err = User:new(raw)
        t:is_nil(user)
        t:error_as(err, "struct_metatable_conflict")
    end)

    test("interface: check is structural and non-mutating", function(t)
        local Greeter = lugo.interface("Greeter", {
            greet = lugo.function_,
        })

        local raw = {
            greet = function()
                return "hello"
            end,
        }

        local before = getmetatable(raw)
        local greeter, err = Greeter:check(raw)

        t:no_error(err)
        t:equal(greeter, raw)
        t:equal(getmetatable(raw), before)
        t:is_true(Greeter:is(raw))
    end)

    test("interface: check reports missing and invalid members", function(t)
        local Greeter = lugo.interface("Greeter", {
            greet = lugo.function_,
        })

        local missing, missing_err = Greeter:check({})
        t:is_nil(missing)
        t:error_as(missing_err, "contract_missing_field")

        local invalid, invalid_err = Greeter:check({
            greet = "hello",
        })
        t:is_nil(invalid)
        t:error_as(invalid_err, "contract_invalid_field")
    end)
end

return register
