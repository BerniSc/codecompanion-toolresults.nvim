local transient_preview = require("codecompanion_toolresults.transient_preview")

local M = {}

---Close the hover preview stored on chat state, if one exists.
---@param chat_state CodeCompanionToolresults.ChatState Per-chat extension state.
---@return nil
local function close(chat_state)
  local preview = chat_state.hover_preview
  -- No active preview is already the closed state; treat this as a no-op.
  if not preview then
    return
  end

  chat_state.hover_preview = nil
  transient_preview.close(preview)
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

  local preview = transient_preview.open(lines, { screenrow = mouse.screenrow, screencol = mouse.screencol }, {
    max_lines = opts.max_lines,
    max_width = opts.max_width,
    title = tool_name,
    keybind = keybind,
    on_view_more = on_view_more,
    focusable = true,
    zindex = 50,
  })
  if preview then
    chat_state.hover_preview = preview
  end
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
    -- Stop if pointer is not over valid line in buffer.
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
