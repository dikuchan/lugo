package.path = "src/?.lua;src/?/init.lua;" .. package.path

local testing = require("lugo.testing")

local ok = testing.run({
    "lugo.context_test",
    "lugo.errors_test",
    "lugo.scheduler_test",
    "lugo.testing_test",
    "lugo_uv.init_test",
})

os.exit(ok and 0 or 1)
