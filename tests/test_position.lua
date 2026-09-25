local MiniTest = require("mini.test")
local position = require("codecompanion_toolresults.position")

local T = MiniTest.new_set()

T["find_tool_lines"] = MiniTest.new_set()

T["find_tool_lines"]["finds ordered tool labels"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "User message",
    "run_command: date",
    "Other message",
    "read_file: README.md",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "run_command", command = "date" },
    { call_id = "call-2", name = "read_file" },
  })

  MiniTest.expect.equality(positions, { ["call-1"] = 2, ["call-2"] = 4 })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["does not match a longer tool name"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "run_command_extra: date" })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "run_command" },
  })

  MiniTest.expect.equality(positions, {})
  MiniTest.expect.equality(#diagnostics.unresolved, 1)
  MiniTest.expect.equality(diagnostics.ambiguous, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["matches a tool name without arguments"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "read_file" })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "read_file" },
  })

  MiniTest.expect.equality(positions, { ["call-1"] = 1 })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["rejects an unresolved later reference"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "run_command: date" })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "run_command", command = "date" },
    { call_id = "call-2", name = "read_file" },
  })

  MiniTest.expect.equality(positions, {})
  MiniTest.expect.equality(#diagnostics.unresolved, 1)
  MiniTest.expect.equality(diagnostics.ambiguous, 2)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["reports an invalid buffer"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "read_file" },
  })

  MiniTest.expect.equality(positions, {})
  MiniTest.expect.equality(diagnostics.invalid_buffer, true)
  MiniTest.expect.equality(#diagnostics.unresolved, 1)
end

T["find_tool_lines"]["matches a run_command label split across rendered lines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "run_command: printf 'first",
    "second'",
    "read_file: README.md",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-1", name = "run_command", command = "printf 'first\nsecond'" },
    { call_id = "call-2", name = "read_file" },
  })

  MiniTest.expect.equality(positions, { ["call-1"] = 1, ["call-2"] = 3 })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["matches a run_command label across more than two rendered lines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "read_file: before.txt",
    "run_command: printf 'first",
    "second",
    "third",
    "fourth'",
    "grep_search: after",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-before", name = "read_file" },
    {
      call_id = "call-multiline",
      name = "run_command",
      command = "printf 'first\nsecond\nthird\nfourth'",
    },
    { call_id = "call-after", name = "grep_search" },
  })

  MiniTest.expect.equality(positions, {
    ["call-before"] = 1,
    ["call-multiline"] = 2,
    ["call-after"] = 6,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["matches multiline labels with doubled backslashes"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "read_file: before.txt",
    "run_command: printf 'C:\\\\temp\\\\file",
    "next line",
    "last line'",
    "grep_search: after",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-before", name = "read_file" },
    {
      call_id = "call-escaped",
      name = "run_command",
      command = "printf 'C:\\\\temp\\\\file\nnext line\nlast line'",
    },
    { call_id = "call-after", name = "grep_search" },
  })

  MiniTest.expect.equality(positions, {
    ["call-before"] = 1,
    ["call-escaped"] = 2,
    ["call-after"] = 5,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["distinguishes escaped backslash-n from rendered newline"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "read_file: before.txt",
    "run_command: printf 'literal\\nnewline'",
    "run_command: printf 'rendered",
    "newline'",
    "grep_search: after",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-before", name = "read_file" },
    {
      call_id = "call-literal-escaped-newline",
      name = "run_command",
      command = "printf 'literal\\nnewline'",
    },
    {
      call_id = "call-rendered-newline",
      name = "run_command",
      command = "printf 'rendered\nnewline'",
    },
    { call_id = "call-after", name = "grep_search" },
  })

  MiniTest.expect.equality(positions, {
    ["call-before"] = 1,
    ["call-literal-escaped-newline"] = 2,
    ["call-rendered-newline"] = 3,
    ["call-after"] = 5,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["matches a command flattened after embedded newlines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "run_command: cat << EOF a b EOF",
    "Following response",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    {
      call_id = "call-heredoc",
      name = "run_command",
      command = "cat << EOF\na\nb\nEOF",
    },
  })

  MiniTest.expect.equality(positions, { ["call-heredoc"] = 1 })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_tool_lines"]["matches each newline escape depth correctly"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "read_file: before.txt",
    "run_command: printf 'one\\nline'",
    "run_command: printf 'two\\\\nline'",
    "run_command: printf 'actual",
    "newline'",
    "grep_search: after",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    { call_id = "call-before", name = "read_file" },
    {
      call_id = "call-one-backslash",
      name = "run_command",
      command = "printf 'one\\nline'",
    },
    {
      call_id = "call-two-backslashes",
      name = "run_command",
      command = "printf 'two\\\\nline'",
    },
    {
      call_id = "call-actual-newline",
      name = "run_command",
      command = "printf 'actual\nnewline'",
    },
    { call_id = "call-after", name = "grep_search" },
  })

  MiniTest.expect.equality(positions, {
    ["call-before"] = 1,
    ["call-one-backslash"] = 2,
    ["call-two-backslashes"] = 3,
    ["call-actual-newline"] = 4,
    ["call-after"] = 6,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["find_reference_at_cursor"] = MiniTest.new_set()

T["find_reference_at_cursor"]["exact mode only matches cursor line"] = function()
  local references = {
    { call_id = "above", line = 6 },
    { call_id = "exact", line = 7 },
    { call_id = "below", line = 8 },
  }

  local reference, index = position.find_reference_at_cursor(references, 7, "exact")
  MiniTest.expect.equality(reference, references[2])
  MiniTest.expect.equality(index, 2)
  MiniTest.expect.equality(position.find_reference_at_cursor(references, 9, "exact"), nil)
end

T["find_reference_at_cursor"]["nearest mode selects closest reference and prefers above on ties"] = function()
  local references = {
    { call_id = "above", line = 6 },
    { call_id = "below", line = 8 },
    { call_id = "far", line = 12 },
  }

  local reference, index = position.find_reference_at_cursor(references, 7, "nearest")
  MiniTest.expect.equality(reference, references[1])
  MiniTest.expect.equality(index, 1)

  reference, index = position.find_reference_at_cursor(references, 11, "nearest")
  MiniTest.expect.equality(reference, references[3])
  MiniTest.expect.equality(index, 3)
end

T["find_reference_at_cursor"]["above and below modes select nearest strict direction"] = function()
  local references = {
    { call_id = "first", line = 3 },
    { call_id = "above", line = 6 },
    { call_id = "cursor", line = 7 },
    { call_id = "below", line = 9 },
    { call_id = "last", line = 12 },
  }

  local reference, index = position.find_reference_at_cursor(references, 7, "above")
  MiniTest.expect.equality(reference, references[2])
  MiniTest.expect.equality(index, 2)

  reference, index = position.find_reference_at_cursor(references, 7, "below")
  MiniTest.expect.equality(reference, references[4])
  MiniTest.expect.equality(index, 4)

  MiniTest.expect.equality(position.find_reference_at_cursor(references, 2, "above"), nil)
  MiniTest.expect.equality(position.find_reference_at_cursor(references, 13, "below"), nil)
end

return T
