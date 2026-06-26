package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

local context = lugo.context

return function(test)
    test("context: background is active", function(t)
        local root = context.background()

        t:is_nil(root:err())
        t:is_false(root:done():is_closed())
    end)

    test("context: cancel closes done and sets error", function(t)
        local root = context.background()
        local child, cancel = context.with_cancel(root)

        t:is_nil(child:err())
        cancel()

        t:is_true(context.is_canceled(child:err()))
        t:is_true(child:done():is_closed())
    end)

    test("context: parent cancellation propagates to child", function(t)
        local parent, cancel = context.with_cancel(context.background())
        local child = context.with_value(parent, "request_id", "abc")

        t:equal(child:value("request_id"), "abc")
        t:is_nil(child:err())

        cancel()
        t:is_true(context.is_canceled(child:err()))
    end)

    test("context: expired deadline wins over later cancel", function(t)
        local expired, cancel = context.with_deadline(context.background(), os.time() - 1)

        t:is_true(context.is_deadline_exceeded(expired:err()))
        cancel()
        t:is_true(context.is_deadline_exceeded(expired:err()))
    end)

    test("context: timeout can be canceled", function(t)
        local timed, cancel = context.with_timeout(context.background(), 60)

        t:is_nil(timed:err())
        cancel()
        t:is_true(context.is_canceled(timed:err()))
    end)
end
