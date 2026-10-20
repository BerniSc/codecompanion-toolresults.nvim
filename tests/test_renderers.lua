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

---@param arguments table
---@param name? string
---@param call_id? string
local function edit_context(arguments, name, call_id)
  call_id = call_id or "call-edit-success"
  return vim.tbl_extend("force", vim.deepcopy(context), {
    find_tool_call = function(found_call_id)
      if found_call_id == call_id then
        return { call_id = found_call_id, name = name or "insert_edit_into_file", arguments = arguments }
      end
    end,
  })
end

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

T["tool renderers"]["renders edit_file summary followed by argument-derived replacement patch"] = function()
  MiniTest.expect.equality(renderers.render({ name = "edit_file", call_id = "call-v20-edit" },
    { content = "Edited `src/example.lua`" }, opts, edit_context({
      filepath = "src/example.lua",
      old_string = "local answer = 1",
      new_string = "local answer = 42",
    }, "edit_file", "call-v20-edit")), {
    "Edited `src/example.lua`",
    "",
    "````diff",
    "--- a/src/example.lua",
    "+++ b/src/example.lua",
    "@@ -1 +1 @@",
    "-local answer = 1",
    "+local answer = 42",
    "````",
  })
end

T["tool renderers"]["renders create_file summary followed by full added-file patch"] = function()
  MiniTest.expect.equality(renderers.render({ name = "create_file", call_id = "call-v20-create" },
    { content = "Created `src/new.lua`" }, opts, edit_context({
      filepath = "src/new.lua",
      content = "local answer = 42\nprint(answer)",
    }, "create_file", "call-v20-create")), {
    "Created `src/new.lua`",
    "",
    "````diff",
    "--- /dev/null",
    "+++ b/src/new.lua",
    "@@ -0,0 +1,2 @@",
    "+local answer = 42",
    "+print(answer)",
    "````",
  })
end

T["tool renderers"]["keeps edit_file summary when call arguments are unavailable"] = function()
  MiniTest.expect.equality(renderers.render({ name = "edit_file", call_id = "missing" },
    { content = "Edited `src/example.lua`" }, opts, context), { "Edited `src/example.lua`" })
end

T["tool renderers"]["renders insert_edit_into_file summary followed by a patch"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.insert_edit_into_file.success_with_explanation.reference,
    fixtures.insert_edit_into_file.success_with_explanation.result, opts, edit_context({
      filepath = "/tmp/test",
      edits = { { oldText = "Hello World!", newText = "Hell! Oh World!" } },
    })), {
    "Edited `README.md`",
    "updated renderer documentation",
    "",
    "````diff",
    "--- a/tmp/test",
    "+++ b/tmp/test",
    "@@ -1 +1 @@",
    "-Hello World!",
    "+Hell! Oh World!",
    "````",
  })
end

T["tool renderers"]["renders multiple insert_edit_into_file edits as separate patches"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.insert_edit_into_file.success_with_explanation.reference,
    fixtures.insert_edit_into_file.success_with_explanation.result, opts, edit_context({
      filepath = "test.lua",
      edits = {
        { oldText = "first", newText = "one" },
        { oldText = "second", newText = "two" },
      },
    })), {
    "Edited `README.md`",
    "updated renderer documentation",
    "",
    "````diff",
    "--- a/test.lua",
    "+++ b/test.lua",
    "@@ -1 +1 @@",
    "-first",
    "+one",
    "--- a/test.lua",
    "+++ b/test.lua",
    "@@ -1 +1 @@",
    "-second",
    "+two",
    "````",
  })
end

T["tool renderers"]["keeps insert_edit_into_file summary when call arguments are unavailable"] = function()
  MiniTest.expect.equality(renderers.render(fixtures.insert_edit_into_file.success_with_explanation.reference,
    fixtures.insert_edit_into_file.success_with_explanation.result, opts, context),
    { "Edited `README.md`", "updated renderer documentation" })
end

T["tool call renderers"] = MiniTest.new_set()
T["tool call renderers"]["renders structured arguments as fenced sorted JSON"] = function()
  MiniTest.expect.equality(renderers.render_call({
    name = "read_file",
    arguments = { filepath = "README.md", lines = { 1, 4 } },
  }), {
    "Tool: read_file",
    "Arguments:",
    "````json",
    "{",
    '  "filepath": "README.md",',
    '  "lines": [',
    "    1,",
    "    4",
    "  ]",
    "}",
    "````",
  })
end

T["tool call renderers"]["uses configured run_command language for command fence"] = function()
  MiniTest.expect.equality(renderers.render_call({
    name = "run_command",
    arguments = { cmd = "printf hi" },
  }, opts), {
    "Tool: run_command",
    "Command:",
    "````bash",
    "printf hi",
    "````",
  })
end

T["tool call renderers"]["uses text fence when run_command language is disabled"] = function()
  MiniTest.expect.equality(renderers.render_call({
    name = "run_command",
    arguments = { cmd = "printf hi" },
  }, { run_command_language = false }), {
    "Tool: run_command",
    "Command:",
    "````text",
    "printf hi",
    "````",
  })
end

T["tool call renderers"]["includes additional run_command arguments when present"] = function()
  MiniTest.expect.equality(renderers.render_call({
    name = "run_command",
    arguments = { cmd = "printf hi", flag = "allow" },
  }, opts), {
    "Tool: run_command",
    "Command:",
    "````bash",
    "printf hi",
    "````",
    "Other arguments:",
    "````json",
    "{",
    '  "flag": "allow"',
    "}",
    "````",
  })
end

T["tool call renderers"]["grows fence around embedded backticks"] = function()
  MiniTest.expect.equality(renderers.render_call({
    name = "custom_tool",
    arguments = { input = "contains ```` inside" },
  }), {
    "Tool: custom_tool",
    "Arguments:",
    "`````json",
    "{",
    '  "input": "contains ```` inside"',
    "}",
    "`````",
  })
end

T["tool call renderers"]["renders string and unavailable arguments as text"] = function()
  MiniTest.expect.equality(renderers.render_call({ name = "custom_tool", arguments = "raw input" }), {
    "Tool: custom_tool",
    "Arguments:",
    "````text",
    "raw input",
    "````",
  })
  MiniTest.expect.equality(renderers.render_call({ name = "custom_tool" }), {
    "Tool: custom_tool",
    "Arguments:",
    "````text",
    "Unavailable",
    "````",
  })
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
