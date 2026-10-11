ROCKS := .rocks
LUACOV := $(ROCKS)/share/lua/5.1/luacov.lua

.PHONY: test coverage lint fmt fmt-check check clean

test:
	nvim -l tests/run.lua

$(LUACOV):
	luarocks --lua-version 5.1 --tree $(ROCKS) install luacov

coverage: $(LUACOV)
	rm -f luacov.stats.out luacov.report.out
	COVERAGE=1 nvim -l tests/run.lua
	nvim -l tests/coverage.lua

lint:
	selene lua plugin bin tests

fmt:
	stylua .

fmt-check:
	stylua --check .

check: fmt-check lint coverage

clean:
	rm -rf $(ROCKS) luacov.stats.out luacov.report.out
