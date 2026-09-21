local M = {}

local navigation = require("codecompanion_toolresults.navigation")
local renderers = require("codecompanion_toolresults.renderers")

---@param opts table Extension options.
---@return string? winbar Formatted winbar, or nil when disabled.
local function build_winbar(opts)
  if not opts.float.show_keymaps then
    return nil
  end

  local mappings = {}
  local function add(key, label)
    if key then
      mappings[#mappings + 1] = string.format("%s %s", key, label)
    end
  end

  add(opts.keymaps.float.next, "Next")
  add(opts.keymaps.float.previous, "Previous")
  add(opts.keymaps.float.return_to_chat, "Return")
  add(opts.keymaps.float.close, "Close")
  add(opts.keymaps.float.escape, "Close")

  -- Center the result, make sure to escape keymaps containing % signs.
  local text = table.concat(mappings, "   ")
  return "%=" .. text:gsub("%%", "%%%%") .. "%="
end

---@param reference table Tool reference.
---@param lines string[] Rendered result lines.
---@param opts table Extension options.
---@return boolean
local function should_position_cursor(reference, lines, opts)
  return reference.name == "run_command" and reference.command ~= nil
    and opts.run_command_language ~= nil and opts.run_command_language ~= false
    and #lines > 0
end

---@param winnr integer Float window number.
---@param reference table Tool reference.
---@param lines string[] Rendered result lines.
---@param opts table Extension options.
local function position_cursor(winnr, reference, lines, opts)
  if not should_position_cursor(reference, lines, opts) then
    return
  end

  -- Avoid placing cursor in fence, this feels annoying in render-markdown as it disables hiding the fences.
  vim.api.nvim_win_set_cursor(winnr, { math.min(2, #lines), 0 })
end

---@param result table Current tool result.
---@param index integer Reference index.
---@param reference_count integer Number of ordered references.
---@return string
local function build_title(result, index, reference_count)
  return string.format("Tool Result: %s [%d/%d]", result.name or "unknown", index, reference_count)
end

---@param chat_state table Per-chat extension state.
---@param reference table Tool reference.
---@param index integer Reference index.
---@param lines string[] Rendered result lines.
---@param title string Float title.
---@param opts table Extension options.
---@param ui table UI adapter.
---@return boolean updated Whether an existing float was updated.
local function update_float(chat_state, reference, index, lines, title, opts, ui)
  local float = chat_state.float
  -- Return false when no managed float exists or its window/buffer was manually closed. The caller then closes stale
  -- state and recreates the managed float.
  local winbar = build_winbar(opts)
  if not float or not ui.update_float(float.bufnr, float.winnr, lines, { title = title, winbar = winbar }) then
    return false
  end

  float.index = index
  float.call_id = reference.call_id
  position_cursor(float.winnr, reference, lines, opts)
  return true
end

---Return from the managed result float to its originating chat tool line.
---@param chat_state table Per-chat extension state.
---@param call_id string Tool call identifier.
---@param reconcile fun(chat_state: table) Reconcile current chat messages.
---@param close fun() Close this managed float.
local function return_to_chat(chat_state, call_id, reconcile, close)
  reconcile(chat_state)

  local reference = chat_state.tools[call_id]
  if not reference or not reference.line then
    close()
    vim.notify("Tool call location unavailable", vim.log.levels.WARN)
    return
  end

  local chat_window
  for _, candidate in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(candidate) == chat_state.bufnr then
      chat_window = candidate
      break
    end
  end

  close()
  if not chat_window then
    vim.notify("CodeCompanion chat window unavailable", vim.log.levels.WARN)
    return
  end

  vim.api.nvim_set_current_win(chat_window)
  vim.api.nvim_win_set_cursor(chat_window, { reference.line, 0 })
end

---@param chat_state table Per-chat extension state.
---@param reference table Tool reference.
---@param index integer Reference index.
---@param lines string[] Rendered result lines.
---@param title string Float title.
---@param opts table Extension options.
---@param ui table UI adapter.
---@param adapter table Message adapter.
---@param reconcile fun(chat_state: table) Reconcile current chat messages.
---@param renderer_context table Renderer dependencies.
local function create_float(chat_state, reference, index, lines, title, opts, ui, adapter, reconcile, renderer_context)
  if chat_state.float then
    ui.close_float(chat_state.float.bufnr, chat_state.float.winnr)
  end

  local bufnr, winnr = ui.create_float(lines, { title = title, winbar = build_winbar(opts) })
  local float = { bufnr = bufnr, winnr = winnr, index = index, call_id = reference.call_id }
  chat_state.float = float

  local function close()
    if chat_state.float == float then
      chat_state.float = nil
    end
    ui.close_float(bufnr, winnr)
  end

  local function move(direction)
    if chat_state.float ~= float then
      return
    end

    reconcile(chat_state)
    local next_index = navigation.next_index(chat_state.references, float.index, direction)
    if next_index then
      -- Keep the injected dependencies explicit for testability. If this list grows,
      -- group them into a display context rather than hiding them in global state.
      M.show(chat_state, chat_state.references[next_index], next_index, opts, adapter, ui, reconcile, renderer_context)
    end
  end

  local mappings = {
    { "n", opts.keymaps.float.next, function() move(1) end, "Next tool result" },
    { "n", opts.keymaps.float.previous, function() move(-1) end, "Previous tool result" },
    { "n", opts.keymaps.float.close, close, "Close tool result" },
    { "n", opts.keymaps.float.escape, close, "Close tool result" },
    { "n", opts.keymaps.float.return_to_chat, function() return_to_chat(chat_state, float.call_id, reconcile, close) end, "Return to tool call" },
  }
  for _, mapping in ipairs(mappings) do
    if mapping[2] then
      vim.keymap.set(mapping[1], mapping[2], mapping[3], { buffer = bufnr, silent = true, desc = mapping[4] })
    end
  end

  position_cursor(winnr, reference, lines, opts)
end

---Display one tool result, reusing the chat's managed float when possible.
---
---The explicit dependencies keep CodeCompanion integration at the call boundary
---and make this module straightforward to test without global plugin state.
---@param chat_state table Per-chat extension state.
---@param reference table Tool reference.
---@param index integer Reference index.
---@param opts table Extension options.
---@param adapter table Message adapter.
---@param ui table UI adapter.
---@param reconcile fun(chat_state: table) Reconcile current chat messages.
---@param renderer_context table Renderer dependencies.
---@return boolean displayed Whether the result was displayed.
function M.show(chat_state, reference, index, opts, adapter, ui, reconcile, renderer_context)
  local result = adapter.find_tool_result(chat_state.messages, reference.call_id)
  if not result then
    vim.notify(string.format("Tool result unavailable: %s (%s)", reference.name or "?", tostring(reference.call_id or "?")), vim.log.levels.WARN)
    return false
  end

  local lines = renderers.render(reference, result, opts, renderer_context)
  local title = build_title(result, index, #chat_state.references)

  if update_float(chat_state, reference, index, lines, title, opts, ui) then
    return true
  end

  create_float(chat_state, reference, index, lines, title, opts, ui, adapter, reconcile, renderer_context)
  return true
end

-- Test seam for the pure formatter; float lifecycle remains private.
M._build_winbar = build_winbar

return M
