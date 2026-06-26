package.path = "src/?.lua;src/?/init.lua;test/?.lua;test/?/init.lua;" .. package.path

local lugo = require("lugo")
local testing = require("lugo.testing")
local test_driver = require("support.test_driver")

local ok = testing(function(test)
  test("scheduler: run returns root value", function(t)
    local result, err = lugo.run(function()
      return "root"
    end)

    t:equal(result, "root")
    t:no_error(err)
  end)

  test("scheduler: go outside run returns error", function(t)
    local task, err = lugo.go(function()
      return "outside"
    end)

    t:is_nil(task)
    t:error_is(err, lugo.scheduler.ErrNoScheduler)
  end)

  test("scheduler: yield interleaves ready tasks", function(t)
    local order = {}
    local result, err = lugo.run(function()
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

      t:equal(first:join(), "a")
      t:equal(second:join(), "b")
      return "done"
    end)

    t:equal(result, "done")
    t:no_error(err)
    t:equal(table.concat(order, ","), "a1,b1,a2,b2")
  end)

  test("scheduler: current returns running task", function(t)
    local result, err = lugo.run(function()
      local current = lugo.current()
      if current == nil then
        t:fatal("expected current task")
        return nil
      end

      t:equal(current:status(), "ready")
      t:is_false(current:done():is_closed())
      return "current"
    end)

    t:equal(result, "current")
    t:no_error(err)
  end)

  test("scheduler: nested run restores outer scheduler", function(t)
    local result, err = lugo.run(function()
      local inner, inner_err = lugo.run(function()
        return "inner"
      end)

      t:equal(inner, "inner")
      t:no_error(inner_err)

      local child = lugo.check(lugo.go(function()
        return "outer"
      end))

      return child:join()
    end)

    t:equal(result, "outer")
    t:no_error(err)
  end)

  test("scheduler: sleep parks task until driver timer fires", function(t)
    local driver = test_driver.new()
    local slept = false

    local result, err = lugo.run(function()
      local sleeper = lugo.check(lugo.go(function()
        lugo.check(lugo.sleep(10))
        slept = true
      end))

      lugo.check(lugo.yield())
      t:is_false(slept)
      lugo.check(sleeper:join())
      return "slept"
    end, { driver = driver })

    t:equal(result, "slept")
    t:no_error(err)
    t:is_true(slept)
    t:equal(driver:now(), 10)
  end)

  test("scheduler: sleepers wake in deadline order", function(t)
    local driver = test_driver.new()
    local wake_order = {}

    local result, err = lugo.run(function()
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

      t:equal(fast:join(), "fast")
      t:equal(slow:join(), "slow")
      return "ordered"
    end, { driver = driver })

    t:equal(result, "ordered")
    t:no_error(err)
    t:equal(table.concat(wake_order, ","), "fast,slow")
    t:equal(driver:now(), 20)
  end)

  test("scheduler: sleep without driver returns capability error", function(t)
    local result, err = lugo.run(function()
      lugo.check(lugo.sleep(1))
      return "unreachable"
    end)

    t:is_nil(result)
    t:error_is(err, lugo.scheduler.ErrUnsupportedDriverCapability)
  end)

  test("scheduler: child panic propagates through join", function(t)
    local result, err = lugo.run(function()
      local child = lugo.check(lugo.go(function()
        error("boom")
      end))

      return child:join()
    end)

    t:is_nil(result)
    t:error_as(err, "panic")
  end)

  test("scheduler: finished task can be joined again", function(t)
    local finished_task
    local result, err = lugo.run(function()
      finished_task = lugo.check(lugo.go(function()
        return "finished"
      end))

      return finished_task:join()
    end)

    t:equal(result, "finished")
    t:no_error(err)
    t:equal(finished_task:status(), "dead")
    t:is_true(finished_task:done():is_closed())
    t:equal(finished_task:join(), "finished")
  end)

  test("scheduler: canceled task reports cancellation", function(t)
    local result, err = lugo.run(function()
      local child = lugo.check(lugo.go(function()
        lugo.check(lugo.yield())
        return "late"
      end))

      child:cancel()
      t:is_true(child:done():is_closed())
      local value, join_err = child:join()
      t:is_nil(value)
      t:error_is(join_err, lugo.scheduler.ErrTaskCanceled)
      return child:status()
    end)

    t:equal(result, "canceled")
    t:no_error(err)
  end)

  test("scheduler: cancel wakes joiner and clears pending timer", function(t)
    local custom_cancel = lugo.new_error("custom cancel", { kind = "custom_cancel" })
    local driver = test_driver.new()
    local joiner_value
    local joiner_err

    local result, err = lugo.run(function()
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
    end, { driver = driver })

    t:equal(result, "joined")
    t:no_error(err)
    t:is_nil(joiner_value)
    t:error_is(joiner_err, custom_cancel)
    t:is_false(driver:has_pending())
  end)

  test("scheduler: self join deadlocks", function(t)
    local result, err = lugo.run(function()
      local current = lugo.current()
      if current == nil then
        t:fatal("expected current task")
        return nil
      end

      return current:join()
    end)

    t:is_nil(result)
    t:error_as(err, "scheduler_deadlock")
  end)
end)

if not ok then
  error("scheduler_test.lua failed")
end
