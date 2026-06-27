package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

---@type lugo.testing.Register
local function register(test)
    test("select: receive ready buffered value", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan(1)
        lugo.check(ch:send("value"))

        local result, err = lugo.run(function()
            return lugo.select({
                lugo.recv(ch, function(value, ok)
                    t:is_true(ok)
                    return value
                end),
            })
        end)

        t:equal(result, "value")
        t:no_error(err)
    end)

    test("select: default runs when no channel is ready", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan()

        local result, err = lugo.run(function()
            return lugo.select({
                lugo.recv(ch, function()
                    return "recv"
                end),
                lugo.default(function()
                    return "default"
                end),
            })
        end)

        t:equal(result, "default")
        t:no_error(err)
    end)

    test("select: blocked receive wakes when sender arrives", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan()

        local result, err = lugo.run(function()
            local receiver = lugo.check(lugo.go(function()
                return lugo.select({
                    lugo.recv(ch, function(value, ok)
                        t:is_true(ok)
                        return value
                    end),
                })
            end))

            lugo.check(lugo.yield())
            lugo.check(ch:send("sent"))
            return receiver:join()
        end)

        t:equal(result, "sent")
        t:no_error(err)
    end)

    test("select: blocked send wakes when receiver arrives", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan()

        local result, err = lugo.run(function()
            local sender = lugo.check(lugo.go(function()
                return lugo.select({
                    lugo.send(ch, "sent", function()
                        return "sent"
                    end),
                })
            end))

            lugo.check(lugo.yield())
            local value, ok, recv_err = ch:recv()
            lugo.check(nil, recv_err)
            t:is_true(ok)
            t:equal(value, "sent")
            return sender:join()
        end)

        t:equal(result, "sent")
        t:no_error(err)
    end)

    test("select: closed receive calls callback with ok false", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan()
        t:no_error(ch:close())

        local result, err = lugo.run(function()
            return lugo.select({
                lugo.recv(ch, function(value, ok)
                    t:is_nil(value)
                    t:is_false(ok)
                    return "closed"
                end),
            })
        end)

        t:equal(result, "closed")
        t:no_error(err)
    end)

    test("select: closed send returns error without callback", function(t)
        ---@type lugo.Channel<string>
        local ch = lugo.chan()
        t:no_error(ch:close())
        local called = false

        local result, err = lugo.run(function()
            return lugo.select({
                lugo.send(ch, "value", function()
                    called = true
                    return "sent"
                end),
            })
        end)

        t:is_nil(result)
        t:error_is(err, lugo.channel.ErrClosed)
        t:is_false(called)
    end)

    test("select: losing registrations are removed", function(t)
        ---@type lugo.Channel<string>
        local first = lugo.chan()
        ---@type lugo.Channel<string>
        local second = lugo.chan()

        local result, err = lugo.run(function()
            local receiver = lugo.check(lugo.go(function()
                return lugo.select({
                    lugo.recv(first, function(value)
                        return "first:" .. tostring(value)
                    end),
                    lugo.recv(second, function(value)
                        return "second:" .. tostring(value)
                    end),
                })
            end))

            lugo.check(lugo.yield())
            lugo.check(second:send("value"))
            return receiver:join()
        end)

        t:equal(result, "second:value")
        t:no_error(err)

        local ok, send_err = first:send("late")
        t:is_nil(ok)
        t:error_is(send_err, lugo.scheduler.ErrNoScheduler)
    end)

    test("select: ready cases rotate", function(t)
        ---@type lugo.Channel<string>
        local first = lugo.chan(2)
        ---@type lugo.Channel<string>
        local second = lugo.chan(2)

        lugo.check(first:send("a1"))
        lugo.check(first:send("a2"))
        lugo.check(second:send("b1"))
        lugo.check(second:send("b2"))

        local result, err = lugo.run(function()
            local one = lugo.check(lugo.select({
                lugo.recv(first, function()
                    return "first"
                end),
                lugo.recv(second, function()
                    return "second"
                end),
            }))

            local two = lugo.check(lugo.select({
                lugo.recv(first, function()
                    return "first"
                end),
                lugo.recv(second, function()
                    return "second"
                end),
            }))

            return one .. "," .. two
        end)

        t:equal(result, "first,second")
        t:no_error(err)
    end)

    test("select: outside scheduler returns error", function(t)
        local result, err = lugo.select({
            lugo.default(function()
                return "default"
            end),
        })

        t:is_nil(result)
        t:error_is(err, lugo.scheduler.ErrNoScheduler)
    end)
end

return register
