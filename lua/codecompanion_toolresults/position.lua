local M = {}

---Build the exact rendered label expected for a reference when possible.
---@param reference table Tool reference.
---@return string? label Exact label, or nil when only tool name is known.
local function expected_label(reference)
  if reference.status == "invalidated" then
    return reference.invalidated_line
  end

  if reference.name == "run_command" and type(reference.command) == "string" and reference.command ~= "" then
    return reference.name .. ": " .. reference.command
  end
end

---Check whether a rendered line (passed in full) is a tool label for a reference.
---@param line string Rendered buffer line.
---@param reference table Tool reference.
---@return boolean
local function matches_reference(line, reference)
  local label = expected_label(reference)
  if label then
    return line == label
  end

  if type(reference.name) ~= "string" or reference.name == "" then
    return false
  end

  -- CodeCompanion renders tools without command text as either `name` or `name: ...`.
  -- Require a complete name boundary; do not match `run_command_extra` as `run_command`.
  -- This is still kind of loose, as it allows for example "read_file: Hey there, whats up dog?"
  -- to correctly match, but until the expected_label function is more fleshed out this is fine
  -- but here is a TODO until then
  return line == reference.name or line:sub(1, #reference.name + 1) == reference.name .. ":"
end

---Find rendered line positions for tool references.
---@param bufnr integer
---@param references table[] Tool references in rendered message order.
---@return table<string, integer> positions Map from call ID to 1-based buffer line.
---@return table diagnostics Unresolved references and detected mapping problems.
function M.find_tool_lines(bufnr, references)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}, { invalid_buffer = true, unresolved = references or {} }
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local positions = {}
  -- unresolved is reference we could not match, ambigous the number of toolcalls that had
  -- to be invalidated because of this. "ambigous" can therefore be seen as unix-style exitcode.
  local diagnostics = { unresolved = {}, ambiguous = 0 }
  local search_start = 1

  for _, reference in ipairs(references or {}) do
    if reference.call_id then
      local match_line
      for line_number = search_start, #lines do
        if matches_reference(lines[line_number], reference) then
          match_line = line_number
          break
        end
      end

      if not match_line then
        diagnostics.unresolved[#diagnostics.unresolved + 1] = reference
        -- somethings off, therefore everything identified previously is "unsafe" as well.
        for _, previous in ipairs(references or {}) do
          if previous.call_id then
            diagnostics.ambiguous = diagnostics.ambiguous + 1
          end
        end
        return {}, diagnostics
      end

      positions[reference.call_id] = match_line
      search_start = match_line + 1
    end
  end

  -- TODO Validate that no additional rendered tool labels remain after expected references.
  -- Extra labels currently remain unassigned and may indicate stale or mismatched chat state.
  return positions, diagnostics
end

---Find the tool reference rendered on a specific line.
---@param references table[] Tool references with current line positions.
---@param line integer 1-based buffer line.
---@return table? Matching tool reference, if any.
function M.find_reference_at_line(references, line)
  for _, reference in ipairs(references or {}) do
    if reference.line == line then
      return reference
    end
  end
end

return M
