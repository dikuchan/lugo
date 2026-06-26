LUA_VERSION ?= 5.1
LUA ?= lua
LUAROCKS ?= luarocks
LUA_LANGUAGE_SERVER ?= lua-language-server
ROCKSPEC ?= lugo-scm-1.rockspec
ROCKS_TREE ?= $(CURDIR)/.rocks
LUAROCKS_ENV = eval "$$($(LUAROCKS) --lua-version=$(LUA_VERSION) --tree=$(ROCKS_TREE) path)"

.PHONY: check typecheck deps test

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
	$(LUAROCKS_ENV) && $(LUA) test.lua
