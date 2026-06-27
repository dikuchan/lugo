---@class lugo.ChannelSender<T>
---@field task lugo.Task<any>
---@field value T
---@field select_waiter? lugo.scheduler.SelectWaiter
---@field case_index? integer

---@class lugo.ChannelReceiver
---@field task lugo.Task<any>
---@field select_waiter? lugo.scheduler.SelectWaiter
---@field case_index? integer

---@class lugo.Channel<T>
---@field capacity integer
---@field buffer T[]
---@field closed boolean
---@field senders lugo.ChannelSender<T>[]
---@field receivers lugo.ChannelReceiver[]
local Channel = {}
Channel.__index = Channel

---@class lugo.channel
local channel = {}

local errors = require("lugo.errors")
local scheduler = require("lugo.scheduler")

channel.ErrClosed = errors.new("channel is closed", { kind = "channel_closed" })

---@param queue table
---@return any
local function shift(queue)
    while #queue > 0 do
        local value = queue[1]
        table.remove(queue, 1)

        local waiter = value.select_waiter
        if waiter == nil or not waiter.selected then
            return value
        end
    end

    return nil
end

---@param queue table
---@return boolean
local function has_active(queue)
    for i = 1, #queue do
        local waiter = queue[i].select_waiter
        if waiter == nil or not waiter.selected then
            return true
        end
    end

    return false
end

---@param sender lugo.ChannelSender<any>
---@param ok boolean|nil
---@param err? lugo.Error
local function wake_sender(sender, ok, err)
    local waiter = sender.select_waiter
    if waiter ~= nil then
        waiter.scheduler:commit_select(waiter, sender.case_index, nil, nil, err)
        return
    end

    sender.task.scheduler:enqueue(sender.task, ok, err)
end

---@param receiver lugo.ChannelReceiver
---@param value any
---@param ok boolean
---@param err? lugo.Error
local function wake_receiver(receiver, value, ok, err)
    local waiter = receiver.select_waiter
    if waiter ~= nil then
        waiter.scheduler:commit_select(waiter, receiver.case_index, value, ok, err)
        return
    end

    receiver.task.scheduler:enqueue(receiver.task, value, ok, err)
end

---@generic T
---@param capacity? integer
---@return lugo.Channel<T>
function channel.new(capacity)
    capacity = capacity or 0
    if capacity < 0 then
        errors.panic(errors.new("channel capacity must be non-negative", {
            kind = "invalid_channel_capacity",
            fields = { capacity = capacity },
        }))
    end

    return setmetatable({
        capacity = capacity,
        buffer = {},
        closed = false,
        senders = {},
        receivers = {},
    }, Channel)
end

