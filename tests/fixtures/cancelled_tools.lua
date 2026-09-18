return {
  messages = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-success",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"date"}',
            },
          },
          {
            id = "call-cancelled-date",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"date"}',
            },
          },
          {
            id = "call-cancelled-ls",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"ls"}',
            },
          },
          {
            id = "call-cancelled-grep",
            ["function"] = {
              name = "grep_search",
              arguments = '{"query":"needle"}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-success", name = "run_command" },
      content = "`date`\n````\noutput\n````",
    },
    {
      role = "tool",
      tools = { call_id = "call-cancelled-date", name = "run_command" },
      content = "The user cancelled the execution of the run_command tool",
    },
    {
      role = "tool",
      tools = { call_id = "call-cancelled-ls", name = "run_command" },
      content = "The user cancelled the execution of the run_command tool",
    },
    {
      role = "tool",
      tools = { call_id = "call-cancelled-grep", name = "grep_search" },
      content = "The user cancelled the execution of the grep_search tool",
    },
  },

  expected_references = {
    {
      call_id = "call-success",
      name = "run_command",
      command = "date",
      status = "available",
    },
    {
      call_id = "call-cancelled-date",
      name = "run_command",
      command = "date",
      invalidated_line = "Cancelled `run_command`",
      status = "invalidated",
    },
    {
      call_id = "call-cancelled-ls",
      name = "run_command",
      command = "ls",
      invalidated_line = "Cancelled `run_command`",
      status = "invalidated",
    },
    {
      call_id = "call-cancelled-grep",
      name = "grep_search",
      invalidated_line = "Cancelled `grep_search`",
      status = "invalidated",
    },
  },

  rendered_lines = {
    "run_command: date",
    "Cancelled `run_command`",
    "Cancelled `run_command`",
    "Cancelled `grep_search`",
  },

  expected_positions = {
    ["call-success"] = 1,
    ["call-cancelled-date"] = 2,
    ["call-cancelled-ls"] = 3,
    ["call-cancelled-grep"] = 4,
  },
}
