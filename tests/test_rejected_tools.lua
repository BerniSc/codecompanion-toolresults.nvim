local MiniTest = require("mini.test")

local messages = require("codecompanion_toolresults.adapters.messages")
local position = require("codecompanion_toolresults.position")
local fixture = require("tests.fixtures.rejected_tools")

local T = MiniTest.new_set()

T["rejected tool references"] = MiniTest.new_set()

T["rejected tool references"]["classifies exact CodeCompanion rejection outputs"] = function()
  MiniTest.expect.equality(messages.tool_references(fixture.messages), fixture.expected_references)
end

T["rejected tool references"]["matches invalidated rendered lines"] = function()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "The user rejected the execution of the `date` command",
    "The user rejected the grep search tool",
    "User rejected the changes for `Proposed changes for `test.txt`:`, with the reason \"\"",
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, fixture.expected_references)

  MiniTest.expect.equality(positions, {
    ["call-command"] = 1,
    ["call-grep"] = 2,
    ["call-edit"] = 3,
  })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["rejected tool references"]["does not classify ordinary rejection text"] = function()
  local references = messages.tool_references({
    {
      role = "tool",
      tools = { call_id = "call-ordinary", name = "grep_search" },
      content = "Search result: rejected pattern found",
    },
  })

  MiniTest.expect.equality(references, {
    {
      call_id = "call-ordinary",
      name = "grep_search",
      status = "available",
    },
  })
end

T["rejected tool references"]["recognizes insert edit rejection output"] = function()
  local references = messages.tool_references(fixture.messages)

  MiniTest.expect.equality(references[3].status, "invalidated")
  MiniTest.expect.equality(references[3].invalidated_line, fixture.expected_references[3].invalidated_line)
end

T["rejected tool references"]["recognizes search help rejection"] = function()
  local references = messages.tool_references({
    {
      role = "tool",
      tools = { call_id = "call-search-help", name = "search_help" },
      content = "The user rejected the search help tool",
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].invalidated_line, "The user rejected the search help tool")
end

T["rejected tool references"]["matches commands containing backticks"] = function()
  local command = "printf '`nested`'"
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-backticks",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command, flag = nil }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-backticks", name = "run_command" },
      content = "The user rejected the execution of the `" .. command .. "` command",
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].command, command)
end

T["rejected tool references"]["does not use a different command rejection"] = function()
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-other-command",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = "date" }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-other-command", name = "run_command" },
      content = "The user rejected the execution of the `ls` command",
    },
  })

  MiniTest.expect.equality(references[1].status, "available")
end


T["rejected tool references"]["matches rejection reasons"] = function()
  local references = messages.tool_references({
    {
      role = "tool",
      tools = { call_id = "call-delete", name = "delete_file" },
      content = 'The user rejected the deletion of the file, with the reason: "test2"',
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
end

T["rejected tool references"]["matches dumped multiline rejection and rendered position"] = function()
  local command = "echo << EOF\nLine 1\nLine 2\nEOF"
  local rejection = 'The user rejected the execution of the `' .. command .. '` command, with the reason: "Thanks"'
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-dump-rejection",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command, flag = nil }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-dump-rejection", name = "run_command" },
      content = rejection,
    },
  })
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "The user rejected the execution of the `echo << EOF",
    "Line 1",
    'Line 2',
    'EOF` command, with the reason: "Thanks"',
  })

  local positions, diagnostics = position.find_tool_lines(bufnr, references)

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].invalidated_line, rejection)
  MiniTest.expect.equality(positions, { ["call-dump-rejection"] = 1 })
  MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["rejected tool references"]["matches rejection reason after multiline command"] = function()
  local command = "echo 'Here is a multiline\ntext example using heredoc << EOF\nLine 1\nLine 2\nEOF'"
  local rejection = 'The user rejected the execution of the `' .. command .. '` command, with the reason: "No"'
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-reason-multiline",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-reason-multiline", name = "run_command" },
      content = rejection
        .. "\n\nThe attempt to execute the multiline command using `echo << EOF ...` was **rejected** with the reason: \"No\".",
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].invalidated_line, "The user rejected the execution of the `" .. command .. "` command, with the reason: \"No\"")
end

T["rejected tool references"]["matches formatted rejected multiline commands"] = function()
  local command = "cat << EOF\na\nb\nEOF"
  local rejection = "The user rejected the execution of the `" .. command .. "` command"
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-formatted-multiline-rejected",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-formatted-multiline-rejected", name = "run_command" },
      content = "**Error:**\n" .. rejection,
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].invalidated_line, rejection)
end

T["rejected tool references"]["matches rejected multiline commands"] = function()
  local command = "cat << EOF\na\nb\nEOF"
  local references = messages.tool_references({
    {
      role = "llm",
      tools = {
        calls = {
          {
            id = "call-multiline-rejected",
            ["function"] = {
              name = "run_command",
              arguments = vim.json.encode({ cmd = command }),
            },
          },
        },
      },
    },
    {
      role = "tool",
      tools = { call_id = "call-multiline-rejected", name = "run_command" },
      content = "The user rejected the execution of the `" .. command .. "` command",
    },
  })

  MiniTest.expect.equality(references[1].status, "invalidated")
  MiniTest.expect.equality(references[1].command, command)
  MiniTest.expect.equality(references[1].invalidated_line, "The user rejected the execution of the `" .. command .. "` command")
end

return T
