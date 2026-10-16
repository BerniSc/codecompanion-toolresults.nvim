local M = {}

---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@return nil
local function close(chat_state)
  local preview = chat_state.hover_preview
  -- No active preview is already the closed state; treat this as a no-op.
  if not preview then
    return
  end

  chat_state.hover_preview = nil
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

---Show a small, scrollable preview beside the hovered tool label.
---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@param lines string[] Rendered result lines.
---@param mouse table Mouse position from getmousepos().
---@param opts table Hover options.
---@param tool_name string Tool name shown in the float border.
---@param keybind string|false|nil Key used to open the full managed result float; false or nil disables it.
---@param on_view_more fun() Callback to open the full managed result float.
function M.show(chat_state, lines, mouse, opts, tool_name, keybind, on_view_more)
  close(chat_state)

  local preview_lines = lines
  local mouse_screen_col = mouse.screencol
  local space_right = math.max(0, vim.o.columns - mouse_screen_col - 2)
  local space_left = math.max(0, mouse_screen_col - 2)
  local place_left = space_left > space_right
  local available_width = place_left and space_left or space_right
  local preview_width = math.max(1, math.min(opts.max_width, available_width))
  local preview_col = place_left and math.max(0, mouse_screen_col - preview_width - 2) or mouse_screen_col

  -- Keep the preview title and footer hints within their available display-cell width.
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

  local title = truncate(tostring(tool_name or "Tool result"), math.max(1, preview_width - 2))

  local footer_hints = {}
  if keybind then
    footer_hints[#footer_hints + 1] = keybind .. ": open"
  end
  if #lines > opts.max_lines then
    footer_hints[#footer_hints + 1] = "↓ scroll for more"
  end
  local footer_height = #footer_hints > 0 and 1 or 0

  -- Keep preview within configured line limit, available result lines, and screen height.
  local height = math.min(opts.max_lines, #preview_lines + footer_height, math.max(1, vim.o.lines - 3))
  -- Start at the pointer row, moving upwards as needed to keep the float on screen.
  local row = math.min(mouse.screenrow, math.max(0, vim.o.lines - height - 3))
  -- Keep the preview within the right edge, accounting for its border columns.
  local screen_col = math.min(preview_col, math.max(0, vim.o.columns - preview_width - 2))
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_lines)
  -- Keep preview buffer temporary and wipe it when its window closes.
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].modifiable = false

  -- Position like mouse-position relative to editor-grid (screen coordinates).
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
    focusable = true,
    zindex = 50,
  })
  if not ok then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return
  end

  -- Preview contents are rendered Markdown. Use the standard Markdown filetype so
  -- Markdown renderers and Tree-sitter resolve the correct parser directly.
  -- Set it after opening the window so FileType handlers see a valid preview window.
  vim.bo[bufnr].filetype = "markdown"
  vim.wo[winnr].wrap = true
  vim.wo[winnr].scrolloff = 0

  local footer_bufnr, footer_winnr

  if #footer_hints > 0 then
    local footer_width = math.max(1, preview_width)
    local footer = table.concat(footer_hints, "    ")
    footer = truncate(footer, footer_width)
    -- Right-align hints in the footer by padding to its display-cell width.
    footer = string.rep(" ", math.max(0, footer_width - vim.fn.strdisplaywidth(footer))) .. footer
    footer_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(footer_bufnr, 0, -1, false, { footer })
    -- Keep preview buffer temporary and wipe it when its window closes.
    vim.bo[footer_bufnr].buftype = "nofile"
    vim.bo[footer_bufnr].bufhidden = "wipe"
    vim.bo[footer_bufnr].modifiable = false

    local footer_ok
    footer_ok, footer_winnr = pcall(vim.api.nvim_open_win, footer_bufnr, false, {
      relative = "editor",
      row = row + height,
      col = screen_col + 1,
      width = footer_width,
      height = 1,
      style = "minimal",
      focusable = false,
      zindex = 51,
    })
    if not footer_ok then
      vim.api.nvim_buf_delete(footer_bufnr, { force = true })
      footer_bufnr = nil
      footer_winnr = nil
    else
      -- Match footer colours to the preview title rim.
      vim.wo[footer_winnr].winhighlight = "Normal:FloatTitle,NormalNC:FloatTitle"
      vim.wo[footer_winnr].wrap = false
    end
  end

  if keybind then
    vim.keymap.set("n", keybind, on_view_more, { buffer = bufnr, silent = true, desc = "Open full tool result" })
  end
  chat_state.hover_preview = {
    bufnr = bufnr,
    winnr = winnr,
    footer_bufnr = footer_bufnr,
    footer_winnr = footer_winnr,
  }
end

