MINI_TEST_DIR := deps/mini.nvim
VERBOSE ?= 0
MINI_TEST_GROUP_DEPTH := $(if $(filter 1,$(VERBOSE)),10,1)
MINI_TEST_OPTIONS := { execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = $(MINI_TEST_GROUP_DEPTH) }) } }

.PHONY: test test_file deps

test: deps
	@LC_ALL=C nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run($(MINI_TEST_OPTIONS))"

test_file: deps
	@LC_ALL=C nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)', $(MINI_TEST_OPTIONS))"

deps: $(MINI_TEST_DIR)

$(MINI_TEST_DIR):
	@mkdir -p deps
	@git clone --filter=blob:none --depth=1 https://github.com/echasnovski/mini.nvim.git $@
