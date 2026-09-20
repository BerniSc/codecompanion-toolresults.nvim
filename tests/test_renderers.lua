local MiniTest = require("mini.test")
local renderers = require("codecompanion_toolresults.renderers")

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
}

T["fallback"] = MiniTest.new_set()

T["fallback"]["renders string content"] = function()
  MiniTest.expect.equality(renderers.render({ name = "read_file" }, { content = "one\ntwo" }, opts, context),
    { "one", "two" })
end

T["fallback"]["inspects non-string content"] = function()
  MiniTest.expect.equality(renderers.render({ name = "read_file" }, { content = { answer = 42 } }, opts, context),
    { "{", "  answer = 42", "}" })
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

return T
