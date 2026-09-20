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

---Update an existing managed result buffer and window.
---@param bufnr integer Buffer number.
---@param winnr integer Window number.
---@param lines string[] Lines to render.
---@param opts? table Window options to update.
---@return boolean updated Whether both handles remained valid.
function M.update_float(bufnr, winnr, lines, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_win_is_valid(winnr) then
    return false
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  if opts and opts.title then
    vim.api.nvim_win_set_config(winnr, { title = " " .. opts.title .. " ", title_pos = "center" })
  end

  vim.api.nvim_set_current_win(winnr)
  return true
end

---Close a managed result floating window and its scratch buffer.
---@param bufnr integer? Buffer number.
---@param winnr integer? Window number.
function M.close_float(bufnr, winnr)
  if winnr and vim.api.nvim_win_is_valid(winnr) then
    vim.api.nvim_win_close(winnr, true)
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

return M
