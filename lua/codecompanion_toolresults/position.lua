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

---Check whether rendered buffer lines starting at a position match a reference label.
---@param lines string[] Rendered buffer lines.
---@param start_line_number integer 1-based starting line.
---@param reference table Tool reference.
---@return integer? last_line Last matching line, or nil.
local function matching_label_end(lines, start_line_number, reference)
  local label = expected_label(reference)
  -- single line check.
  if not label then
    -- OOB.
    if start_line_number > #lines then
      return nil
    end

    local line = lines[start_line_number]
    if type(reference.name) ~= "string" or reference.name == "" then
      return nil
    end

    -- CodeCompanion renders tools without command text as either `name` or `name: ...`.
    -- Require a complete name boundary; do not match `run_command_extra` as `run_command`.
    -- This is still kind of loose, as it allows for example "read_file: Hey there, whats up dog?"
    -- to correctly match, but until the expected_label function is more fleshed out this is fine
    -- but here is a TODO until then
    if line == reference.name or line:sub(1, #reference.name + 1) == reference.name .. ":" then
      return start_line_number
    end

    return nil
  end

  -- A rare "behaviour" in CodeCompanion can result in the modell sending an underescaped newline in a run_command argument.
  -- This can render one expected label across several buffer lines. In that case we still want to match, but include the
  -- following data as well. For this we match every segment in order.
  local label_lines = vim.split(label, "\n", { plain = true })
  if start_line_number + #label_lines - 1 <= #lines then
    local matches_multiline = true

    for offset, label_line in ipairs(label_lines) do
      if lines[start_line_number + offset - 1] ~= label_line then
        matches_multiline = false
        break
      end
    end

    if matches_multiline then
      return start_line_number + #label_lines - 1
    end
  end

  -- CodeCompanion may flatten embedded command newlines to spaces in the chat buffer.
  local flattened_label = label:gsub("\r?\n", " ")
  if lines[start_line_number] == flattened_label then
    return start_line_number
  end

  return nil
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
      local match_end
      for line_number = search_start, #lines do
        local label_end = matching_label_end(lines, line_number, reference)
        if label_end then
          match_line = line_number
          match_end = label_end
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
      search_start = match_end + 1
    end
  end

  -- TODO Validate that no additional rendered tool labels remain after expected references.
  -- Extra labels currently remain unassigned and may indicate stale or mismatched chat state.
  return positions, diagnostics
end

---Find a tool reference based on the cursor line and configured selection mode.
---@param references table[] Tool references with current line positions.
---@param line integer 1-based cursor line.
---@param mode string One of `exact`, `nearest`, `above`, or `below`.
---@return table?, integer? Matching tool reference and its ordered index, or nil when absent.
function M.find_reference_at_cursor(references, line, mode)
  -- nil by default
  local selected_reference, selected_index, selected_distance

  for index, reference in ipairs(references or {}) do
    if reference.line then
      local distance = reference.line - line

      if mode == "exact" and distance == 0 then
        return reference, index
      elseif mode == "above" and distance < 0 and (not selected_distance or distance > selected_distance) then
        selected_reference, selected_index, selected_distance = reference, index, distance
      elseif mode == "below" and distance > 0 and (not selected_distance or distance < selected_distance) then
        selected_reference, selected_index, selected_distance = reference, index, distance
      elseif mode == "nearest" then
        local absolute_distance = math.abs(distance)
        -- On equal distance, prefer reference above the cursor for stable selection (matches behaviour of just following output).
        if not selected_distance or absolute_distance < selected_distance or (absolute_distance == selected_distance and distance < 0) then
          selected_reference, selected_index, selected_distance = reference, index, absolute_distance
        end
      end
    end
  end

  return selected_reference, selected_index
end

return M
