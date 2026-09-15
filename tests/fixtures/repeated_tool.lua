return {
  messages = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-read-before",
            ["function"] = {
              name = "read_file",
              arguments = '{"filepath":"new_file.md"}',
            },
          },
          {
            id = "call-read-after",
            ["function"] = {
              name = "read_file",
              arguments = '{"filepath":"new_file.md"}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-read-before", index = 2 },
      tools = { call_id = "call-read-before", name = "read_file" },
      content = "Welcome to this markdown file!",
    },
    {
      role = "tool",
      _meta = { id = "message-read-after", index = 3 },
      tools = { call_id = "call-read-after", name = "read_file" },
      content = "Welcome to this markdown file! test",
    },
  },

  expected_references = {
    {
      call_id = "call-read-before",
      name = "read_file",
      message_id = "message-read-before",
      message_index = 2,
      status = "available",
    },
    {
      call_id = "call-read-after",
      name = "read_file",
      message_id = "message-read-after",
      message_index = 3,
      status = "available",
    },
  },
}
