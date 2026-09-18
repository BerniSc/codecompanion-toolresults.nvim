local MiniTest = require("mini.test")

local messages = require("codecompanion_toolresults.adapters.messages")
local position = require("codecompanion_toolresults.position")
local fixture = require("tests.fixtures.cancelled_tools")

local T = MiniTest.new_set()

T["cancelled tool references"] = MiniTest.new_set()

T["cancelled tool references"]["classifies exact CodeCompanion cancellation output"] = function()
  local references = messages.tool_references({
    {
      role = "tool",
      tools = { call_id = "call-cancelled", name = "run_command" },
      content = "The user cancelled the execution of the run_command tool",
    },
  })

  MiniTest.expect.equality(references[1], {
    call_id = "call-cancelled",
    name = "run_command",
    command = nil,
    invalidated_line = "Cancelled `run_command`",
    message_id = nil,
    message_index = nil,
    status = "invalidated",
  })
end

T["cancelled tool references"]["matches cancelled rendered lines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "Cancelled `run_command`",
    "Cancelled `grep_search`",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, {
    {
      call_id = "call-command",
      name = "run_command",
      invalidated_line = "Cancelled `run_command`",
      status = "invalidated",
    },
    {
      call_id = "call-grep",
      name = "grep_search",
      invalidated_line = "Cancelled `grep_search`",
      status = "invalidated",
    },
  })

  MiniTest.expect.equality(positions, {
    ["call-command"] = 1,
    ["call-grep"] = 2,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["cancelled tool references"]["preserves mixed successful and cancelled batch order"] = function()
  local references = messages.tool_references(fixture.messages)
  MiniTest.expect.equality(references, fixture.expected_references)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, fixture.rendered_lines)

  local positions, diagnostics = position.find_tool_lines(bufnr, references)
  MiniTest.expect.equality(positions, fixture.expected_positions)
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
