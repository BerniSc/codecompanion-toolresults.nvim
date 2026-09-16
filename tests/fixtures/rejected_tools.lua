return {
  messages = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            _index = 0,
            type = "function",
            id = "call-command",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"date","flag":null}',
            },
          },
          {
            _index = 1,
            type = "function",
            id = "call-grep",
            ["function"] = {
              name = "grep_search",
              arguments = '{"query":"needle","include_pattern":"*.lua"}',
            },
          },
          {
            _index = 2,
            type = "function",
            id = "call-edit",
            ["function"] = {
              name = "insert_edit_into_file",
              arguments = '{"mode":"append","explanation":"Retry appending Hi to test.txt.","filepath":"test.txt","edits":[{"newText":"Hi","oldText":"$","replaceAll":false}]}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { cycle = 4, estimated_tokens = 14, id = 46955181 },
      opts = { visible = true },
      tools = { call_id = "call-command", name = "run_command" },
      content = "The user rejected the execution of the `date` command",
    },
    {
      role = "tool",
      _meta = { cycle = 4, estimated_tokens = 14, id = 46955182 },
      opts = { visible = true },
      tools = { call_id = "call-grep", name = "grep_search" },
      content = "The user rejected the grep search tool",
    },
    {
      role = "tool",
      _meta = { cycle = 4, estimated_tokens = 27, id = 46955184 },
      opts = { visible = true },
      tools = { call_id = "call-edit", name = "insert_edit_into_file" },
      content = '**Error:**\nUser rejected the changes for `Proposed changes for `test.txt`:`, with the reason ""',
    },
  },

  expected_references = {
    {
      call_id = "call-command",
      name = "run_command",
      command = "date",
      invalidated_line = "The user rejected the execution of the `date` command",
      message_id = 46955181,
      status = "invalidated",
    },
    {
      call_id = "call-grep",
      name = "grep_search",
      invalidated_line = "The user rejected the grep search tool",
      message_id = 46955182,
      status = "invalidated",
    },
    {
      call_id = "call-edit",
      name = "insert_edit_into_file",
      invalidated_line = "User rejected the changes for `Proposed changes for `test.txt`:`, with the reason \"\"",
      message_id = 46955184,
      status = "invalidated",
    },
  },
}
