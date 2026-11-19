---Transient, scrollable preview windows for rendered tool-result lines.
---
---This module owns only window and buffer lifecycle for a preview. It does not track per-chat state, mouse
---position, timers, or CodeCompanion messages. Callers pass the anchor, the lines, and an optional action.
local M = {}

---Truncate text to a display-cell width, ending with an ellipsis when needed.
---@param text string
---@param max_width integer
---@return string
local function truncate(text, max_width)
  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end

  local prefix = ""
  local ellipsis_char = "…"
  for index = 0, vim.fn.strchars(text) - 1 do
    local character = vim.fn.strcharpart(text, index, 1)
    if vim.fn.strdisplaywidth(prefix .. character .. ellipsis_char) > max_width then
      break
    end
    prefix = prefix .. character
  end
  return prefix .. ellipsis_char
end

---Create a temporary, non-modifiable scratch buffer.
---@param lines string[]
---@return integer bufnr
local function scratch_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  -- Keep the buffer temporary and wipe it when its window closes.
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = false
  return bufnr
end

---Close a preview returned by `open`. Safe to call with nil or with already-closed windows.
---@param preview? { winnr: integer, bufnr: integer, footer_winnr: integer?, footer_bufnr: integer? }
---@return nil
function M.close(preview)
  if not preview then
    return
  end

  if preview.footer_winnr and vim.api.nvim_win_is_valid(preview.footer_winnr) then
    vim.api.nvim_win_close(preview.footer_winnr, true)
  end
  if preview.footer_bufnr and vim.api.nvim_buf_is_valid(preview.footer_bufnr) then
    vim.api.nvim_buf_delete(preview.footer_bufnr, { force = true })
  end
  if vim.api.nvim_win_is_valid(preview.winnr) then
    vim.api.nvim_win_close(preview.winnr, true)
  end
  if vim.api.nvim_buf_is_valid(preview.bufnr) then
    vim.api.nvim_buf_delete(preview.bufnr, { force = true })
  end
end

---@class CodeCompanionToolresults.PreviewOptions
---@field max_lines integer Maximum body lines before scrolling.
---@field max_width integer Maximum preview width in columns.
---@field title? string Border title; truncated to fit.
---@field keybind string|false|nil Key that runs `on_view_more`; false or nil disables the key and its hint.
---@field on_view_more? fun() Callback for `keybind`.
---@field focusable? boolean Whether the preview window can receive focus.
---@field zindex? integer Base stacking order; footer uses the next value.

---Open a preview beside an anchor in editor-grid coordinates.
---
---The preview prefers the side with more room, stays inside the screen, and uses a footer for key hints.
---@param lines string[] Body lines.
---@param anchor { screenrow: integer, screencol: integer } Anchor in editor-grid coordinates.
---@param opts CodeCompanionToolresults.PreviewOptions
---@return { bufnr: integer, winnr: integer, footer_bufnr: integer?, footer_winnr: integer? }? preview
function M.open(lines, anchor, opts)
  local anchor_col = anchor.screencol
  local space_right = math.max(0, vim.o.columns - anchor_col - 2)
  local space_left = math.max(0, anchor_col - 2)
  local place_left = space_left > space_right
  local available_width = place_left and space_left or space_right
  local preview_width = math.max(1, math.min(opts.max_width, available_width))
  local preview_col = place_left and math.max(0, anchor_col - preview_width - 2) or anchor_col

  -- Keep the title and footer hints within their available display-cell width.
  local title = truncate(tostring(opts.title or "Tool result"), math.max(1, preview_width - 2))

  local footer_hints = {}
  if opts.keybind then
    footer_hints[#footer_hints + 1] = opts.keybind .. ": open"
  end
  if #lines > opts.max_lines then
    footer_hints[#footer_hints + 1] = "↓ scroll for more"
  end
  local footer_height = #footer_hints > 0 and 1 or 0

  -- Keep preview within the configured line limit, available lines, and screen height.
  local height = math.min(opts.max_lines, #lines + footer_height, math.max(1, vim.o.lines - 3))
  -- Start at the anchor row, moving upwards as needed to keep the float on screen.
  local row = math.min(anchor.screenrow, math.max(0, vim.o.lines - height - 3))
  -- Keep the preview within the right edge, accounting for its border columns.
  local screen_col = math.min(preview_col, math.max(0, vim.o.columns - preview_width - 2))

  local bufnr = scratch_buffer(lines)

  local ok, winnr = pcall(vim.api.nvim_open_win, bufnr, false, {
    relative = "editor",
    row = row,
    col = screen_col,
    width = preview_width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    focusable = opts.focusable == true,
    zindex = opts.zindex or 50,
  })
  if not ok then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end

  -- Preview contents are rendered Markdown. Use the standard Markdown filetype so
  -- Markdown renderers and Tree-sitter resolve the correct parser directly.
  -- Set it after opening the window so FileType handlers see a valid preview window.
  vim.bo[bufnr].filetype = "markdown"
  vim.wo[winnr].wrap = true
  vim.wo[winnr].scrolloff = 0

  local preview = { bufnr = bufnr, winnr = winnr }

  if #footer_hints > 0 then
    local footer_width = math.max(1, preview_width)
    local footer = truncate(table.concat(footer_hints, "    "), footer_width)
    -- Right-align hints in the footer by padding to its display-cell width.
    footer = string.rep(" ", math.max(0, footer_width - vim.fn.strdisplaywidth(footer))) .. footer
    local footer_bufnr = scratch_buffer({ footer })

    local footer_ok, footer_winnr = pcall(vim.api.nvim_open_win, footer_bufnr, false, {
      relative = "editor",
      row = row + height,
      col = screen_col + 1,
      width = footer_width,
      height = 1,
      style = "minimal",
      focusable = false,
      zindex = (opts.zindex or 50) + 1,
    })
    if footer_ok then
      -- Match footer colours to the preview title rim.
      vim.wo[footer_winnr].winhighlight = "Normal:FloatTitle,NormalNC:FloatTitle"
      vim.wo[footer_winnr].wrap = false
      preview.footer_bufnr = footer_bufnr
      preview.footer_winnr = footer_winnr
    else
      vim.api.nvim_buf_delete(footer_bufnr, { force = true })
    end
  end

  if opts.keybind and opts.on_view_more then
    vim.keymap.set("n", opts.keybind, opts.on_view_more, { buffer = bufnr, silent = true, desc = "Open full tool result" })
  end

  return preview
end

return M
