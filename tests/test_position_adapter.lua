local MiniTest = require("mini.test")

local positions = require("codecompanion_toolresults.adapters.positions")

local T = MiniTest.new_set()

local function with_buffer(lines, callback)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local ok, err = pcall(callback, bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  if not ok then
    error(err)
  end
end

T["version gate"] = MiniTest.new_set()

T["version gate"]["selects extmarks at v20.1.0 and newer"] = function()
  for _, version in ipairs({ "20.1.0", "20.1.1", "20.2.0", "21.0.0" }) do
    MiniTest.expect.equality(positions._uses_extmark_tool_output(version), true)
  end
end

T["version gate"]["selects the legacy locator below v20.1.0"] = function()
  for _, version in ipairs({ "19.99.0", "20.0.0", "20.0.1", "20.0.99" }) do
    MiniTest.expect.equality(positions._uses_extmark_tool_output(version), false)
  end
end

T["version gate"]["rejects malformed or unavailable versions"] = function()
  for _, version in ipairs({ nil, "", "main", "20.x.0" }) do
    MiniTest.expect.equality(positions._uses_extmark_tool_output(version), false)
  end
end

T["find_tool_lines"] = MiniTest.new_set()

T["find_tool_lines"]["uses legacy labels below v20.1.0"] = function()
  with_buffer({ "**Execute** date", "run_command: date" }, function(bufnr)
    local found, diagnostics = positions.find_tool_lines(bufnr, {
      { call_id = "call-legacy", name = "run_command", command = "date", status = "available" },
    }, {}, "20.0.1")

    MiniTest.expect.equality(found, { ["call-legacy"] = 2 })
    MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  end)
end

-- Did not really want to do it this way, but CodeCompanions version() returned 20.0.1, even though my CodeCompanion
-- already has the new feature. Therefore I have to have this as fallback.
T["find_tool_lines"]["uses extmark capability even when reported version is older"] = function()
  with_buffer({ "**Execute** date" }, function(bufnr)
    local namespace = vim.api.nvim_create_namespace("CodeCompanion-tool_calls")
    local mark = vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, 0, { right_gravity = false })
    local chat = { tool_call_marks = { [mark] = "call-patched" } }

    local found, diagnostics = positions.find_tool_lines(bufnr, {
      { call_id = "call-patched", name = "run_command", command = "date", status = "available" },
    }, chat, "20.0.1")

    MiniTest.expect.equality(found, { ["call-patched"] = 1 })
    MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  end)
end

T["find_tool_lines"]["locates new-format lines by call ID extmarks"] = function()
  with_buffer({ "**Execute** date", "**Read** README.md", "Following response" }, function(bufnr)
    local namespace = vim.api.nvim_create_namespace("CodeCompanion-tool_calls")
    local execute_mark = vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, 0, { right_gravity = false })
    local read_mark = vim.api.nvim_buf_set_extmark(bufnr, namespace, 1, 0, { right_gravity = false })
    local chat = { tool_call_marks = { [execute_mark] = "call-execute", [read_mark] = "call-read" } }

    local found, diagnostics = positions.find_tool_lines(bufnr, {
      { call_id = "call-execute", name = "run_command", command = "date", status = "available" },
      { call_id = "call-read", name = "read_file", status = "available" },
    }, chat, "20.1.0")

    MiniTest.expect.equality(found, { ["call-execute"] = 1, ["call-read"] = 2 })
    MiniTest.expect.equality(diagnostics, { unresolved = {}, ambiguous = 0 })
  end)
end

T["find_tool_lines"]["does not fall back to labels at or above v20.1.0"] = function()
  with_buffer({ "run_command: date", "**Execute** date" }, function(bufnr)
    local found, diagnostics = positions.find_tool_lines(bufnr, {
      { call_id = "call-new", name = "run_command", command = "date", status = "available" },
    }, { tool_call_marks = {} }, "20.1.0")

    MiniTest.expect.equality(found, {})
    MiniTest.expect.equality(#diagnostics.unresolved, 1)
    MiniTest.expect.equality(diagnostics.ambiguous, 1)
  end)
end

T["find_tool_lines"]["rejects an unrecognized version instead of guessing"] = function()
  with_buffer({ "run_command: date" }, function(bufnr)
    local found, diagnostics = positions.find_tool_lines(bufnr, {
      { call_id = "call-unknown", name = "run_command", command = "date", status = "available" },
    }, {}, "main")

    MiniTest.expect.equality(found, {})
    MiniTest.expect.equality(diagnostics.unsupported_version, "main")
    MiniTest.expect.equality(diagnostics.ambiguous, 1)
  end)
end

return T
