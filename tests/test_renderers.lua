local MiniTest = require("mini.test")
local renderers = require("codecompanion_toolresults.renderers")
local message_adapter = require("codecompanion_toolresults.adapters.messages")
local fixtures = require("tests.fixtures.renderers._barrell")

local T = MiniTest.new_set()

local opts = { run_command_language = "bash" }
local context = {
  remove_run_command_prefix = function(content, command)
    local prefix = string.format("`%s`\n", command)
    if content:sub(1, #prefix) == prefix then
      return content:sub(#prefix + 1)
    end
    return content
  end,
  normalize_result = message_adapter.normalize_result,
}

T["truncation"] = MiniTest.new_set()

T["truncation"]["moves a final CodeCompanion notice above the result"] = function()
  local notice = "[Tool output truncated: it was around 100 tokens, which is over the 50 token limit for a single tool result.]"
  local content, metadata = message_adapter.normalize_result("before\n\n" .. notice)

  MiniTest.expect.equality(content, "before")
  MiniTest.expect.equality(metadata.truncation_notice, notice)
  MiniTest.expect.equality(renderers.render({ name = "unknown" }, { content = "before\n\n" .. notice }, opts, context),
    { "⚠ " .. notice, "before" })
end

T["truncation"]["does not treat an inline marker as truncation"] = function()
  local notice = "[Tool output truncated: it was around 100 tokens, which is over the 50 token limit for a single tool result.]"
  local content, metadata = message_adapter.normalize_result("before " .. notice .. " after")

  MiniTest.expect.equality(content, "before " .. notice .. " after")
  MiniTest.expect.equality(metadata.truncation_notice, nil)
  MiniTest.expect.equality(renderers.render({ name = "unknown" }, { content = content }, opts, context),
    { "before " .. notice .. " after" })
end


T["fallback"] = MiniTest.new_set()

T["fallback"]["renders string content"] = function()
  MiniTest.expect.equality(renderers.render({ name = "read_file" }, { content = "one\ntwo" }, opts, context),
    { "one", "two" })
end

T["fallback"]["inspects non-string content"] = function()
  MiniTest.expect.equality(renderers.render({ name = "read_file" }, { content = { answer = 42 } }, opts, context),
    { "{", "  answer = 42", "}" })
end

T["tool renderers"] = MiniTest.new_set()

T["tool renderers"]["renders file_search matches without wrapper or fence"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.file_search.matches.reference, fixtures.file_search.matches.result, opts, context),
    { "Searched files for `**/*.lua`, 2 results", "````text", "lua/init.lua", "lua/module.lua", "````" })
end

T["tool renderers"]["renders grep_search matches without notes"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.grep_search.matches.reference, fixtures.grep_search.matches.result, opts, context),
    { "Searched text for `renderer`, 3 results", "````text", "lua/codecompanion_toolresults/renderers.lua:1", "lua/codecompanion_toolresults/display.lua:4", "tests/test_renderers.lua:2", "````" })
end

T["tool renderers"]["renders read_file content without fence"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.read_file.markdown.reference, fixtures.read_file.markdown.result, opts, context),
    { "Read file `README.md` from lines 0 - 2 (3 lines total):", "````md", "# Project", "", "Description", "````" })
end

T["tool renderers"]["preserves diagnostics report"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.get_diagnostics.diagnostics.reference, fixtures.get_diagnostics.diagnostics.result, opts, context),
    { "Diagnostics for `lua/example.lua` (2 found):", "1:1 ERROR lua-language-server undefined global `vim`", "4:5 WARNING lua-language-server unused local `value`", "", "Code:", "1: local value = vim.api.nvim_get_current_buf()", "4: return value" })
end

T["run_command"] = MiniTest.new_set()
T["run_command"]["renders command and removes duplicated prefix"] = function()
  MiniTest.expect.equality(
    renderers.render({ name = "run_command", command = "printf hi" }, { content = "`printf hi`\nhi" }, opts, context),
    { "````bash", "printf hi", "````", "hi" })
end

T["run_command"]["keeps raw content when language disabled"] = function()
  MiniTest.expect.equality(
    renderers.render({ name = "run_command", command = "printf hi" }, { content = "`printf hi`\nhi" }, { run_command_language = false }, context),
    { "`printf hi`", "hi" })
end

T["run_command"]["grows fence around embedded backticks"] = function()
  MiniTest.expect.equality(renderers._format_codeblock("a````b", "text"),
    "`````text\na````b\n`````")
end

T["run_command"]["renders a bash command block and preserves output"] = function()
  MiniTest.expect.equality(renderers.render({ name = "run_command", command = "find /tmp/hallo -type f" },
        { content = "`find /tmp/hallo -type f`\n````\n/tmp/hallo/1\n/tmp/hallo/2\n````" }, opts, context),
    { "````bash", "find /tmp/hallo -type f", "````", "````", "/tmp/hallo/1", "/tmp/hallo/2", "````" })
end

return T
