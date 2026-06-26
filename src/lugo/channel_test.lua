package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

return function(test)
    test("channel: buffered send and receive", function(t)
        local ch = lugo.chan(1)

        t:no_error(select(2, ch:send("value")))

        local value, ok, err = ch:recv()
        t:equal(value, "value")
        t:is_true(ok)
        t:no_error(err)
    end)

    test("channel: unbuffered send waits for receiver", function(t)
        local ch = lugo.chan()
        local seen

        local result, err = lugo.run(function()
            local sender = lugo.check(lugo.go(function()
                lugo.check(ch:send("value"))
                seen = "sent"
            end))

            lugo.check(lugo.yield())
            t:is_nil(seen)

            local value, ok, recv_err = ch:recv()
            t:no_error(recv_err)
            t:is_true(ok)
            t:equal(value, "value")

            lugo.check(sender:join())
            return "done"
        end)

        t:equal(result, "done")
        t:no_error(err)
        t:equal(seen, "sent")
    end)

    test("channel: receiver waits for unbuffered sender", function(t)
        local ch = lugo.chan()
        local received

        local result, err = lugo.run(function()
            local receiver = lugo.check(lugo.go(function()
                local value, ok, recv_err = ch:recv()
                lugo.check(nil, recv_err)
                if ok then
                    received = value
                end
                return ok
            end))

            lugo.check(lugo.yield())
            t:is_nil(received)

            lugo.check(ch:send("value"))
            t:is_true(receiver:join())
            return "done"
        end)

        t:equal(result, "done")
        t:no_error(err)
        t:equal(received, "value")
    end)

    test("channel: closed buffered channel drains before closed receive", function(t)
        local ch = lugo.chan(2)

        lugo.check(ch:send("a"))
        lugo.check(ch:send("b"))
        t:no_error(ch:close())

        local first, first_ok, first_err = ch:recv()
        local second, second_ok, second_err = ch:recv()
        local third, third_ok, third_err = ch:recv()

        t:equal(first, "a")
        t:is_true(first_ok)
        t:no_error(first_err)
        t:equal(second, "b")
        t:is_true(second_ok)
        t:no_error(second_err)
        t:is_nil(third)
        t:is_false(third_ok)
        t:no_error(third_err)
    end)

    test("channel: send on closed channel returns error", function(t)
        local ch = lugo.chan()

        t:no_error(ch:close())

        local ok, err = ch:send("value")
        t:is_nil(ok)
        t:error_is(err, lugo.channel.ErrClosed)
    end)

    test("channel: double close returns error", function(t)
        local ch = lugo.chan()

        t:no_error(ch:close())
        t:error_is(ch:close(), lugo.channel.ErrClosed)
    end)

    test("channel: unbuffered send outside scheduler returns error", function(t)
        local ch = lugo.chan()

        local ok, err = ch:send("value")
        t:is_nil(ok)
        t:error_is(err, lugo.scheduler.ErrNoScheduler)
    end)

    test("channel: close wakes receiver", function(t)
        local ch = lugo.chan()
        local received_ok

        local result, err = lugo.run(function()
            local receiver = lugo.check(lugo.go(function()
                local value, ok, recv_err = ch:recv()
                lugo.check(nil, recv_err)
                t:is_nil(value)
                received_ok = ok
            end))

            lugo.check(lugo.yield())
            t:no_error(ch:close())
            lugo.check(receiver:join())
            return "done"
        end)

        t:equal(result, "done")
        t:no_error(err)
        t:is_false(received_ok)
    end)

    test("channel: close wakes sender with error", function(t)
        local ch = lugo.chan()
        local send_err

        local result, err = lugo.run(function()
            local sender = lugo.check(lugo.go(function()
                local ok, inner_err = ch:send("value")
                t:is_nil(ok)
                send_err = inner_err
            end))

            lugo.check(lugo.yield())
            t:no_error(ch:close())
            lugo.check(sender:join())
            return "done"
        end)

        t:equal(result, "done")
        t:no_error(err)
        t:error_is(send_err, lugo.channel.ErrClosed)
    end)
end
