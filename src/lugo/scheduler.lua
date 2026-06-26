---@alias lugo.TaskStatus "ready"|"waiting"|"dead"|"canceled"
---@alias lugo.scheduler.Op lugo.scheduler.YieldOp|lugo.scheduler.SleepOp|lugo.scheduler.JoinOp<any>|lugo.scheduler.ChannelSendOp<any>|lugo.scheduler.ChannelRecvOp<any>

---@class lugo.scheduler.YieldOp
---@field kind "yield"

---@class lugo.scheduler.SleepOp
---@field kind "sleep"
---@field deadline number

---@class lugo.scheduler.JoinOp<T>
---@field kind "join"
---@field task lugo.Task<T>

---@class lugo.scheduler.ChannelSendOp<T>
---@field kind "channel_send"
---@field channel lugo.Channel<T>
---@field value T

---@class lugo.scheduler.ChannelRecvOp<T>
---@field kind "channel_recv"
---@field channel lugo.Channel<T>

---@class lugo.TimerHandle
---@field cancel fun(self: lugo.TimerHandle)

---@class lugo.SchedulerDriver
---@field now fun(self: lugo.SchedulerDriver): number
---@field call_at fun(self: lugo.SchedulerDriver, deadline: number, callback: fun()): lugo.TimerHandle|nil, lugo.Error|nil
---@field run_once fun(self: lugo.SchedulerDriver)
---@field has_pending fun(self: lugo.SchedulerDriver): boolean
local SchedulerDriver = {}

---@class lugo.SchedulerOptions
---@field driver? lugo.SchedulerDriver

---@class lugo.ResumeArgs
---@field n integer

---@class lugo.Task<T>
---@field scheduler lugo.Scheduler
---@field co thread
---@field status_value lugo.TaskStatus
---@field result_value T
---@field err_value? lugo.Error
---@field done_signal lugo.Done
---@field waiters lugo.Task<any>[]
---@field resume_args? lugo.ResumeArgs
---@field timer_handle? lugo.TimerHandle
local Task = {}
Task.__index = Task

---@class lugo.Scheduler
---@field driver? lugo.SchedulerDriver
---@field ready lugo.Task<any>[]
---@field current_task? lugo.Task<any>
---@field tasks lugo.Task<any>[]
---@field root? lugo.Task<any>
local Scheduler = {}
Scheduler.__index = Scheduler

---@class lugo.scheduler
local scheduler = {}

local context = require("lugo.context")
local errors = require("lugo.errors")

local current_scheduler = nil
local unpack_args = _G["unpack"] or rawget(table, "unpack")

scheduler.ErrNoScheduler = errors.new("no scheduler is running", {
    kind = "scheduler_not_running",
})

scheduler.ErrUnsupportedDriverCapability = errors.new("driver does not support this scheduler operation", {
    kind = "unsupported_driver_capability",
})

scheduler.ErrTaskCanceled = errors.new("task canceled", {
    kind = "task_canceled",
})

---@param ... any
---@return lugo.ResumeArgs
local function pack(...)
    return { n = select("#", ...), ... }
end

---@param err any
---@param co? thread
---@return lugo.Error
local function error_from_panic(err, co)
    if type(err) == "table" and err._lugo_panic == true then
        return err.error
    end

    local message = tostring(err)
    local stack = co and debug.traceback(co, message) or debug.traceback(message, 2)
    return errors.new(message, {
        kind = "panic",
        stack = stack,
    })
end

