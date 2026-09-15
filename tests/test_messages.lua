local MiniTest = require("mini.test")

local messages = require("codecompanion_toolresults.adapters.messages")

local fixture = require("tests.fixtures.tool_batch")
local repeated_tool = require("tests.fixtures.repeated_tool")
local single_run_command = require("tests.fixtures.single_run_command")
local tool_failure = require("tests.fixtures.tool_failure")
local excess_attributes = require("tests.fixtures.excess_attributes")

local T = MiniTest.new_set()

T["tool_references"] = MiniTest.new_set()

-- kind of "chained catchall", but I like it^^
T["tool_references"]["extracts a realistic tool batch"] = function()
  MiniTest.expect.equality(messages.tool_references(fixture.messages), fixture.expected_references)
end

-- more atomic tests
T["tool_references"]["extracts a single run_command"] = function()
  MiniTest.expect.equality(messages.tool_references(single_run_command.messages),
                           single_run_command.expected_references)
end

T["tool_references"]["keeps repeated tool names separate"] = function()
  MiniTest.expect.equality(messages.tool_references(repeated_tool.messages),
                           repeated_tool.expected_references)
end

T["tool_references"]["ignores excess attributes"] = function()
  MiniTest.expect.equality(messages.tool_references(excess_attributes.messages),
                           excess_attributes.expected_references)
end


T["find_tool_result"] = MiniTest.new_set()
T["find_tool_result"]["returns current failed result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(tool_failure.messages, "call-create"),
                           tool_failure.expected_result)
end

T["find_tool_result"]["returns nil for an unavailable result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(fixture.messages, "missing-call"), nil)
end


T["remove_run_command_prefix"] = MiniTest.new_set()

T["remove_run_command_prefix"]["removes only an exact prefix"] = function()
  MiniTest.expect.equality(messages.remove_run_command_prefix("`date`\noutput\n", "date"),
                           "output\n")
  MiniTest.expect.equality(messages.remove_run_command_prefix("`date`\noutput\n`", "date"),
                           "output\n`")
  MiniTest.expect.equality(messages.remove_run_command_prefix("date\noutput", "date"),
                           "date\noutput")
end

return T