---Close the active hover preview, if one exists.
---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@return nil
function M.close(chat_state)
  close(chat_state)
end

---Close the transient preview before scheduling its full-result window.
---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@param call_id string Stable tool call identifier.
---@param on_view_more fun(call_id: string) Open the managed result float for this call.
---@return nil
function M.open_full_result(chat_state, call_id, on_view_more)
  close(chat_state)
  chat_state.hovered_call_id = nil
  vim.schedule(function()
    on_view_more(call_id)
  end)
end

---Attach per-chat mouse preview handling and return its cleanup function.
---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@param bufnr integer Chat buffer number.
---@param opts table Hover options.
---@param on_preview fun(mouse: table) Preview callback.
---@return fun() stop Stop timer, remove mappings and autocmds, and close preview.
function M.attach(chat_state, bufnr, opts, on_preview)
  -- Group hover autocmds per chat buffer and clear stale handlers before attaching new ones.
  local group = vim.api.nvim_create_augroup("CodeCompanionToolresultsHover" .. bufnr, { clear = true })
  local stopped = false

  local function stop()
    if chat_state.hover_timer then
      chat_state.hover_timer:stop()
      chat_state.hover_timer:close()
      chat_state.hover_timer = nil
    end
    chat_state.hover_mouse = nil
    chat_state.hovered_call_id = nil
    close(chat_state)
  end

  -- Preview uses a separate buffer, so allow its window; stop on other buffers/windows.
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      local preview = chat_state.hover_preview
      if vim.api.nvim_get_current_buf() ~= bufnr and (not preview or vim.api.nvim_get_current_win() ~= preview.winnr) then
        stop()
      end
    end,
  })

  -- InsertEnter may run before mode() reflects Insert mode, so close unconditionally on the event.
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = stop,
  })

  ---Recheck the hover target after pointer movement or scrolling.
  ---@param from_scroll boolean Whether this check was triggered by window scrolling.
  local function update_hover_target(from_scroll)
    -- Defensively ignore events already queued when hover handling was detached.
    if stopped then
      return
    end
    if not from_scroll and vim.api.nvim_get_current_buf() ~= bufnr then
      stop()
      return
    end

    local mouse = vim.fn.getmousepos()
    -- Moving onto either preview window (content or footer) should not replace or dismiss that preview.
    if chat_state.hover_preview and (mouse.winid == chat_state.hover_preview.winnr
        or mouse.winid == chat_state.hover_preview.footer_winnr) then
      return
    end
    -- Stop if poiner is not over valid line in buffer.
    if mouse.winid == 0 or not vim.api.nvim_win_is_valid(mouse.winid)
      or vim.api.nvim_win_get_buf(mouse.winid) ~= bufnr or mouse.line < 1 then
      stop()
      return
    end

    local previous = chat_state.hover_mouse
    -- Scrolling may trigger this again without changing the buffer line under the pointer.
    if previous and previous.line == mouse.line and previous.winid == mouse.winid then
      return
    end

    if chat_state.hover_timer then
      chat_state.hover_timer:stop()
      chat_state.hover_timer:close()
    end
    chat_state.hovered_call_id = nil
    close(chat_state)
    chat_state.hover_mouse = { line = mouse.line, winid = mouse.winid }
    -- Debounce movement so previews appear only after the pointer settles.
    local timer = vim.uv.new_timer()
    chat_state.hover_timer = timer
    if not timer then
      chat_state.hover_timer = nil
      return
    end
    timer:start(opts.delay, 0, vim.schedule_wrap(function()
      if stopped or chat_state.hover_timer ~= timer then
        return
      end
      timer:stop()
      timer:close()
      chat_state.hover_timer = nil

      -- Recheck pointer and editor state; the target may have changed during the delay.
      local current_mouse = vim.fn.getmousepos()
      if current_mouse.winid == mouse.winid and current_mouse.line == mouse.line
        and vim.api.nvim_win_is_valid(current_mouse.winid)
        and vim.api.nvim_win_get_buf(current_mouse.winid) == bufnr
        and vim.api.nvim_get_current_buf() == bufnr
        and not vim.fn.mode(1):find("i") then
        on_preview(current_mouse)
      end
    end))
  end

  vim.keymap.set("n", "<MouseMove>", update_hover_target, {
    buffer = bufnr,
    silent = true,
    desc = "Preview CodeCompanion tool result on hover",
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      update_hover_target(true)
    end,
  })

  return function()
    if stopped then
      return
    end
    stopped = true
    stop()
    pcall(vim.api.nvim_del_augroup_by_id, group)
    pcall(vim.keymap.del, "n", "<MouseMove>", { buffer = bufnr })
  end
end

return M
