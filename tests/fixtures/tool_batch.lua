-- generated with - "copilot education: auto" on 5434165ffbfd48f7d92f1686d58119643d641ac0
--
--````
-- Can you please use @{run_command} to get the current date, then check contents of current dir and /tmp, use @{files} to create a new markdownfile there with some content inside, then use @{insert_edit_into_file} to insert the word "test" in the middle of the text and finally verify this worked. Then, finish by getting date again.
--````
-- stripped unneccessary elements from `gd` buffer


return {
  messages = {
    {
      role = "user",
      content = "Run several tools, edit a file, verify it, then get the date again.",
    },
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-date-before",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"date","flag":null}',
            },
          },
          {
            id = "call-ls",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"ls","flag":null}',
            },
          },
          {
            id = "call-ls-tmp",
            ["function"] = {
              name = "run_command",
              arguments = '{"cmd":"ls /tmp","flag":null}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-date-before", index = 5 },
      tools = { call_id = "call-date-before", name = "run_command" },
      content = "`date`\n````\nTue Sep 15 17:50:34 CEST 2026\n````",
    },
    {
      role = "tool",
      _meta = { id = "message-ls", index = 6 },
      tools = { call_id = "call-ls", name = "run_command" },
      content = "`ls`\n````\nnew_file.md\nlorem_ipsum.txt\n````",
    },
    {
      role = "tool",
      _meta = { id = "message-ls-tmp", index = 7 },
      tools = { call_id = "call-ls-tmp", name = "run_command" },
      content = "`ls /tmp`\n````\ncache\nworkspace\n````",
    },
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-create",
            ["function"] = {
              name = "create_file",
              arguments = '{"content":"# New Markdown File\\nInitial content\\n","filepath":"new_file.md"}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-create", index = 9 },
      tools = { call_id = "call-create", name = "create_file" },
      content = "Failed creating `new_file.md` - File/directory already exists",
    },
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
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-read-before", index = 11 },
      tools = { call_id = "call-read-before", name = "read_file" },
      content = "Read file `new_file.md` from lines 0 - 3 (4 lines total):\n````md\n# Welcome to this markdown file!\n````",
    },
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-edit",
            ["function"] = {
              name = "insert_edit_into_file",
              arguments = '{"filepath":"new_file.md","mode":"append","explanation":"added word!","edits":[{"oldText":"# Welcome to this markdown file!","newText":"# Welcome to this markdown file! test","replaceAll":false}]}',
            },
          },
        },
      },
    },
    {
      role = "tool",
      _meta = { id = "message-edit", index = 13 },
      tools = { call_id = "call-edit", name = "insert_edit_into_file" },
      content = "Edited `new_file.md`\nadded word!", -- TODO seperate fixture checking the explanation ends up here
    },
    {
      role = "llm",
      tools = {
        calls = {
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
      _meta = { id = "message-read-after", index = 15 },
      tools = { call_id = "call-read-after", name = "read_file" },
      content = "Read file `new_file.md` from lines 0 - 3 (4 lines total):\n````md\n# Welcome to this markdown file! test\n````",
    },
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-date-after",
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
      _meta = { id = "message-date-after", index = 17 },
      tools = { call_id = "call-date-after", name = "run_command" },
      content = "`date`\n````\nTue Sep 15 17:50:48 CEST 2026\n````",
    },
  },

  expected_references = {
    { call_id = "call-date-before", name = "run_command", command = "date", message_id = "message-date-before", message_index = 5, status = "available" },
    { call_id = "call-ls", name = "run_command", command = "ls", message_id = "message-ls", message_index = 6, status = "available" },
    { call_id = "call-ls-tmp", name = "run_command", command = "ls /tmp", message_id = "message-ls-tmp", message_index = 7, status = "available" },
    { call_id = "call-create", name = "create_file", message_id = "message-create", message_index = 9, status = "available" },
    { call_id = "call-read-before", name = "read_file", message_id = "message-read-before", message_index = 11, status = "available" },
    { call_id = "call-edit", name = "insert_edit_into_file", message_id = "message-edit", message_index = 13, status = "available" },
    { call_id = "call-read-after", name = "read_file", message_id = "message-read-after", message_index = 15, status = "available" },
    { call_id = "call-date-after", name = "run_command", command = "date", message_id = "message-date-after", message_index = 17, status = "available" },
  },
}
