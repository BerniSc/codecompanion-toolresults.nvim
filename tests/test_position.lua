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

T["find_reference_at_line"] = function()
  local reference = { call_id = "call-1", line = 7 }

  MiniTest.expect.equality(position.find_reference_at_line({ reference }, 7), reference)
  MiniTest.expect.equality(position.find_reference_at_line({ reference }, 8), nil)
end

return T
