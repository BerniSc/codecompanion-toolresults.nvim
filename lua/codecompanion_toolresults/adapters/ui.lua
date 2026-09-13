local M = {}

---Copy CodeCompanion's configured chat floating-window options.
---@return table
local function get_parent_window_opts()
  local config = require("codecompanion.config")
  return vim.deepcopy(config.display.chat.floating_window or {})
end

---Open tool result using CodeCompanion's own floating-window helper.
---@param lines string[] Lines to render in the floating buffer.
---@param opts? table Tool-result-specific window overrides.
---@return integer bufnr Created or reused buffer number.
---@return integer winnr Created window number.
function M.create_float(lines, opts)
  local ui = require("codecompanion.utils.ui")
  local window_opts = vim.tbl_deep_extend("force", get_parent_window_opts(), {
    ft = "codecompanion",
    lock = true,
    style = "minimal",
    title = "Tool Result",
  }, opts or {})

  return ui.create_float(lines, window_opts)
end

return M
