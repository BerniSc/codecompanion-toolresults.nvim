local M = {}

---Build a Lua pattern matching a rendered tool label.
---@param name string Tool name.
---@return string
local function tool_label_pattern(name)
  return "^" .. vim.pesc(name) .. ":"
end

---OPTIM This is the current bottleneck O(N x R) with N:=numberOfLines and R:=#references, maybe later on optimize to
---for example only rescan diff or something? For now this would add more complexity than it would prevent
---
---Find rendered line positions for tool references.
---@param bufnr integer
---@param references table[] Tool references in rendered message order.
---@return table<string, integer> Map from call ID to 1-based buffer line.
function M.find_tool_lines(bufnr, references)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local positions = {}
  local search_start = 1

  for _, reference in ipairs(references) do
    if reference.call_id and reference.name then
      local pattern = tool_label_pattern(reference.name)

      for line_number = search_start, #lines do
        if lines[line_number]:match(pattern) then
          positions[reference.call_id] = line_number
          search_start = line_number + 1
          break
        end
      end
    end
  end

  return positions
end

---Find the tool reference rendered on a specific line.
---@param references table[] Tool references with current line positions.
---@param line integer 1-based buffer line.
---@return table? Matching tool reference, if any.
function M.find_reference_at_line(references, line)
  for _, reference in pairs(references or {}) do
    if reference.line == line then
      return reference
    end
  end
end

return M
