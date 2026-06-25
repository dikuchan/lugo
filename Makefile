LUA ?= lua
LUA_LANGUAGE_SERVER ?= lua-language-server

.PHONY: check typecheck test

check: typecheck test

typecheck:
	$(LUA_LANGUAGE_SERVER) \
		--check=. \
		--checklevel=Hint \
		--check_format=pretty \
		--configpath=$(CURDIR)/.luarc.json \
		--logpath=.lua-ls/log \
		--metapath=.lua-ls/meta

test:
	$(LUA) test/errors_test.lua
