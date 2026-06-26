package.path = "src/?.lua;src/?/init.lua;test/?.lua;test/?/init.lua;" .. package.path

local lugo = require("lugo")
local test_driver = require("support.test_driver")

local function assert_equal(actual, expected)
  if actual ~= expected then
    error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
  end
end

local result, err = lugo.run(function()
  return "root"
end)

assert_equal(result, "root")
assert_equal(err, nil)

local task, go_err = lugo.go(function()
  return "outside"
end)

assert_equal(task, nil)
assert(lugo.errors.is(go_err, lugo.scheduler.ErrNoScheduler))

local order = {}
local interleaved, interleaved_err = lugo.run(function()
  local first = lugo.check(lugo.go(function()
    order[#order + 1] = "a1"
    lugo.check(lugo.yield())
    order[#order + 1] = "a2"
    return "a"
  end))

  local second = lugo.check(lugo.go(function()
    order[#order + 1] = "b1"
    lugo.check(lugo.yield())
    order[#order + 1] = "b2"
    return "b"
  end))

  assert_equal(first:join(), "a")
  assert_equal(second:join(), "b")
  return "done"
end)

assert_equal(interleaved, "done")
assert_equal(interleaved_err, nil)
assert_equal(table.concat(order, ","), "a1,b1,a2,b2")

local current_seen, current_err = lugo.run(function()
  local current = lugo.current()
  assert(current ~= nil)
  assert_equal(current:status(), "ready")
  assert_equal(current:done():is_closed(), false)
  return "current"
end)

assert_equal(current_seen, "current")
assert_equal(current_err, nil)

local nested_result, nested_err = lugo.run(function()
  local inner, inner_err = lugo.run(function()
    return "inner"
  end)

  assert_equal(inner, "inner")
  assert_equal(inner_err, nil)

  local child = lugo.check(lugo.go(function()
    return "outer"
  end))

  return child:join()
end)

assert_equal(nested_result, "outer")
assert_equal(nested_err, nil)

local driver = test_driver.new()
local slept = false
local sleep_result, sleep_err = lugo.run(function()
  local sleeper = lugo.check(lugo.go(function()
    lugo.check(lugo.sleep(10))
    slept = true
  end))

  lugo.check(lugo.yield())
  assert_equal(slept, false)
  lugo.check(sleeper:join())
  return "slept"
end, { driver = driver })

assert_equal(sleep_result, "slept")
assert_equal(sleep_err, nil)
assert_equal(slept, true)
assert_equal(driver:now(), 10)

local ordered_driver = test_driver.new()
local wake_order = {}
local ordered_sleep_result, ordered_sleep_err = lugo.run(function()
  local slow = lugo.check(lugo.go(function()
    lugo.check(lugo.sleep(20))
    wake_order[#wake_order + 1] = "slow"
    return "slow"
  end))

  local fast = lugo.check(lugo.go(function()
    lugo.check(lugo.sleep(5))
    wake_order[#wake_order + 1] = "fast"
    return "fast"
  end))

  assert_equal(fast:join(), "fast")
  assert_equal(slow:join(), "slow")
  return "ordered"
end, { driver = ordered_driver })

assert_equal(ordered_sleep_result, "ordered")
assert_equal(ordered_sleep_err, nil)
assert_equal(table.concat(wake_order, ","), "fast,slow")
assert_equal(ordered_driver:now(), 20)

local sleep_without_driver, sleep_without_driver_err = lugo.run(function()
  lugo.check(lugo.sleep(1))
  return "unreachable"
end)

assert_equal(sleep_without_driver, nil)
assert(lugo.errors.is(sleep_without_driver_err, lugo.scheduler.ErrUnsupportedDriverCapability))

local child_err_result, child_err = lugo.run(function()
  local child = lugo.check(lugo.go(function()
    error("boom")
  end))

  return child:join()
end)

assert_equal(child_err_result, nil)
assert(lugo.errors.as(child_err, "panic") ~= nil)

local finished_task
local finished_result, finished_err = lugo.run(function()
  finished_task = lugo.check(lugo.go(function()
    return "finished"
  end))

  return finished_task:join()
end)

assert_equal(finished_result, "finished")
assert_equal(finished_err, nil)
assert_equal(finished_task:status(), "dead")
assert_equal(finished_task:done():is_closed(), true)
assert_equal(finished_task:join(), "finished")

local canceled_status, canceled_err = lugo.run(function()
  local child = lugo.check(lugo.go(function()
    lugo.check(lugo.yield())
    return "late"
  end))

  child:cancel()
  assert_equal(child:done():is_closed(), true)
  local value, join_err = child:join()
  assert_equal(value, nil)
  assert(lugo.errors.is(join_err, lugo.scheduler.ErrTaskCanceled))
  return child:status()
end)

assert_equal(canceled_status, "canceled")
assert_equal(canceled_err, nil)

local custom_cancel = lugo.new_error("custom cancel", { kind = "custom_cancel" })
local joiner_value
local joiner_err
local cancel_driver = test_driver.new()
local cancel_result, cancel_err = lugo.run(function()
  local child = lugo.check(lugo.go(function()
    lugo.check(lugo.sleep(100))
    return "late"
  end))

  local joiner = lugo.check(lugo.go(function()
    joiner_value, joiner_err = child:join()
    return "joined"
  end))

  lugo.check(lugo.yield())
  child:cancel(custom_cancel)
  return joiner:join()
end, { driver = cancel_driver })

assert_equal(cancel_result, "joined")
assert_equal(cancel_err, nil)
assert_equal(joiner_value, nil)
assert(lugo.errors.is(joiner_err, custom_cancel))
assert_equal(cancel_driver:has_pending(), false)

local deadlock_result, deadlock_err = lugo.run(function()
  local current = lugo.current()
  assert(current ~= nil)
  return current:join()
end)

assert_equal(deadlock_result, nil)
assert(lugo.errors.as(deadlock_err, "scheduler_deadlock") ~= nil)

print("scheduler_test.lua: ok")
