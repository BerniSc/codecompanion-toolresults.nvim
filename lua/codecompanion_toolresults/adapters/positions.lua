local M = {}

local NEW_TOOL_OUTPUT_VERSION = { 20, 1, 0 }
local TOOL_CALL_NAMESPACE = "CodeCompanion-tool_calls"

---Parse a CodeCompanion semantic version into numeric components.
---CodeCompanion's format looks something like "20.0.1".
---@param version any
---@return integer[]? parts
local function parse_version(version)
  if type(version) ~= "string" then
    return nil
  end

  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)")
  if not major then
    return nil
  end

  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

---Return whether a version is at least the new tool-output boundary.
---@param version any
---@return boolean
local function uses_extmark_tool_output(version)
  local parts = parse_version(version)
  if not parts then
    return false
  end

  for index, boundary in ipairs(NEW_TOOL_OUTPUT_VERSION) do
    if parts[index] > boundary then
      return true
    elseif parts[index] < boundary then
      return false
    end
  end

  return true
end

---Read CodeCompanion's public version accessor.
---@return string?
local function codecompanion_version()
  local ok, codecompanion = pcall(require, "codecompanion")
  if not ok or type(codecompanion) ~= "table" or type(codecompanion.version) ~= "function" then
    return nil
  end

  local version_ok, version = pcall(codecompanion.version)
  return version_ok and version or nil
end

---Find rendered tool lines using CodeCompanion's tool-call extmarks.
---No text-based fallback is attempted for the new format.
---@param bufnr integer
---@param references CodeCompanionToolresults.ToolReference[]
---@param chat table CodeCompanion chat instance.
---@return table<string, integer> positions
---@return table diagnostics
local function find_extmark_tool_lines(bufnr, references, chat)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}, { invalid_buffer = true, unresolved = references or {}, ambiguous = 0 }
  end

  local unresolved = {}
  local references_by_call_id = {}
  for _, reference in ipairs(references or {}) do
    if reference.call_id then
      references_by_call_id[reference.call_id] = reference
    else
      unresolved[#unresolved + 1] = reference
    end
  end

  local marks_by_extmark = chat and chat.tool_call_marks
  if type(marks_by_extmark) ~= "table" then
    for _, reference in ipairs(references or {}) do
      unresolved[#unresolved + 1] = reference
    end
    return {}, { unresolved = unresolved, ambiguous = #(references or {}) }
  end

  local namespace = vim.api.nvim_create_namespace(TOOL_CALL_NAMESPACE)
  local ok, extmarks = pcall(vim.api.nvim_buf_get_extmarks, bufnr, namespace, 0, -1, {})
  if not ok then
    for _, reference in ipairs(references or {}) do
      unresolved[#unresolved + 1] = reference
    end
    return {}, { unresolved = unresolved, ambiguous = #(references or {}) }
  end

  local positions = {}
  local lines_to_call_ids = {}
  for _, extmark in ipairs(extmarks) do
    local extmark_id, row = extmark[1], extmark[2]
    local call_id = marks_by_extmark[extmark_id]
    if call_id and references_by_call_id[call_id] then
      local line = row + 1
      -- A call with an approval prompt can have more than one mark. Its summary is written before the prompt, so
      -- the earliest live mark is the tool-call line.
      if not positions[call_id] or line < positions[call_id] then
        positions[call_id] = line
      end
      lines_to_call_ids[line] = lines_to_call_ids[line] or {}
      lines_to_call_ids[line][call_id] = true
    end
  end

  for call_id, reference in pairs(references_by_call_id) do
    if not positions[call_id] then
      unresolved[#unresolved + 1] = reference
    end
  end

  for _, call_ids in pairs(lines_to_call_ids) do
    local count = 0
    for _ in pairs(call_ids) do
      count = count + 1
    end
    if count > 1 then
      for call_id in pairs(call_ids) do
        unresolved[#unresolved + 1] = references_by_call_id[call_id]
        positions[call_id] = nil
      end
    end
  end

  if #unresolved > 0 then
    return {}, { unresolved = unresolved, ambiguous = #(references or {}) }
  end

  return positions, { unresolved = {}, ambiguous = 0 }
end

---Locate tool-result labels using the strategy selected by CodeCompanion's version.
---Before v20.1.0 the chat uses text labels. v20.1.0 and newer use extmarks only.
---@param bufnr integer Chat buffer number.
---@param references CodeCompanionToolresults.ToolReference[]
---@param chat table CodeCompanion chat instance.
---@param version? string Version override for tests.
---@return table<string, integer> positions
---@return table diagnostics
function M.find_tool_lines(bufnr, references, chat, version)
  version = version or codecompanion_version()
  local has_tool_call_marks = type(chat) == "table" and type(chat.tool_call_marks) == "table"
  local parts = parse_version(version)
  if has_tool_call_marks or (parts and uses_extmark_tool_output(version)) then
    return find_extmark_tool_lines(bufnr, references, chat)
  end

  if not parts then
    return {}, { unresolved = references or {}, ambiguous = #(references or {}), unsupported_version = version }
  end

  return require("codecompanion_toolresults.position").find_tool_lines(bufnr, references)
end

-- Test seam for the compatibility boundary and parser.
M._uses_extmark_tool_output = uses_extmark_tool_output
M._parse_version = parse_version

return M
