package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")
local lugo_uv = require("lugo_uv")

local probe_driver, probe_err = lugo_uv.driver()
if probe_driver == nil then
  return function(test)
    test("lugo_uv: skipped", function(t)
      t:log("skipped: " .. tostring(probe_err))
    end)
  end
end
probe_driver:close()

return function(test)
  test("lugo_uv: now is monotonic", function(t)
    local driver = lugo.check(lugo_uv.driver())
    t:cleanup(function()
      driver:close()
    end)

    local before = driver:now()
    local after = driver:now()

    t:is_true(after >= before)
  end)

  test("lugo_uv: sleep resumes through real timer", function(t)
    local driver = lugo.check(lugo_uv.driver())
    local slept = false
    t:cleanup(function()
      driver:close()
    end)

    local result, err = lugo.run(function()
      lugo.check(lugo.sleep(0.01))
      slept = true
      return "slept"
    end, { driver = driver })

    t:equal(result, "slept")
    t:no_error(err)
    t:is_true(slept)
    t:is_false(driver:has_pending())
  end)

  test("lugo_uv: timers fire in deadline order", function(t)
    local driver = lugo.check(lugo_uv.driver())
    local order = {}
    t:cleanup(function()
      driver:close()
    end)

    local result, err = lugo.run(function()
      local slow = lugo.check(lugo.go(function()
        lugo.check(lugo.sleep(0.02))
        order[#order + 1] = "slow"
        return "slow"
      end))

      local fast = lugo.check(lugo.go(function()
        lugo.check(lugo.sleep(0.005))
        order[#order + 1] = "fast"
        return "fast"
      end))

      t:equal(fast:join(), "fast")
      t:equal(slow:join(), "slow")
      return "ordered"
    end, { driver = driver })

    t:equal(result, "ordered")
    t:no_error(err)
    t:equal(table.concat(order, ","), "fast,slow")
    t:is_false(driver:has_pending())
  end)

  test("lugo_uv: cancellation clears timer", function(t)
    local driver = lugo.check(lugo_uv.driver())
    t:cleanup(function()
      driver:close()
    end)

    local result, err = lugo.run(function()
      local child = lugo.check(lugo.go(function()
        lugo.check(lugo.sleep(10))
        return "late"
      end))

      lugo.check(lugo.yield())
      child:cancel()
      t:is_false(driver:has_pending())
      return child:status()
    end, { driver = driver })

    t:equal(result, "canceled")
    t:no_error(err)
  end)

  test("lugo_uv: close cancels pending timers", function(t)
    local driver = lugo.check(lugo_uv.driver())
    local fired = false

    driver:call_at(driver:now() + 10, function()
      fired = true
    end)

    t:is_true(driver:has_pending())
    driver:close()
    t:is_false(driver:has_pending())
    t:is_false(fired)
  end)
end
