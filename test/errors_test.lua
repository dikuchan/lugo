package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")

local function assert_equal(actual, expected)
  if actual ~= expected then
    error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
  end
end

local not_found = lugo.new_error("not found", { kind = "not_found" })
local wrapped = lugo.wrap_error(not_found, "load user failed")

assert_equal(tostring(not_found), "not found")
assert(lugo.errors.is_error(not_found))
assert(lugo.errors.is(wrapped, not_found))
assert(lugo.errors.as(wrapped, "not_found") == not_found)

local value, err = lugo.catch(function()
  local user = lugo.check(nil, wrapped)
  return user
end)

assert_equal(value, nil)
assert(err ~= nil)
assert(lugo.errors.is(err, not_found))

local result, result_err = lugo.catch(function()
  return "ok"
end)

assert_equal(result, "ok")
assert_equal(result_err, nil)

local function returns_nil_pair()
  return nil, nil
end

local nil_result, nil_err = lugo.catch(returns_nil_pair)

assert_equal(nil_result, nil)
assert_equal(nil_err, nil)

local function returns_pair()
  return "first", "second"
end

local first_result, first_err = lugo.catch(returns_pair)

assert_equal(first_result, "first")
assert_equal(first_err, nil)

local joined = lugo.errors.join(nil, "first", not_found)
assert(joined ~= nil)
assert_equal(joined.kind, "multiple")
assert_equal(#joined.fields.errors, 2)

print("errors_test.lua: ok")
