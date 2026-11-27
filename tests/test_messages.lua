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
    local changed, commit_error = operation.commit("User cleared this tool result.")
    MiniTest.expect.equality(changed, true)
    MiniTest.expect.equality(commit_error, nil)
    -- Mutation is in place on the original CodeCompanion-owned message object.
    MiniTest.expect.equality(chat.messages[1], message)
    MiniTest.expect.equality(message._meta.estimated_tokens, 23)
    MiniTest.expect.equality(message._meta.codecompanion_toolresults_cleared, true)
  end)
end

T["prepare_tool_result_clear"]["removes stale estimate when CodeCompanion estimation fails"] = function()
  with_stubbed_token_module({ calculate = function() error("calculator unavailable") end }, function()
    local message = { role = "tool", tools = { call_id = "estimate-failure" }, content = "large", _meta = { estimated_tokens = 500 } }
    local operation, err = messages.prepare_tool_result_clear({ messages = { message } }, "estimate-failure")
    assert(operation, err)
    local changed, commit_error = operation.commit("User cleared this tool result.")
    MiniTest.expect.equality(changed, true)
    MiniTest.expect.equality(commit_error, nil)
    MiniTest.expect.equality(message._meta.estimated_tokens, nil)
    MiniTest.expect.equality(message._meta.codecompanion_toolresults_cleared, true)
  end)
end

T["tool_outcome"] = MiniTest.new_set()

local function call_message(call_id, name, arguments)
  return {
    role = "llm",
    tools = { calls = { { id = call_id, ["function"] = { name = name, arguments = arguments } } } },
  }
end

local function result_message(call_id, name, content)
  return { role = "tool", tools = { call_id = call_id, name = name }, content = content }
end

