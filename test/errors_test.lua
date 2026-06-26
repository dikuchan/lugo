package.path = "src/?.lua;src/?/init.lua;" .. package.path

local lugo = require("lugo")
local testing = require("lugo.testing")

local ok = testing(function(test)
  test("errors: create and wrap structured errors", function(t)
    local not_found = lugo.new_error("not found", { kind = "not_found" })
    local wrapped = lugo.wrap_error(not_found, "load user failed")

    t:equal(tostring(not_found), "not found")
    t:is_true(lugo.errors.is_error(not_found))
    t:is_true(lugo.errors.is(wrapped, not_found))
    t:equal(lugo.errors.as(wrapped, "not_found"), not_found)
  end)

  test("errors: catch converts check panic to error return", function(t)
    local not_found = lugo.new_error("not found", { kind = "not_found" })
    local wrapped = lugo.wrap_error(not_found, "load user failed")

    local value, err = lugo.catch(function()
      local user = lugo.check(nil, wrapped)
      return user
    end)

    t:is_nil(value)
    t:not_nil(err)
    t:error_is(err, not_found)
  end)

  test("errors: catch returns successful value", function(t)
    local result, err = lugo.catch(function()
      return "ok"
    end)

    t:equal(result, "ok")
    t:no_error(err)
  end)

  test("errors: catch preserves nil success", function(t)
    local function returns_nil_pair()
      return nil, nil
    end

    local result, err = lugo.catch(returns_nil_pair)

    t:is_nil(result)
    t:no_error(err)
  end)

  test("errors: catch keeps first success value", function(t)
    local function returns_pair()
      return "first", "second"
    end

    local result, err = lugo.catch(returns_pair)

    t:equal(result, "first")
    t:no_error(err)
  end)

  test("errors: join combines multiple errors", function(t)
    local not_found = lugo.new_error("not found", { kind = "not_found" })
    local joined = lugo.errors.join(nil, "first", not_found)

    if joined == nil then
      t:fatal("expected joined error")
      return
    end

    t:equal(joined.kind, "multiple")
    t:equal(#joined.fields.errors, 2)
  end)
end)

if not ok then
  error("errors_test.lua failed")
end
