return {
  messages = {
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-create",
            ["function"] = {
              name = "create_file",
              arguments = '{"content":"Initial content\\n","filepath":"new_file.md"}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-create", index = 2 },
      tools = { call_id = "call-create", name = "create_file" },
      content = "Failed creating `new_file.md` - File/directory already exists",
    },
  },

  expected_result = {
    call_id = "call-create",
    name = "create_file",
    message_id = "message-create",
    message_index = 2,
    content = "Failed creating `new_file.md` - File/directory already exists",
    status = "available",
  },
}
