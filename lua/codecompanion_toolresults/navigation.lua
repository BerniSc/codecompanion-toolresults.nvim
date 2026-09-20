local M = {}

---Find the next or previous reference index, with wrapping.
---@param references table[] Ordered tool references.
---@param current_index integer Current reference index.
---@param direction integer 1 for next, -1 for previous.
---@return integer? index Target index, or nil when no references exist.
function M.next_index(references, current_index, direction)
  local count = #references
  if count == 0 then
    return nil
  end

  if direction > 0 then
    return current_index % count + 1
  end

  return (current_index - 2) % count + 1
end

return M
