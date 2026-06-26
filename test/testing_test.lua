package.path = "src/?.lua;src/?/init.lua;" .. package.path

local testing = require("lugo.testing")

local assertions_ok = testing(function(test)
  test("testing: assertions", function(t)
    t:equal("a", "a")
    t:not_equal("a", "b")
    t:is_true(true)
    t:is_false(false)
    t:is_nil(nil)
    t:not_nil({})
    t:no_error(nil)
  end)
end)

if not assertions_ok then
  error("testing assertions failed")
end

local cleanup_seen = false
local cleanup_ok = testing(function(test)
  test("testing: cleanup runs after test", function(t)
    local value = "cleaned"
    t:cleanup(function()
      cleanup_seen = value == "cleaned"
    end)
  end)
end)

if not cleanup_ok then
  error("testing cleanup test failed")
end

if not cleanup_seen then
  error("expected cleanup to run")
end

local expect_seen = false
local expect_ok = testing(function(test)
  test("testing: expect wraps callback", function(t)
    local callback = t:expect(function(value)
      expect_seen = true
      t:equal(value, "called")
      return "returned"
    end)

    t:equal(callback("called"), "returned")
  end)
end)

if not expect_ok then
  error("testing expect test failed")
end

if not expect_seen then
  error("expected callback to run")
end
