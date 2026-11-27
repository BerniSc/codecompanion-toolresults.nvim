local M = {}

local TOOL_CALL_NAMESPACE = "CodeCompanion-tool_calls"

---Resolve current ACP summary lines by their live call-ID extmarks.
---@param bufnr integer Chat buffer.
---@param references CodeCompanionToolresults.ToolReference[] Current lightweight references.
---@param chat CodeCompanionToolresults.CodeCompanionChat
---@return table<string, integer> positions
---@return CodeCompanionToolresults.PositionDiagnostics diagnostics
function M.find_tool_lines(bufnr, references, chat)
  local unresolved = {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}, { invalid_buffer = true, unresolved = references or {}, ambiguous = 0 }
  end

  local references_by_call_id = {}
  for _, reference in ipairs(references or {}) do
    if type(reference.call_id) == "string" then
      references_by_call_id[reference.call_id] = reference
    else
      unresolved[#unresolved + 1] = reference
    end
  end

  local marks_by_extmark = chat and chat.tool_call_marks
  if type(marks_by_extmark) ~= "table" then
    for _, reference in pairs(references_by_call_id) do
      unresolved[#unresolved + 1] = reference
    end
    return {}, { unresolved = unresolved, ambiguous = 0 }
  end

  local namespace = vim.api.nvim_create_namespace(TOOL_CALL_NAMESPACE)
  local ok, extmarks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, namespace, 0, -1, {})
  if not ok then
    for _, reference in pairs(references_by_call_id) do
      unresolved[#unresolved + 1] = reference
    end
    return {}, { unresolved = unresolved, ambiguous = 0 }
  end

  local positions = {}
  for _, extmark in ipairs(extmarks) do
    local call_id = marks_by_extmark[extmark[1]]
    if references_by_call_id[call_id] then
      local line = extmark[2] + 1
      -- CodeCompanion may mark both summary and approval prompt; summary comes first.
      if not positions[call_id] or line < positions[call_id] then
        positions[call_id] = line
      end
    end
  end

  local line_call_ids = {}
  for call_id, line in pairs(positions) do
    line_call_ids[line] = line_call_ids[line] or {}
    line_call_ids[line][call_id] = true
  end

  local ambiguous = 0
  for line, call_ids in pairs(line_call_ids) do
    local count = 0
    for _ in pairs(call_ids) do
      count = count + 1
    end
    if count > 1 then
      for call_id in pairs(call_ids) do
        positions[call_id] = nil
        ambiguous = ambiguous + 1
      end
    end
  end

  for call_id, reference in pairs(references_by_call_id) do
    if not positions[call_id] then
      unresolved[#unresolved + 1] = reference
    end
  end

  return positions, { unresolved = unresolved, ambiguous = ambiguous }
end

return M
