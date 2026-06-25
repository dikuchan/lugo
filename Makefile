LUA ?= lua
LUA_LANGUAGE_SERVER ?= lua-language-server
TESTS := $(wildcard test/*_test.lua)

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
	@for test in $(TESTS); do \
		$(LUA) $$test || exit 1; \
	done