---@param task lugo.Task<any>
---@param ... any
function Scheduler:enqueue(task, ...)
    if task.status_value == "dead" or task.status_value == "canceled" then
        return
    end

    task.status_value = "ready"
    task.resume_args = pack(...)
    self.ready[#self.ready + 1] = task
end

---@return lugo.Task<any>|nil
function Scheduler:dequeue()
    if #self.ready == 0 then
        return nil
    end

    local task = self.ready[1]
    table.remove(self.ready, 1)
    return task
end

---@param task lugo.Task<any>
function Scheduler:finish_task(task)
    task.done_signal:close()

    local waiters = task.waiters
    task.waiters = {}
    for i = 1, #waiters do
        self:enqueue(waiters[i], task.result_value, task.err_value)
    end
end

---@param task lugo.Task<any>
---@param op lugo.scheduler.Op|nil
---@param extra any
function Scheduler:handle_yield(task, op, extra)
    if op == nil or op.kind == "yield" then
        self:enqueue(task)
        return
    end

    if op.kind == "sleep" then
        if self.driver == nil or self.driver.now == nil or self.driver.call_at == nil then
            task.status_value = "dead"
            task.err_value = errors.wrap(scheduler.ErrUnsupportedDriverCapability,
                "sleep requires a timer-capable scheduler driver")
            self:finish_task(task)
            return
        end

        task.status_value = "waiting"
        local timer_handle, timer_err = self.driver:call_at(op.deadline, function()
            task.timer_handle = nil
            self:enqueue(task)
        end)

        if timer_err ~= nil then
            task.status_value = "dead"
            task.err_value = timer_err
            self:finish_task(task)
            return
        end

        task.timer_handle = timer_handle
        return
    end

    if op.kind == "join" then
        local target = op.task
        if target.status_value == "dead" or target.status_value == "canceled" then
            self:enqueue(task, target.result_value, target.err_value)
            return
        end

        task.status_value = "waiting"
        target.waiters[#target.waiters + 1] = task
        return
    end

    if op.kind == "channel_send" then
        local ok, err = op.channel:send_op(task, op.value)
        if err ~= nil then
            task.status_value = "dead"
            task.err_value = err
            self:finish_task(task)
        elseif ok then
            self:enqueue(task, true, nil)
        else
            task.status_value = "waiting"
        end
        return
    end

    if op.kind == "channel_recv" then
        local ready, value, ok, err = op.channel:recv_op(task)
        if err ~= nil then
            task.status_value = "dead"
            task.err_value = err
            self:finish_task(task)
        elseif ready then
            self:enqueue(task, value, ok, nil)
        else
            task.status_value = "waiting"
        end
        return
    end

    task.status_value = "dead"
    task.err_value = errors.new("unknown scheduler operation", {
        kind = "unknown_scheduler_operation",
        fields = { operation = op.kind, argument = extra },
    })
    self:finish_task(task)
end

---@param task lugo.Task<any>
function Scheduler:resume_task(task)
    if task.status_value == "dead" or task.status_value == "canceled" then
        return
    end

    self.current_task = task
    task.status_value = "ready"

    local args = task.resume_args or { n = 0 }
    task.resume_args = nil

    local ok, op, a = coroutine.resume(task.co, unpack_args(args, 1, args.n))
    self.current_task = nil

    if not ok then
        task.status_value = "dead"
        task.err_value = error_from_panic(op, task.co)
        self:finish_task(task)
        return
    end

    if coroutine.status(task.co) == "dead" then
        task.status_value = "dead"
        task.result_value = op
        task.err_value = a
        self:finish_task(task)
        return
    end

    self:handle_yield(task, op, a)
end

---@return boolean
function Scheduler:has_live_tasks()
    for i = 1, #self.tasks do
        local status = self.tasks[i].status_value
        if status ~= "dead" and status ~= "canceled" then
            return true
        end
    end
    return false
end

---@generic T
---@overload fun(self: lugo.Scheduler, fn: fun(...), ...: any): lugo.Task<nil>
---@param fn fun(...): T|nil
---@param ... any
---@return lugo.Task<T>
function Scheduler:go(fn, ...)
    local args = pack(...)
    local task = setmetatable({
        scheduler = self,
        co = coroutine.create(function()
            return fn(unpack_args(args, 1, args.n))
        end),
        status_value = "ready",
        done_signal = context.new_done(),
        waiters = {},
    }, Task)

    self.tasks[#self.tasks + 1] = task
    self:enqueue(task)
    return task
end

---@generic T
---@param fn fun(): T
---@return T|nil value
---@return lugo.Error|nil err
function Scheduler:run(fn)
    local previous = current_scheduler
    current_scheduler = self

    self.root = self:go(fn)

    while self.root.status_value ~= "dead" and self.root.status_value ~= "canceled" do
        local task = self:dequeue()
        if task ~= nil then
            self:resume_task(task)
        else
            if self.driver ~= nil and self.driver.has_pending ~= nil and self.driver:has_pending() then
                self.driver:run_once()
            elseif not self:has_live_tasks() then
                break
            else
                self.root.status_value = "dead"
                self.root.err_value = errors.new("scheduler deadlock", { kind = "scheduler_deadlock" })
                self:finish_task(self.root)
            end
        end
    end

    current_scheduler = previous
    return self.root:result()
end

---@return lugo.TaskStatus
function Task:status()
    return self.status_value
end

---@return lugo.Done
function Task:done()
    return self.done_signal
end

---@return T|nil value
---@return lugo.Error|nil err
function Task:result()
    return self.result_value, self.err_value
end

---@param err? lugo.Error
function Task:cancel(err)
    if self.status_value == "dead" or self.status_value == "canceled" then
        return
    end

    if self.timer_handle ~= nil then
        self.timer_handle:cancel()
        self.timer_handle = nil
    end

    self.status_value = "canceled"
    self.err_value = err or scheduler.ErrTaskCanceled
    self.done_signal:close()
    self.scheduler:finish_task(self)
end

---@return T|nil value
---@return lugo.Error|nil err
function Task:join()
    if self.status_value == "dead" or self.status_value == "canceled" then
        return self:result()
    end

    local running = current_scheduler and current_scheduler.current_task or nil
    if running == nil then
        return nil, scheduler.ErrNoScheduler
    end

    return coroutine.yield({ kind = "join", task = self })
end

---@param opts? lugo.SchedulerOptions
---@return lugo.Scheduler
function scheduler.new(opts)
    opts = opts or {}
    return setmetatable({
        driver = opts.driver,
        ready = {},
        tasks = {},
    }, Scheduler)
end

---@generic T
---@param fn fun(): T
---@param opts? lugo.SchedulerOptions
---@return T|nil value
---@return lugo.Error|nil err
function scheduler.run(fn, opts)
    return scheduler.new(opts):run(fn)
end

---@generic T
---@overload fun(fn: fun(...), ...: any): lugo.Task<nil>|nil, lugo.Error|nil
---@param fn fun(...): T|nil
---@param ... any
---@return lugo.Task<T>|nil task
---@return lugo.Error|nil err
function scheduler.go(fn, ...)
    if current_scheduler == nil then
        return nil, scheduler.ErrNoScheduler
    end

    return current_scheduler:go(fn, ...), nil
end

---@return lugo.Task<any>|nil
function scheduler.current()
    return current_scheduler and current_scheduler.current_task or nil
end

---@return lugo.Scheduler|nil
function scheduler.current_scheduler()
    return current_scheduler
end

---@return nil
---@return lugo.Error|nil err
function scheduler.yield()
    if scheduler.current() == nil then
        return nil, scheduler.ErrNoScheduler
    end

    ---@type lugo.scheduler.YieldOp
    local op = { kind = "yield" }
    coroutine.yield(op)
    return nil, nil
end

---@param seconds number
---@return nil
---@return lugo.Error|nil err
function scheduler.sleep(seconds)
    local running = scheduler.current()
    if running == nil then
        return nil, scheduler.ErrNoScheduler
    end

    local driver = current_scheduler and current_scheduler.driver or nil
    if driver == nil or driver.now == nil or driver.call_at == nil then
        return nil, scheduler.ErrUnsupportedDriverCapability
    end

    ---@type lugo.scheduler.SleepOp
    local op = { kind = "sleep", deadline = driver:now() + seconds }
    coroutine.yield(op)
    return nil, nil
end

return scheduler
