package.path = "src/?.lua;src/?/init.lua;test/?.lua;test/?/init.lua;" .. package.path

local lugo = require("lugo")

---@class lugo.TestDriver: lugo.SchedulerDriver
---@field time number
---@field timers lugo.TestTimerHandle[]
local TestDriver = {}
TestDriver.__index = TestDriver

---@class lugo.TestTimerHandle: lugo.TimerHandle
---@field driver lugo.TestDriver
---@field deadline number
---@field callback fun()
---@field canceled boolean
local TestTimerHandle = {}
TestTimerHandle.__index = TestTimerHandle

---@return lugo.TestDriver
local function new_test_driver()
    return setmetatable({ time = 0, timers = {} }, TestDriver)
end

---@return number
function TestDriver:now()
    return self.time
end

---@param deadline number
---@param callback fun()
---@return lugo.TimerHandle
---@return nil
function TestDriver:call_at(deadline, callback)
    local handle = setmetatable({
        driver = self,
        deadline = deadline,
        callback = callback,
        canceled = false,
    }, TestTimerHandle)

    self.timers[#self.timers + 1] = handle
    return handle, nil
end

function TestTimerHandle:cancel()
    self.canceled = true
end

function TestDriver:fire_due()
    local remaining = {}
    for i = 1, #self.timers do
        local timer = self.timers[i]
        if timer.canceled then
            -- drop it
        elseif timer.deadline <= self.time then
            timer.canceled = true
            timer.callback()
        else
            remaining[#remaining + 1] = timer
        end
    end
    self.timers = remaining
end

---@return lugo.TestTimerHandle|nil
function TestDriver:next_timer()
    local next_timer = nil
    for i = 1, #self.timers do
        local timer = self.timers[i]
        if not timer.canceled and (next_timer == nil or timer.deadline < next_timer.deadline) then
            next_timer = timer
        end
    end
    return next_timer
end

function TestDriver:run_once()
    local timer = self:next_timer()
    if timer ~= nil then
        if timer.deadline > self.time then
            self.time = timer.deadline
        end
        self:fire_due()
    end
end

---@return boolean
function TestDriver:has_pending()
    return self:next_timer() ~= nil
end

return function(test)
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
        local driver = new_test_driver()
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
        local driver = new_test_driver()
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

    test("scheduler: driver timer error fails sleeping task", function(t)
        local timer_err = lugo.new_error("timer failed", { kind = "timer_failed" })
        local driver = {
            now = function()
                return 0
            end,
            call_at = function()
                return nil, timer_err
            end,
            run_once = function()
            end,
            has_pending = function()
                return false
            end,
        }

        local result, err = lugo.run(function()
            lugo.check(lugo.sleep(1))
            return "unreachable"
        end, { driver = driver })

        t:is_nil(result)
        t:error_is(err, timer_err)
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
        local driver = new_test_driver()
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
end
