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

T["tool_references"]["supports the standard call ID form"] = function()
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-standard",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"find /tmp/hallo -type f","flag":null}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-standard", name = "run_command" },
      content = "`find /tmp/hallo -type f`\noutput",
    },
  })

  MiniTest.expect.equality(references, {
    {
      call_id = "call-standard",
      name = "run_command",
      command = "find /tmp/hallo -type f",
      message_id = nil,
      message_index = nil,
      status = "available",
    },
  })
end

T["tool_references"]["supports the Luna call ID form"] = function()
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "opaque-provider-id",
            call_id = "call-luna",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"find /tmp/hallo -type f","flag":null}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-luna", name = "run_command" },
      content = "`find /tmp/hallo -type f`\noutput",
    },
  })

  MiniTest.expect.equality(references, {
    {
      call_id = "call-luna",
      name = "run_command",
      command = "find /tmp/hallo -type f",
      message_id = nil,
      message_index = nil,
      status = "available",
    },
  })
end

T["tool_references"]["keeps repeated tool names separate"] = function()
  MiniTest.expect.equality(messages.tool_references(repeated_tool.messages),
                           repeated_tool.expected_references)
end

T["tool_references"]["ignores excess attributes"] = function()
  MiniTest.expect.equality(messages.tool_references(excess_attributes.messages),
                           excess_attributes.expected_references)
end

T["tool_references"]["handles missing messages"] = function()
  MiniTest.expect.equality(messages.tool_references(nil), {})
end

T["tool_references"]["ignores malformed run_command arguments"] = function()
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-1",
            ["function"] = {
              name = "run_command",
              arguments = "{not valid json}",
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-1", name = "run_command" },
      content = "output",
    },
  })

  MiniTest.expect.equality(references, {
    {
      call_id = "call-1",
      name = "run_command",
      command = nil,
      message_id = nil,
      message_index = nil,
      status = "available",
    },
  })
end


T["find_tool_result"] = MiniTest.new_set()
T["find_tool_result"]["returns current failed result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(tool_failure.messages, "call-create"),
                           tool_failure.expected_result)
end

T["find_tool_result"]["returns nil for an unavailable result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(fixture.messages, "missing-call"), nil)
end

T["find_tool_result"]["handles a missing call ID"] = function()
  MiniTest.expect.equality(messages.find_tool_result({}, nil), nil)
end


T["remove_run_command_prefix"] = MiniTest.new_set()

T["remove_run_command_prefix"]["removes only an exact prefix"] = function()
  MiniTest.expect.equality(messages.remove_run_command_prefix("`date`\noutput\n", "date"),
                           "output\n")
  MiniTest.expect.equality(messages.remove_run_command_prefix("`date`\noutput\n`", "date"),
                           "output\n`")
  MiniTest.expect.equality(messages.remove_run_command_prefix("date\noutput", "date"),
                           "date\noutput")
  MiniTest.expect.equality(messages.remove_run_command_prefix("prefix\n`date`\noutput", "date"),
                           "prefix\n`date`\noutput")
end

return T
