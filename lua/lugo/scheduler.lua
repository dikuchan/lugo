---@alias lugo.TaskStatus "ready"|"waiting"|"dead"|"canceled"

---@class lugo.SchedulerDriver
---@field now fun(self: lugo.SchedulerDriver): number
---@field wait_until fun(self: lugo.SchedulerDriver, deadline?: number)
---@field wake? fun(self: lugo.SchedulerDriver)
local SchedulerDriver = {}

---@class lugo.SchedulerOptions
---@field driver? lugo.SchedulerDriver

---@class lugo.ResumeArgs
---@field n integer

---@class lugo.Task
---@field scheduler lugo.Scheduler
---@field co thread
---@field status_value lugo.TaskStatus
---@field result_value any
---@field err_value? lugo.Error
---@field done_signal lugo.Done
---@field waiters lugo.Task[]
---@field resume_args? lugo.ResumeArgs
---@field deadline? number
local Task = {}
Task.__index = Task

---@class lugo.Scheduler
---@field driver? lugo.SchedulerDriver
---@field ready lugo.Task[]
---@field sleeping lugo.Task[]
---@field current_task? lugo.Task
---@field tasks lugo.Task[]
---@field root? lugo.Task
local Scheduler = {}
Scheduler.__index = Scheduler

---@class lugo.scheduler
local scheduler = {}

local context = require("lugo.context")
local errors = require("lugo.errors")

local current_scheduler = nil

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

---@param task lugo.Task
---@param ... any
function Scheduler:enqueue(task, ...)
    if task.status_value == "dead" or task.status_value == "canceled" then
        return
    end

    task.status_value = "ready"
    task.resume_args = pack(...)
    self.ready[#self.ready + 1] = task
    local driver = self.driver
    if driver ~= nil and driver.wake ~= nil then
        driver:wake()
    end
end

---@return lugo.Task|nil
function Scheduler:dequeue()
    if #self.ready == 0 then
        return nil
    end

    local task = self.ready[1]
    table.remove(self.ready, 1)
    return task
end

---@param task lugo.Task
function Scheduler:finish_task(task)
    task.done_signal:close()

    local waiters = task.waiters
    task.waiters = {}
    for i = 1, #waiters do
        self:enqueue(waiters[i], task.result_value, task.err_value)
    end
end

---@param task lugo.Task
---@param op table|nil
---@param a any
function Scheduler:handle_yield(task, op, a)
    if op == nil or op.kind == "yield" then
        self:enqueue(task)
        return
    end

    if op.kind == "sleep" then
        if self.driver == nil or self.driver.now == nil or self.driver.wait_until == nil then
            task.status_value = "dead"
            task.err_value = errors.wrap(scheduler.ErrUnsupportedDriverCapability,
                "sleep requires a monotonic scheduler driver")
            self:finish_task(task)
            return
        end

        task.status_value = "waiting"
        task.deadline = op.deadline
        self.sleeping[#self.sleeping + 1] = task
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

    task.status_value = "dead"
    task.err_value = errors.new("unknown scheduler operation", {
        kind = "unknown_scheduler_operation",
        fields = { operation = op.kind, argument = a },
    })
    self:finish_task(task)
end

---@param task lugo.Task
function Scheduler:resume_task(task)
    if task.status_value == "dead" or task.status_value == "canceled" then
        return
    end

    self.current_task = task
    task.status_value = "ready"

    local args = task.resume_args or { n = 0 }
    task.resume_args = nil

    local ok, op, a = coroutine.resume(task.co, unpack(args, 1, args.n))
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

function Scheduler:wake_sleepers()
    if self.driver == nil or self.driver.now == nil then
        return
    end

    local now = self.driver:now()
    local remaining = {}
    for i = 1, #self.sleeping do
        local task = self.sleeping[i]
        if task.deadline <= now then
            task.deadline = nil
            self:enqueue(task)
        else
            remaining[#remaining + 1] = task
        end
    end
    self.sleeping = remaining
end

---@return number|nil
function Scheduler:next_deadline()
    local deadline = nil
    for i = 1, #self.sleeping do
        local task_deadline = self.sleeping[i].deadline
        if task_deadline ~= nil and (deadline == nil or task_deadline < deadline) then
            deadline = task_deadline
        end
    end
    return deadline
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

---@param fn fun(...): any
---@param ... any
---@return lugo.Task
function Scheduler:go(fn, ...)
    local args = pack(...)
    local task = setmetatable({
        scheduler = self,
        co = coroutine.create(function()
            return fn(unpack(args, 1, args.n))
        end),
        status_value = "ready",
        done_signal = context.new_done(),
        waiters = {},
    }, Task)

    self.tasks[#self.tasks + 1] = task
    self:enqueue(task)
    return task
end

---@param fn fun(...): any
---@return any value
---@return lugo.Error|nil err
function Scheduler:run(fn)
    local previous = current_scheduler
    current_scheduler = self

    self.root = self:go(fn)

    while self.root.status_value ~= "dead" and self.root.status_value ~= "canceled" do
        self:wake_sleepers()

        local task = self:dequeue()
        if task ~= nil then
            self:resume_task(task)
        else
            local deadline = self:next_deadline()
            if deadline ~= nil and self.driver ~= nil and self.driver.wait_until ~= nil then
                self.driver:wait_until(deadline)
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

---@return any value
---@return lugo.Error|nil err
function Task:result()
    return self.result_value, self.err_value
end

---@param err? lugo.Error
function Task:cancel(err)
    if self.status_value == "dead" or self.status_value == "canceled" then
        return
    end

    self.status_value = "canceled"
    self.err_value = err or scheduler.ErrTaskCanceled
    self.done_signal:close()
    self.scheduler:finish_task(self)
end

---@return any value
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
        sleeping = {},
        tasks = {},
    }, Scheduler)
end

---@param fn fun(...): any
---@param opts? lugo.SchedulerOptions
---@return any value
---@return lugo.Error|nil err
function scheduler.run(fn, opts)
    return scheduler.new(opts):run(fn)
end

---@param fn fun(...): any
---@param ... any
---@return lugo.Task|nil task
---@return lugo.Error|nil err
function scheduler.go(fn, ...)
    if current_scheduler == nil then
        return nil, scheduler.ErrNoScheduler
    end

    return current_scheduler:go(fn, ...), nil
end

---@return lugo.Task|nil
function scheduler.current()
    return current_scheduler and current_scheduler.current_task or nil
end

---@return nil
---@return lugo.Error|nil err
function scheduler.yield()
    if scheduler.current() == nil then
        return nil, scheduler.ErrNoScheduler
    end

    coroutine.yield({ kind = "yield" })
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
    if driver == nil or driver.now == nil or driver.wait_until == nil then
        return nil, scheduler.ErrUnsupportedDriverCapability
    end

    coroutine.yield({ kind = "sleep", deadline = driver:now() + seconds })
    return nil, nil
end

return scheduler
