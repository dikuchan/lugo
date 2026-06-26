package.path = "src/?.lua;src/?/init.lua;" .. package.path

local testing = require("lugo.testing")

local callback_seen = false
local cleaned = false

local ok = testing(function(test)
  test("testing: assertions and cleanup", function(t)
    t:equal("a", "a")
    t:not_equal("a", "b")
    t:is_true(true)
    t:is_false(false)
    t:is_nil(nil)
    t:not_nil({})
    t:no_error(nil)
    t:cleanup(function()
      cleaned = true
    end)
  end)

  test("testing: expect wraps callback", function(t)
    local callback = t:expect(function(value)
      callback_seen = true
      t:equal(value, "called")
      return "returned"
    end)

    t:equal(callback("called"), "returned")
  end)
end)

if not ok then
  error("testing_test.lua failed")
end

if not callback_seen then
  error("expected callback to run")
end

if not cleaned then
  error("expected cleanup to run")
end