T["tool_outcome"]["classifies completed and failed results"] = function()
  local stack = {
    call_message("call-ok", "read_file", '{"filepath":"a.lua"}'),
    result_message("call-ok", "read_file", "local a = 1"),
    call_message("call-fail", "create_file", '{"filepath":"new.md"}'),
    result_message("call-fail", "create_file", "Failed creating `new.md` - File/directory already exists"),
    call_message("call-error", "read_file", '{"filepath":"missing.md"}'),
    result_message("call-error", "read_file", "Error: file not found"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-ok"), "completed")
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-fail"), "failed")
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-error"), "failed")
end

T["tool_outcome"]["does not treat ordinary words as failures"] = function()
  local stack = {
    call_message("call-words", "grep_search", '{"query":"Errors"}'),
    result_message("call-words", "grep_search", "Errors are handled in init.lua"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-words"), "completed")
end

T["tool_outcome"]["classifies cancelled and rejected results"] = function()
  local stack = {
    call_message("call-cancel", "grep_search", '{"query":"needle"}'),
    result_message("call-cancel", "grep_search", "The user cancelled the execution of the grep_search tool"),
    call_message("call-reject", "read_file", '{"filepath":"secret.txt"}'),
    result_message("call-reject", "read_file", "The user rejected the read file tool"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-cancel"), "cancelled")
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-reject"), "rejected")
end

T["tool_outcome"]["classifies a multiline run_command rejection using its stored command"] = function()
  local command = "cat << EOF\nhello\nEOF"
  local stack = {
    call_message("call-multiline", "run_command", vim.json.encode({ cmd = command, flag = vim.NIL })),
    result_message("call-multiline", "run_command",
      "The user rejected the execution of the `" .. command .. "` command, with the reason: \"not now\""),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-multiline"), "rejected")
end

T["tool_outcome"]["rejection takes precedence over the failure marker"] = function()
  local stack = {
    call_message("call-both", "read_file", '{"filepath":"a"}'),
    result_message("call-both", "read_file", "Failed: nothing\nThe user rejected the read file tool"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-both"), "rejected")
end

T["tool_outcome"]["looks up repeated tools by call ID, not by name"] = function()
  local stack = {
    call_message("call-a", "grep_search", '{"query":"a"}'),
    call_message("call-b", "grep_search", '{"query":"b"}'),
    result_message("call-a", "grep_search", "Failed searching"),
    result_message("call-b", "grep_search", "matches"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-a"), "failed")
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-b"), "completed")
end

T["tool_outcome"]["reports a missing result as unavailable"] = function()
  local stack = { call_message("call-pending", "read_file", '{"filepath":"a"}') }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-pending"), "unavailable")
  MiniTest.expect.equality(messages.tool_outcome(stack, "call-unknown"), "unavailable")
  MiniTest.expect.equality(messages.tool_outcome(stack, nil), "unavailable")
end

T["overview_items"] = MiniTest.new_set()

local function summarise_for_test(command, arguments)
  if command then
    return command
  end
  return arguments and arguments.filepath or ""
end

T["overview_items"]["builds ordered items with outcome and summary"] = function()
  local stack = {
    call_message("call-a", "read_file", '{"filepath":"a.lua"}'),
    result_message("call-a", "read_file", "local a = 1"),
    call_message("call-b", "grep_search", '{"query":"needle"}'),
    result_message("call-b", "grep_search", "Failed searching"),
    call_message("call-c", "read_file", '{"filepath":"pending.lua"}'),
  }
  local items = messages.overview_items(stack, summarise_for_test)
  MiniTest.expect.equality(items, {
    { call_id = "call-a", index = 1, name = "read_file", outcome = "completed", summary = "a.lua" },
    { call_id = "call-b", index = 2, name = "grep_search", outcome = "failed", summary = "" },
    -- summarise_for_test only reads filepath, so grep_search's query is not shown here.
    { call_id = "call-c", index = 3, name = "read_file", outcome = "unavailable", summary = "pending.lua" },
  })
end

T["overview_items"]["uses run_command input as summary"] = function()
  local stack = {
    call_message("call-cmd", "run_command", vim.json.encode({ cmd = "date", flag = vim.NIL })),
    result_message("call-cmd", "run_command", "`date`\nMon"),
  }
  local items = messages.overview_items(stack, summarise_for_test)
  MiniTest.expect.equality(items[1].summary, "date")
end

T["overview_items"]["decodes run_command arguments when call_id is the only identifier"] = function()
  local command = "cat << EOF\nhello\nEOF"
  local stack = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            call_id = "call-responses-multiline",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command, flag = vim.NIL }),
            },
          },
        },
      },
    },
    result_message("call-responses-multiline", "run_command",
      "The user rejected the execution of the `" .. command .. "` command, with the reason: \"not now\""),
  }
  local items = messages.overview_items(stack, function(cmd) return cmd or "" end)
  MiniTest.expect.equality(items[1].summary, command)
  MiniTest.expect.equality(items[1].outcome, "rejected")
end

T["overview_items"]["keeps repeated tools distinct by call ID"] = function()
  local stack = {
    call_message("call-1", "grep_search", '{"query":"a"}'),
    call_message("call-2", "grep_search", '{"query":"b"}'),
    result_message("call-2", "grep_search", "matches"),
    result_message("call-1", "grep_search", "Error: bad"),
  }
  -- Items follow tool-call message order, independent of result arrival order.
  local items = messages.overview_items(stack, summarise_for_test)
  MiniTest.expect.equality(items[1].call_id, "call-1")
  MiniTest.expect.equality(items[1].outcome, "failed")
  MiniTest.expect.equality(items[2].call_id, "call-2")
  MiniTest.expect.equality(items[2].outcome, "completed")
end

T["overview_items"]["returns no items for an empty chat"] = function()
  MiniTest.expect.equality(messages.overview_items({}, summarise_for_test), {})
end

T["overview_items"]["supports the id form of tool call IDs"] = function()
  local stack = {
    { role = "llm", tools = { calls = { { id = "call_provider_form_2", ["function"] = { name = "read_file", arguments = '{"filepath":"x"}' } } } } },
    result_message("call_provider_form_2", "read_file", "ok"),
  }
  local items = messages.overview_items(stack, summarise_for_test)
  MiniTest.expect.equality(items[1].call_id, "call_provider_form_2")
  MiniTest.expect.equality(items[1].summary, "x")
end

T["tool_outcome"]["supports the id form of tool call IDs"] = function()
  local stack = {
    { role = "llm", tools = { calls = { { id = "call_provider_form_1", ["function"] = { name = "read_file" } } } } },
    result_message("call_provider_form_1", "read_file", "Failed reading"),
  }
  MiniTest.expect.equality(messages.tool_outcome(stack, "call_provider_form_1"), "failed")
end

return T
