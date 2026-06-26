package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")
local lugo_uv = require("lugo_uv")

local function assert_equal(actual, expected)
  if actual ~= expected then
    error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
  end
end

local driver, driver_err = lugo_uv.driver()
if driver == nil then
  print("uv_driver_test.lua: skipped (" .. tostring(driver_err) .. ")")
  return
end

local before = driver:now()
local after = driver:now()
assert(after >= before)

local slept = false
local sleep_result, sleep_err = lugo.run(function()
  lugo.check(lugo.sleep(0.01))
  slept = true
  return "slept"
end, { driver = driver })

assert_equal(sleep_result, "slept")
assert_equal(sleep_err, nil)
assert_equal(slept, true)
assert_equal(driver:has_pending(), false)

local order = {}
local ordered_driver = lugo.check(lugo_uv.driver())
local ordered_result, ordered_err = lugo.run(function()
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

  assert_equal(fast:join(), "fast")
  assert_equal(slow:join(), "slow")
  return "ordered"
end, { driver = ordered_driver })

assert_equal(ordered_result, "ordered")
assert_equal(ordered_err, nil)
assert_equal(table.concat(order, ","), "fast,slow")
assert_equal(ordered_driver:has_pending(), false)

local canceled_driver = lugo.check(lugo_uv.driver())
local cancel_result, cancel_err = lugo.run(function()
  local child = lugo.check(lugo.go(function()
    lugo.check(lugo.sleep(10))
    return "late"
  end))

  lugo.check(lugo.yield())
  child:cancel()
  assert_equal(canceled_driver:has_pending(), false)
  return child:status()
end, { driver = canceled_driver })

assert_equal(cancel_result, "canceled")
assert_equal(cancel_err, nil)

local close_driver = lugo.check(lugo_uv.driver())
local close_fired = false
close_driver:call_at(close_driver:now() + 10, function()
  close_fired = true
end)

assert_equal(close_driver:has_pending(), true)
close_driver:close()
assert_equal(close_driver:has_pending(), false)
assert_equal(close_fired, false)

driver:close()
ordered_driver:close()
canceled_driver:close()

print("uv_driver_test.lua: ok")
