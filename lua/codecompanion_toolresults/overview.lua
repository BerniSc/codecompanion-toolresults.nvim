---Managed tool overview window.
---
---This module owns the overview float, row selection, grouping folds, and overview-local mappings. It does not
---read CodeCompanion messages: callers pass plain items with outcomes and summaries already resolved, and
---handle inspection, preview, and return-to-chat through callbacks. Overview state stores only the selected
---call ID, the grouping, and collapsed groups.
local M = {}

local model = require("codecompanion_toolresults.overview_model")

local namespace = vim.api.nvim_create_namespace("CodeCompanionToolresultsOverview")

for name, link in pairs({
  Header = "FloatTitle",
  ----
  Group = "Title",
  ----
  Completed = "DiagnosticOk",
  Failed = "DiagnosticError",
  Rejected = "DiagnosticWarn",
  Cancelled = "Comment",
  Unavailable = "Comment",
  ----
  Tool = "Function",
}) do
  vim.api.nvim_set_hl(0, "CodeCompanionToolresultsOverview" .. name, { default = true, link = link })
end

local outcome_highlights = {
  completed = "CodeCompanionToolresultsOverviewCompleted",
  failed = "CodeCompanionToolresultsOverviewFailed",
  rejected = "CodeCompanionToolresultsOverviewRejected",
  cancelled = "CodeCompanionToolresultsOverviewCancelled",
  unavailable = "CodeCompanionToolresultsOverviewUnavailable",
}

-- Glyph columns are fixed by `overview_model.format_row`: " NN  <glyph>  <name>".
local glyph_start = 5

---Default picker: native "vim.ui.select" for grouping choices.
---@type CodeCompanionToolresults.GroupPicker
local function default_picker(choices, on_choice)
  vim.ui.select(choices, {
    prompt = "Group tool overview by",
    format_item = function(choice)
      return choice.label
    end,
  }, function(choice)
    on_choice(choice and choice.grouping or nil)
  end)
end

---@param grouping CodeCompanionToolresults.OverviewGrouping?
---@return CodeCompanionToolresults.OverviewGrouping
local function valid_grouping(grouping)
  if grouping and vim.tbl_contains(model.groupings, grouping) then
    return grouping
  end
  return "none"
end

