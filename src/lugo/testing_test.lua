package.path = "src/?.lua;src/?/init.lua;" .. package.path

local testing = require("lugo.testing")

---@type lugo.testing.Register
local function register(test)
    test("testing: assertions", function(t)
        t:equal("a", "a")
        t:not_equal("a", "b")
        t:is_true(true)
        t:is_false(false)
        t:is_nil(nil)
        t:not_nil({})
        t:no_error(nil)
    end)

    test("testing: cleanup runs after test", function(t)
        local cleanup_seen = false
        local original_print = print
        _G.print = function()
        end

        local ran, ok = xpcall(function()
            return testing(function(inner_test)
                inner_test("inner cleanup", function(inner_t)
                    inner_t:cleanup(function()
                        cleanup_seen = true
                    end)
                end)
            end)
        end, debug.traceback)

        _G.print = original_print

        if not ran then
            t:fatal(tostring(ok))
            return
        end

        t:is_true(ok)
        t:is_true(cleanup_seen)
    end)

    test("testing: run loads modules", function(t)
        local original_print = print
        _G.print = function()
        end

        local preload_key = "lugo.testing_test_fixture"
        package.preload[preload_key] = function()
            return function(inner_test)
                inner_test("fixture", function(inner_t)
                    inner_t:pass()
                end)
            end
        end

        local ran, ok = xpcall(function()
            return testing.run({ preload_key })
        end, debug.traceback)

        package.preload[preload_key] = nil
        _G.print = original_print

        if not ran then
            t:fatal(tostring(ok))
            return
        end

        t:is_true(ok)
    end)

    test("testing: expect wraps callback", function(t)
        local expect_seen = false
        local callback = t:expect(function(value)
            expect_seen = true
            t:equal(value, "called")
            return "returned"
        end)

        t:equal(callback("called"), "returned")
        t:is_true(expect_seen)
    end)
end

return register