---@param value T
---@return boolean|nil ok
---@return lugo.Error|nil err
function Channel:send(value)
    if self.closed then
        return nil, channel.ErrClosed
    end

    local receiver = shift(self.receivers)
    if receiver ~= nil then
        wake_receiver(receiver, value, true, nil)
        return true, nil
    end

    if #self.buffer < self.capacity then
        self.buffer[#self.buffer + 1] = value
        return true, nil
    end

    local current = scheduler.current()
    if current == nil then
        return nil, scheduler.ErrNoScheduler
    end

    ---@type lugo.scheduler.ChannelSendOp<T>
    local op = { kind = "channel_send", channel = self, value = value }
    return coroutine.yield(op)
end

---@param task lugo.Task<any>
---@param value T
---@return boolean ready
---@return lugo.Error|nil err
function Channel:send_op(task, value)
    if self.closed then
        return false, channel.ErrClosed
    end

    local receiver = shift(self.receivers)
    if receiver ~= nil then
        wake_receiver(receiver, value, true, nil)
        return true, nil
    end

    if #self.buffer < self.capacity then
        self.buffer[#self.buffer + 1] = value
        return true, nil
    end

    self.senders[#self.senders + 1] = {
        task = task,
        value = value,
    }
    return false, nil
end

---@return T|nil value
---@return boolean ok
---@return lugo.Error|nil err
function Channel:recv()
    if #self.buffer > 0 then
        local value = shift(self.buffer)
        local sender = shift(self.senders)
        if sender ~= nil then
            self.buffer[#self.buffer + 1] = sender.value
            wake_sender(sender, true, nil)
        end
        return value, true, nil
    end

    local sender = shift(self.senders)
    if sender ~= nil then
        wake_sender(sender, true, nil)
        return sender.value, true, nil
    end

    if self.closed then
        return nil, false, nil
    end

    local current = scheduler.current()
    if current == nil then
        return nil, false, scheduler.ErrNoScheduler
    end

    ---@type lugo.scheduler.ChannelRecvOp<T>
    local op = { kind = "channel_recv", channel = self }
    return coroutine.yield(op)
end

---@param task lugo.Task<any>
---@return boolean ready
---@return T|nil value
---@return boolean ok
---@return lugo.Error|nil err
function Channel:recv_op(task)
    if #self.buffer > 0 then
        local value = shift(self.buffer)
        local sender = shift(self.senders)
        if sender ~= nil then
            self.buffer[#self.buffer + 1] = sender.value
            wake_sender(sender, true, nil)
        end
        return true, value, true, nil
    end

    local sender = shift(self.senders)
    if sender ~= nil then
        wake_sender(sender, true, nil)
        return true, sender.value, true, nil
    end

    if self.closed then
        return true, nil, false, nil
    end

    self.receivers[#self.receivers + 1] = {
        task = task,
    }
    return false, nil, false, nil
end

---@return boolean
function Channel:can_send()
    return self.closed or has_active(self.receivers) or #self.buffer < self.capacity
end

---@return boolean
function Channel:can_recv()
    return #self.buffer > 0 or has_active(self.senders) or self.closed
end

---@param value T
---@return boolean ready
---@return lugo.Error|nil err
function Channel:try_send(value)
    if self.closed then
        return true, channel.ErrClosed
    end

    local receiver = shift(self.receivers)
    if receiver ~= nil then
        wake_receiver(receiver, value, true, nil)
        return true, nil
    end

    if #self.buffer < self.capacity then
        self.buffer[#self.buffer + 1] = value
        return true, nil
    end

    return false, nil
end

---@return boolean ready
---@return T|nil value
---@return boolean ok
---@return lugo.Error|nil err
function Channel:try_recv()
    if #self.buffer > 0 then
        local value = shift(self.buffer)
        local sender = shift(self.senders)
        if sender ~= nil then
            self.buffer[#self.buffer + 1] = sender.value
            wake_sender(sender, true, nil)
        end
        return true, value, true, nil
    end

    local sender = shift(self.senders)
    if sender ~= nil then
        wake_sender(sender, true, nil)
        return true, sender.value, true, nil
    end

    if self.closed then
        return true, nil, false, nil
    end

    return false, nil, false, nil
end

---@param waiter lugo.scheduler.SelectWaiter
---@param case_index integer
---@param value T
---@return lugo.ChannelSender<T>
function Channel:park_select_send(waiter, case_index, value)
    ---@type lugo.ChannelSender<T>
    local sender = {
        task = waiter.task,
        value = value,
        select_waiter = waiter,
        case_index = case_index,
    }
    self.senders[#self.senders + 1] = sender
    return sender
end

---@param waiter lugo.scheduler.SelectWaiter
---@param case_index integer
---@return lugo.ChannelReceiver
function Channel:park_select_recv(waiter, case_index)
    ---@type lugo.ChannelReceiver
    local receiver = {
        task = waiter.task,
        select_waiter = waiter,
        case_index = case_index,
    }
    self.receivers[#self.receivers + 1] = receiver
    return receiver
end

---@param registration lugo.scheduler.SelectRegistration
function Channel:remove_select_registration(registration)
    local queue = registration.kind == "send" and self.senders or self.receivers
    for i = 1, #queue do
        if queue[i] == registration.entry then
            table.remove(queue, i)
            return
        end
    end
end

---@return lugo.Error|nil err
function Channel:close()
    if self.closed then
        return channel.ErrClosed
    end

    self.closed = true

    while #self.receivers > 0 do
        local receiver = shift(self.receivers)
        if receiver ~= nil then
            wake_receiver(receiver, nil, false, nil)
        end
    end

    while #self.senders > 0 do
        local sender = shift(self.senders)
        if sender ~= nil then
            wake_sender(sender, nil, channel.ErrClosed)
        end
    end

    return nil
end

---@return boolean
function Channel:is_closed()
    return self.closed
end

return channel