---Build lines, call-ID and row lookups, and group headers for one grouping.
---@param items CodeCompanionToolresults.OverviewItem[]
---@param grouping CodeCompanionToolresults.OverviewGrouping
---@return CodeCompanionToolresults.OverviewLayout layout
local function build_layout(items, grouping)
  local layout = { lines = { "  Tool calls" }, call_ids = {}, rows = {}, headers = {} }
  if #items == 0 then
    layout.lines = { "No tool calls in current chat." }
    return layout
  end

  for _, group in ipairs(model.group(items, grouping) or {}) do
    if group.label then
      layout.lines[#layout.lines + 1] = string.format("▼ %s · %d call%s", group.label, #group.items,
        #group.items == 1 and "" or "s")
      layout.headers[#layout.headers + 1] = { line = #layout.lines, key = group.key }
    end
    for _, item in ipairs(group.items) do
      layout.lines[#layout.lines + 1] = model.format_row(item)
      local line = #layout.lines
      layout.call_ids[line] = item.call_id
      layout.rows[line] = { outcome = item.outcome, name = item.name or "unknown" }
    end
  end
  return layout
end

---@param grouping CodeCompanionToolresults.OverviewGrouping
---@param count integer
---@return string
local function title(grouping, count)
  return string.format("Tool Overview [%d] · %s", count, model.grouping_labels[grouping])
end

---@param handle CodeCompanionToolresults.OverviewHandle
---@return boolean
local function is_open(handle)
  return handle ~= nil and not handle.closed and vim.api.nvim_win_is_valid(handle.winnr)
end

---Record which group folds are closed so they can be restored for the same grouping.
---@param handle CodeCompanionToolresults.OverviewHandle
local function remember_collapsed(handle)
  if not is_open(handle) or #handle.layout.headers == 0 then
    return
  end

  local state = handle.context.state
  state.collapsed = state.collapsed or {}
  vim.api.nvim_win_call(handle.winnr, function()
    for _, header in ipairs(handle.layout.headers) do
      local key = handle.grouping .. ":" .. header.key
      state.collapsed[key] = vim.fn.foldclosed(header.line) ~= -1 or nil
    end
  end)
end

---Create one manual fold per group and restore collapsed groups.
---@param handle CodeCompanionToolresults.OverviewHandle
local function apply_folds(handle)
  local winnr = handle.winnr
  local layout = handle.layout
  vim.wo[winnr].foldmethod = "manual"
  vim.wo[winnr].foldenable = #layout.headers > 0
  vim.wo[winnr].foldlevel = 99
  if #layout.headers == 0 then
    return
  end

  local collapsed = handle.context.state.collapsed or {}
  vim.api.nvim_win_call(winnr, function()
    vim.cmd("silent! normal! zE")
    for index, header in ipairs(layout.headers) do
      local next_header = layout.headers[index + 1]
      local last = next_header and (next_header.line - 1) or #layout.lines
      vim.cmd(string.format("%d,%dfold", header.line, last))
    end
    vim.cmd("silent! normal! zR")
    for _, header in ipairs(layout.headers) do
      if collapsed[handle.grouping .. ":" .. header.key] then
        vim.api.nvim_win_set_cursor(winnr, { header.line, 0 })
        vim.cmd("silent! normal! zc")
      end
    end
  end)
end

---Highlight header rows and outcome glyph and tool name columns.
---@param handle CodeCompanionToolresults.OverviewHandle
local function highlight(handle)
  local bufnr = handle.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  local layout = handle.layout
  -- Extmarks replace the deprecated nvim_buf_add_highlight. Columns are 0-based byte offsets, end-exclusive.
  local header_text = layout.lines[1]
  vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, 0, {
    end_col = #header_text,
    hl_group = "CodeCompanionToolresultsOverviewHeader",
    hl_eol = true, -- Extend the highlight to the window edge.
  })
  for _, header in ipairs(layout.headers) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace, header.line - 1, 0, {
      end_col = #layout.lines[header.line],
      hl_group = "CodeCompanionToolresultsOverviewGroup",
      hl_eol = true,
    })
  end
  for line, row in pairs(layout.rows) do
    -- Glyph positions are byte offsets, so glyph_bytes covers multibyte glyphs such as "✓".
    local glyph = vim.fn.strcharpart(layout.lines[line], glyph_start, 1)
    local glyph_bytes = #glyph
    vim.api.nvim_buf_set_extmark(bufnr, namespace, line - 1, glyph_start, {
      end_col = glyph_start + glyph_bytes,
      hl_group = outcome_highlights[row.outcome] or "Comment",
    })
    local name_start = glyph_start + glyph_bytes + 2
    vim.api.nvim_buf_set_extmark(bufnr, namespace, line - 1, name_start, {
      end_col = name_start + #row.name,
      hl_group = "CodeCompanionToolresultsOverviewTool",
    })
  end
end

---Move the cursor to a call ID, or the first call row when it is absent.
---@param handle CodeCompanionToolresults.OverviewHandle
---@param call_id? string
local function select_call(handle, call_id)
  local layout = handle.layout
  local first_call_line
  for line = 1, #layout.lines do
    if layout.call_ids[line] then
      first_call_line = first_call_line or line
      if layout.call_ids[line] == call_id then
        vim.api.nvim_win_set_cursor(handle.winnr, { line, 0 })
        return
      end
    end
  end
  if first_call_line then
    vim.api.nvim_win_set_cursor(handle.winnr, { first_call_line, 0 })
  end
end

---@param handle CodeCompanionToolresults.OverviewHandle
---@return string? call_id
local function selected_call_id(handle)
  if not is_open(handle) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(handle.winnr)[1]
  return handle.layout.call_ids[line]
end

---Anchor for a transient preview beside the selected row, in editor-grid coordinates.
---@param handle CodeCompanionToolresults.OverviewHandle
---@return CodeCompanionToolresults.Anchor
local function preview_anchor(handle)
  local line = vim.api.nvim_win_get_cursor(handle.winnr)[1]
  local screenpos = vim.fn.screenpos(handle.winnr, line, 1)
  local position = vim.api.nvim_win_get_position(handle.winnr)
  local width = vim.api.nvim_win_get_width(handle.winnr)
  return { screenrow = screenpos.row, screencol = position[2] + math.floor(width / 2) }
end

---Close the overview and remember its selection and folds.
---@param handle? CodeCompanionToolresults.OverviewHandle
local close = function(handle)
  if not handle or handle.closed then
    return
  end

  local state = handle.context.state
  state.selected_call_id = selected_call_id(handle) or state.selected_call_id
  remember_collapsed(handle)
  handle.context.callbacks.close_preview()
  handle.closed = true
  handle.context.ui.close_float(handle.bufnr, handle.winnr)
end

---Rebuild the overview for a grouping while keeping the selected call when possible.
---@param handle CodeCompanionToolresults.OverviewHandle
---@param grouping CodeCompanionToolresults.OverviewGrouping
local function regroup(handle, grouping)
  if not is_open(handle) then
    return
  end

  local selected = selected_call_id(handle)
  remember_collapsed(handle)
  local state = handle.context.state
  state.grouping = grouping
  state.selected_call_id = selected or state.selected_call_id
  handle.grouping = grouping
  handle.layout = build_layout(handle.context.items, grouping)

  handle.context.ui.update_float(handle.bufnr, handle.winnr, handle.layout.lines, {
    title = title(grouping, #handle.context.items),
  })
  apply_folds(handle)
  highlight(handle)
  select_call(handle, state.selected_call_id)
end

---Open the grouping picker and apply the chosen grouping.
---@param handle CodeCompanionToolresults.OverviewHandle
local function choose_grouping(handle)
  local choices = {}
  for _, grouping in ipairs(model.groupings) do
    choices[#choices + 1] = { grouping = grouping, label = model.grouping_labels[grouping] }
  end

  local picker = handle.context.group_picker or default_picker
  picker(choices, function(grouping)
    if grouping and vim.tbl_contains(model.groupings, grouping) and grouping ~= handle.grouping then
      regroup(handle, grouping)
    end
  end)
end

---Install overview-local mappings. Disabled actions ("=false") are skipped.
---@param handle CodeCompanionToolresults.OverviewHandle
local function install_mappings(handle)
  local context = handle.context
  local keymaps = context.keymaps

  local function with_selection(action)
    return function()
      local call_id = selected_call_id(handle)
      if not call_id then
        vim.notify("No tool call selected.", vim.log.levels.INFO)
        return
      end
      action(call_id)
    end
  end

  local actions = {
    { keymaps.inspect, with_selection(function(call_id)
      close(handle)
      context.callbacks.inspect(call_id)
    end), "Inspect selected tool result" },
    { keymaps.preview, with_selection(function(call_id)
      context.callbacks.preview(call_id, preview_anchor(handle))
    end), "Preview selected tool result" },
    { keymaps.group, function() choose_grouping(handle) end, "Select overview grouping" },
    { keymaps.return_to_chat, with_selection(function(call_id)
      close(handle)
      context.callbacks.return_to_chat(call_id)
    end), "Return to tool call" },
    { keymaps.close, function() close(handle) end, "Close tool overview" },
    { keymaps.escape, function() close(handle) end, "Close tool overview" },
  }

  for _, action in ipairs(actions) do
    if action[1] then
      vim.keymap.set("n", action[1], action[2], { buffer = handle.bufnr, silent = true, desc = action[3] })
    end
  end
end

---Open the overview for one chat.
---Returns a handle that callers keep to close or regroup the overview. The handle is not a copy of chat data.
---@param context CodeCompanionToolresults.OverviewContext
---@return CodeCompanionToolresults.OverviewHandle handle
function M.open(context)
  local grouping = valid_grouping(context.state.grouping)
  local layout = build_layout(context.items, grouping)
  local bufnr, winnr = context.ui.create_float(layout.lines, {
    ft = context.filetype,
    title = title(grouping, #context.items),
  })

  local handle = {
    bufnr = bufnr,
    winnr = winnr,
    context = context,
    grouping = grouping,
    layout = layout,
  }
  context.state.grouping = grouping
  apply_folds(handle)
  highlight(handle)
  install_mappings(handle)
  select_call(handle, context.state.selected_call_id)
  return handle
end

---Close an overview handle. Safe to call more than once.
---@param handle CodeCompanionToolresults.OverviewHandle? Handle returned by `open`.
function M.close(handle)
  close(handle)
end

return M
