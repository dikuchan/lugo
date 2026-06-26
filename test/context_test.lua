package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

local context = lugo.context

local function assert_equal(actual, expected)
  if actual ~= expected then
    error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
  end
end

local root = context.background()
assert_equal(root:err(), nil)
assert_equal(root:done():is_closed(), false)

local child, cancel = context.with_cancel(root)
assert_equal(child:err(), nil)
cancel()

assert(context.is_canceled(child:err()))
assert_equal(child:done():is_closed(), true)

local parent, parent_cancel = context.with_cancel(context.background())
local grandchild = context.with_value(parent, "request_id", "abc")
assert_equal(grandchild:value("request_id"), "abc")
assert_equal(grandchild:err(), nil)

parent_cancel()
assert(context.is_canceled(grandchild:err()))

local expired, expired_cancel = context.with_deadline(context.background(), os.time() - 1)
assert(context.is_deadline_exceeded(expired:err()))
expired_cancel()
assert(context.is_deadline_exceeded(expired:err()))

local timed, timed_cancel = context.with_timeout(context.background(), 60)
assert_equal(timed:err(), nil)
timed_cancel()
assert(context.is_canceled(timed:err()))

print("context_test.lua: ok")
