package = "lugo"
version = "scm-1"

source = {
  url = "git+https://github.com/dikuchan/lugo.git",
}

description = {
  summary = "Go-like programming model for Lua.",
  detailed = "Lugo provides Go-like structured errors, contexts, cooperative scheduling, and optional libuv-backed timers for Lua.",
  homepage = "https://github.com/dikuchan/lugo",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1, < 5.2",
  "luv >= 1.52.1, < 2.0",
}

build = {
  type = "builtin",
  modules = {
    ["lugo"] = "src/lugo/init.lua",
    ["lugo.channel"] = "src/lugo/channel.lua",
    ["lugo.context"] = "src/lugo/context.lua",
    ["lugo.errors"] = "src/lugo/errors.lua",
    ["lugo.scheduler"] = "src/lugo/scheduler.lua",
    ["lugo.testing"] = "src/lugo/testing.lua",
    ["lugo_uv"] = "src/lugo_uv/init.lua",
  },
}
