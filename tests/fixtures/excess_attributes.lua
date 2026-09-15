return {
  messages = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            _index = 0,
            another_important_argument = "here",
            type = "function",
            id = "call-date",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"date","flag":null}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-date", index = 2 },
      tools = { call_id = "call-date", name = "run_command" },
      content = "`date`\n````\nTue Sep 15 17:50:34 CEST 2026\n````",
    },
  },

  expected_references = {
    {
      call_id = "call-date",
      name = "run_command",
      command = "date",
      message_id = "message-date",
      message_index = 2,
      status = "available",
    },
  },
}
