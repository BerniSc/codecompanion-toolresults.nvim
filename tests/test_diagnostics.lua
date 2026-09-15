local MiniTest = require("mini.test")

local diagnostics = require("codecompanion_toolresults.diagnostics")

local T = MiniTest.new_set()

local function read_json(path)
  local file = assert(io.open(path, "r"))
  local content = file:read("*a")
  file:close()
  return vim.json.decode(content)
end

local function remove_directory(directory)
  vim.fn.delete(directory, "rf")
end

T["dump"] = MiniTest.new_set()

T["dump"]["writes metadata for empty state"] = function()
  local directory, error_message = diagnostics.dump({})
  MiniTest.expect.no_equality(directory, nil)
  MiniTest.expect.equality(error_message, nil)

  local metadata = read_json(directory .. "/metadata.json")
  MiniTest.expect.equality(metadata.chat_count, 0)
  MiniTest.expect.equality(metadata.chats, {})

  remove_directory(directory)
end

T["dump"]["writes current chat state and buffer lines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "diagnostic-chat")
  vim.bo[bufnr].filetype = "codecompanion"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "User message",
    "run_command: date",
  })

  local references = {
    {
      call_id = "call-1",
      name = "run_command",
      command = "date",
      line = 2,
      status = "available",
    },
  }
  local messages = {
    {
      role = "tool",
      tools = { call_id = "call-1", name = "run_command" },
      content = "output",
    },
  }

  local directory, error_message = diagnostics.dump({
    [bufnr] = {
      bufnr = bufnr,
      messages = messages,
      references = references,
      tools = { ["call-1"] = references[1] },
    },
  })

  MiniTest.expect.no_equality(directory, nil)
  MiniTest.expect.equality(error_message, nil)

  local chat_directory = directory .. "/chat-" .. bufnr
  MiniTest.expect.equality(read_json(chat_directory .. "/messages.json"), messages)
  MiniTest.expect.equality(read_json(chat_directory .. "/references.json"), references)
  MiniTest.expect.equality(read_json(chat_directory .. "/tools.json")["call-1"], references[1])

  local buffer_metadata = read_json(chat_directory .. "/buffer-metadata.json")
  MiniTest.expect.equality(buffer_metadata.valid, true)
  -- truncate so its just buffername, nvim normalizes to absolute paths
  MiniTest.expect.equality(vim.fn.fnamemodify(buffer_metadata.name, ":t"), "diagnostic-chat")
  MiniTest.expect.equality(buffer_metadata.filetype, "codecompanion")
  MiniTest.expect.equality(buffer_metadata.line_count, 2)

  local buffer_file = assert(io.open(chat_directory .. "/buffer.txt", "r"))
  local buffer_content = buffer_file:read("*a")
  buffer_file:close()
  MiniTest.expect.equality(buffer_content, "User message\nrun_command: date\n")

  local metadata = read_json(directory .. "/metadata.json")
  MiniTest.expect.equality(metadata.chat_count, 1)
  MiniTest.expect.equality(metadata.chats, { bufnr })

  remove_directory(directory)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["dump"]["writes separate snapshots for multiple buffers"] = function()
  local first_bufnr = vim.api.nvim_create_buf(false, true)
  local second_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(first_bufnr, 0, -1, false, { "first chat" })
  vim.api.nvim_buf_set_lines(second_bufnr, 0, -1, false, { "second chat" })

  local directory, error_message = diagnostics.dump({
    [first_bufnr] = {
      messages = { { role = "user", content = "first" } },
      references = {},
      tools = {},
    },
    [second_bufnr] = {
      messages = { { role = "user", content = "second" } },
      references = {},
      tools = {},
    },
  })

  MiniTest.expect.no_equality(directory, nil)
  MiniTest.expect.equality(error_message, nil)

  local metadata = read_json(directory .. "/metadata.json")
  MiniTest.expect.equality(metadata.chat_count, 2)
  MiniTest.expect.equality(#metadata.chats, 2)

  local first_directory = directory .. "/chat-" .. first_bufnr
  local first_file = assert(io.open(first_directory .. "/buffer.txt", "r"))
  MiniTest.expect.equality(first_file:read("*a"), "first chat\n")
  first_file:close()
  MiniTest.expect.equality(read_json(first_directory .. "/messages.json"), {
    { role = "user", content = "first" }})

  local second_directory = directory .. "/chat-" .. second_bufnr
  local second_file = assert(io.open(second_directory .. "/buffer.txt", "r"))
  MiniTest.expect.equality(second_file:read("*a"), "second chat\n")
  second_file:close()
  MiniTest.expect.equality(read_json(second_directory .. "/messages.json"), {
    { role = "user", content = "second" }})

  remove_directory(directory)
  vim.api.nvim_buf_delete(first_bufnr, { force = true })
  vim.api.nvim_buf_delete(second_bufnr, { force = true })
end

T["dump"]["records invalid buffers without reading them"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })

  local directory, error_message = diagnostics.dump({
    [bufnr] = {
      messages = {},
      references = {},
      tools = {},
    },
  })

  MiniTest.expect.no_equality(directory, nil)
  MiniTest.expect.equality(error_message, nil)

  local chat_directory = directory .. "/chat-" .. bufnr
  local buffer_metadata = read_json(chat_directory .. "/buffer-metadata.json")
  MiniTest.expect.equality(buffer_metadata.valid, false)

  local buffer_file = assert(io.open(chat_directory .. "/buffer.txt", "r"))
  local buffer_content = buffer_file:read("*a")
  buffer_file:close()
  MiniTest.expect.equality(buffer_content, "[buffer invalid]\n")

  remove_directory(directory)
end

T["dump"]["uses a supplied directory"] = function()
  local directory = vim.fn.tempname()
  local created_directory, error_message = diagnostics.dump({}, { directory = directory })

  MiniTest.expect.equality(created_directory, directory)
  MiniTest.expect.equality(error_message, nil)
  MiniTest.expect.equality(vim.fn.filereadable(directory .. "/metadata.json"), 1)

  remove_directory(directory)
end

return T
