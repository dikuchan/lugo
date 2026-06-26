LUA_VERSION ?= 5.1
LUA ?= lua
LUAROCKS ?= luarocks
LUA_LANGUAGE_SERVER ?= lua-language-server
ROCKSPEC ?= lugo-scm-1.rockspec
ROCKS_TREE ?= $(CURDIR)/.rocks
TESTS := $(wildcard test/*_test.lua)
LUAROCKS_ENV = eval "$$($(LUAROCKS) --lua-version=$(LUA_VERSION) --tree=$(ROCKS_TREE) path)"

.PHONY: check typecheck deps test test-uv

check: typecheck test

deps:
	$(LUAROCKS) --lua-version=$(LUA_VERSION) --tree=$(ROCKS_TREE) make --only-deps $(ROCKSPEC)

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
		$(LUAROCKS_ENV) && $(LUA) $$test || exit 1; \
	done

test-uv:
	$(LUAROCKS_ENV) && $(LUA) test/uv_driver_test.lua
