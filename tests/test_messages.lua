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

T["tool_references"]["supports the Responses call ID form"] = function()
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "opaque-provider-id",
            call_id = "call-responses",
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
      tools = { call_id = "call-responses", name = "run_command" },
      content = "`find /tmp/hallo -type f`\noutput",
    },
  })

  MiniTest.expect.equality(references, {
    {
      call_id = "call-responses",
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


T["find_tool_call"] = MiniTest.new_set()
T["find_tool_call"]["finds and decodes call arguments by call_id"] = function()
  local call = messages.find_tool_call({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "provider-id",
            call_id = "call-responses",
            ["function"] = {
              name = "read_file",
              arguments = '{"filepath":"README.md","lines":[1,4]}',
            },
          },
        },
      },
    },
  }, "call-responses")

  MiniTest.expect.equality(call, {
    call_id = "call-responses",
    name = "read_file",
    arguments = { filepath = "README.md", lines = { 1, 4 } },
  })
end

T["find_tool_call"]["returns malformed arguments without inventing decoded data"] = function()
  local call = messages.find_tool_call({
    {
      tools = {
        calls = {
          {
            id = "call-1",
            ["function"] = { name = "custom", arguments = "{invalid" },
          },
        },
      },
    },
  }, "call-1")

  MiniTest.expect.equality(call, {
    call_id = "call-1",
    name = "custom",
    arguments = "{invalid",
  })
end

T["find_tool_call"]["returns nil when call is unavailable"] = function()
  MiniTest.expect.equality(messages.find_tool_call({}, "missing-call"), nil)
end

T["find_tool_result"] = MiniTest.new_set()
T["find_tool_result"]["returns current failed result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(tool_failure.messages, "call-create"),
                           tool_failure.expected_result)
end

T["find_tool_result"]["returns nil for an unavailable result"] = function()
  MiniTest.expect.equality(messages.find_tool_result(fixture.messages, "missing-call"), nil)
end

T["find_tool_result"]["exposes current estimate metadata when present"] = function()
  local result = messages.find_tool_result({
    { role = "tool", tools = { call_id = "estimated", name = "grep_search" }, content = "output",
      _meta = { estimated_tokens = 37 } },
  }, "estimated")
  MiniTest.expect.equality(result.estimated_tokens, 37)
end

T["find_tool_result"]["handles a missing call ID"] = function()
  MiniTest.expect.equality(messages.find_tool_result({}, nil), nil)
end

T["find_tool_result"]["does not invent unavailable estimate metadata"] = function()
  local result = messages.find_tool_result({
    { role = "tool", tools = { call_id = "unknown", name = "grep_search" }, content = "output" },
  }, "unknown")
  MiniTest.expect.equality(result.estimated_tokens, nil)
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

T["prepare_tool_result_clear"] = MiniTest.new_set()

local function with_stubbed_token_module(module, callback)
  local module_name = "codecompanion.utils.tokens"
  local original = package.loaded[module_name]
  package.loaded[module_name] = module
  local ok, err = pcall(callback)
  package.loaded[module_name] = original
  if not ok then
    error(err)
  end
end

T["prepare_tool_result_clear"]["uses CodeCompanion estimator and preserves message identity"] = function()
  with_stubbed_token_module({ calculate = function(content)
    MiniTest.expect.equality(content, "User cleared this tool result.")
    return 23
  end }, function()
    local message = { role = "tool", tools = { call_id = "estimate", name = "grep_search" }, content = "large", _meta = { estimated_tokens = 500 } }
    local chat = { messages = { message } }
    local operation, err = messages.prepare_tool_result_clear(chat, "estimate")
    assert(operation, err)
    MiniTest.expect.equality(err, nil)
    local changed, current_messages, commit_error = operation.commit("User cleared this tool result.")
    MiniTest.expect.equality(changed, true)
    MiniTest.expect.equality(commit_error, nil)
    assert(current_messages)
    MiniTest.expect.equality(current_messages, chat.messages)
    MiniTest.expect.equality(current_messages[1], message)
    MiniTest.expect.equality(message._meta.estimated_tokens, 23)
    MiniTest.expect.equality(message._meta.codecompanion_toolresults_cleared, true)
  end)
end

T["prepare_tool_result_clear"]["removes stale estimate when CodeCompanion estimation fails"] = function()
  with_stubbed_token_module({ calculate = function() error("calculator unavailable") end }, function()
    local message = { role = "tool", tools = { call_id = "estimate-failure" }, content = "large", _meta = { estimated_tokens = 500 } }
    local operation, err = messages.prepare_tool_result_clear({ messages = { message } }, "estimate-failure")
    assert(operation, err)
    local changed = operation.commit("User cleared this tool result.")
    MiniTest.expect.equality(changed, true)
    MiniTest.expect.equality(message._meta.estimated_tokens, nil)
    MiniTest.expect.equality(message._meta.codecompanion_toolresults_cleared, true)
  end)
end

return T
