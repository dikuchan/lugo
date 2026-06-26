---@class lugo.ChannelSender<T>
---@field task lugo.Task<any>
---@field value T

---@class lugo.ChannelReceiver
---@field task lugo.Task<any>

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
    local value = queue[1]
    table.remove(queue, 1)
    return value
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
        receiver.task.scheduler:enqueue(receiver.task, value, true, nil)
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
        receiver.task.scheduler:enqueue(receiver.task, value, true, nil)
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
            sender.task.scheduler:enqueue(sender.task, true, nil)
        end
        return value, true, nil
    end

    local sender = shift(self.senders)
    if sender ~= nil then
        sender.task.scheduler:enqueue(sender.task, true, nil)
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
            sender.task.scheduler:enqueue(sender.task, true, nil)
        end
        return true, value, true, nil
    end

    local sender = shift(self.senders)
    if sender ~= nil then
        sender.task.scheduler:enqueue(sender.task, true, nil)
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

---@return lugo.Error|nil err
function Channel:close()
    if self.closed then
        return channel.ErrClosed
    end

    self.closed = true

    while #self.receivers > 0 do
        local receiver = shift(self.receivers)
        receiver.task.scheduler:enqueue(receiver.task, nil, false, nil)
    end

    while #self.senders > 0 do
        local sender = shift(self.senders)
        sender.task.scheduler:enqueue(sender.task, nil, channel.ErrClosed)
    end

    return nil
end

---@return boolean
function Channel:is_closed()
    return self.closed
end

return channel
