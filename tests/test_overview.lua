local MiniTest = require("mini.test")
local overview = require("codecompanion_toolresults.overview")
local adapter_ui = require("codecompanion_toolresults.adapters.ui")

local T = MiniTest.new_set()

local items = {
  { call_id = "call-1", index = 1, name = "grep_search", outcome = "completed", summary = "needle" },
  { call_id = "call-2", index = 2, name = "read_file", outcome = "failed", summary = "a.lua" },
  { call_id = "call-3", index = 3, name = "grep_search", outcome = "cancelled", summary = "other" },
  { call_id = "call-4", index = 4, name = "run_command", outcome = "completed", summary = "date" },
}

-- Real float windows without CodeCompanion. Update and close reuse the adapter's own helpers.
local test_ui = vim.tbl_extend("force", adapter_ui, {
  create_float = function(lines, opts)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    local winnr = vim.api.nvim_open_win(bufnr, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 70,
      height = 16,
      style = "minimal",
      border = "rounded",
      title = " " .. (opts.title or "Tool Overview") .. " ",
    })
    vim.bo[bufnr].filetype = opts.ft or "codecompanion-toolresults-overview"
    return bufnr, winnr
  end,
})

local function keymaps()
  return {
    inspect = "<CR>",
    preview = "K",
    group = "<M-g>",
    return_to_chat = "gT",
    close = "q",
    escape = "<Esc>",
  }
end

local function make_context(overrides)
  local calls = { inspect = {}, preview = {}, return_to_chat = {}, close_preview = 0 }
  local context = vim.tbl_extend("force", {
    items = items,
    state = {},
    ui = test_ui,
    keymaps = keymaps(),
    filetype = "codecompanion-toolresults-overview",
    group_picker = function() end,
    callbacks = {
      inspect = function(call_id) table.insert(calls.inspect, call_id) end,
      preview = function(call_id, anchor) table.insert(calls.preview, { call_id = call_id, anchor = anchor }) end,
      close_preview = function() calls.close_preview = calls.close_preview + 1 end,
      return_to_chat = function(call_id) table.insert(calls.return_to_chat, call_id) end,
    },
  }, overrides or {})
  return context, calls
end

-- Invoke a buffer-local normal-mode mapping registered by the overview.
local function press(bufnr, lhs)
  vim.api.nvim_buf_call(bufnr, function()
    local map = vim.fn.maparg(lhs, "n", false, true)
    assert(map and map.callback, "no buffer mapping for " .. lhs)
    map.callback()
  end)
end

local function has_mapping(bufnr, lhs)
  local found = false
  vim.api.nvim_buf_call(bufnr, function()
    local map = vim.fn.maparg(lhs, "n", false, true)
    found = map ~= nil and next(map) ~= nil
  end)
  return found
end

local function cursor_call_id(handle)
  local line = vim.api.nvim_win_get_cursor(handle.winnr)[1]
  return handle.layout.call_ids[line]
end

local function buffer_lines(handle)
  return vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false)
end

T["open"] = MiniTest.new_set()

T["open"]["renders chronological rows with a title and selects the first call"] = function()
  local context = make_context()
  local handle = overview.open(context)
  local lines = buffer_lines(handle)
  MiniTest.expect.equality(lines[1], "  Tool calls")
  MiniTest.expect.equality(lines[2]:find("grep_search", 1, true) ~= nil, true)
  MiniTest.expect.equality(cursor_call_id(handle), "call-1")
  MiniTest.expect.equality(vim.api.nvim_win_get_config(handle.winnr).title[1][1], " Tool Overview [4] · No grouping ")
  overview.close(handle)
end

T["open"]["shows a message for an empty chat"] = function()
  local handle = overview.open(make_context({ items = {} }))
  MiniTest.expect.equality(buffer_lines(handle), { "No tool calls in current chat." })
  overview.close(handle)
end

T["open"]["restores the previously selected call when still present"] = function()
  local context = make_context({ state = { selected_call_id = "call-3" } })
  local handle = overview.open(context)
  MiniTest.expect.equality(cursor_call_id(handle), "call-3")
  overview.close(handle)
end

T["open"]["falls back to the first call when the remembered call is gone"] = function()
  local context = make_context({ state = { selected_call_id = "call-removed" } })
  local handle = overview.open(context)
  MiniTest.expect.equality(cursor_call_id(handle), "call-1")
  overview.close(handle)
end

T["open"]["skips mappings that are disabled with false"] = function()
  local context = make_context({ keymaps = vim.tbl_extend("force", keymaps(), { inspect = false, preview = false }) })
  local handle = overview.open(context)
  MiniTest.expect.equality(has_mapping(handle.bufnr, "<CR>"), false)
  MiniTest.expect.equality(has_mapping(handle.bufnr, "K"), false)
  MiniTest.expect.equality(has_mapping(handle.bufnr, "q"), true)
  overview.close(handle)
end

T["actions"] = MiniTest.new_set()

T["actions"]["inspect opens the selected call and closes the overview"] = function()
  local context, calls = make_context({ state = { selected_call_id = "call-2" } })
  local handle = overview.open(context)
  press(handle.bufnr, "<CR>")
  MiniTest.expect.equality(calls.inspect, { "call-2" })
  MiniTest.expect.equality(handle.closed, true)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(handle.winnr), false)
end

T["actions"]["preview passes the selected call and an anchor without closing"] = function()
  local context, calls = make_context({ state = { selected_call_id = "call-4" } })
  local handle = overview.open(context)
  press(handle.bufnr, "K")
  MiniTest.expect.equality(calls.preview[1].call_id, "call-4")
  MiniTest.expect.equality(type(calls.preview[1].anchor.screenrow), "number")
  MiniTest.expect.equality(type(calls.preview[1].anchor.screencol), "number")
  MiniTest.expect.equality(handle.closed, nil)
  overview.close(handle)
end

T["actions"]["return to chat passes the selected call and closes"] = function()
  local context, calls = make_context({ state = { selected_call_id = "call-3" } })
  local handle = overview.open(context)
  press(handle.bufnr, "gT")
  MiniTest.expect.equality(calls.return_to_chat, { "call-3" })
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(handle.winnr), false)
end

T["actions"]["close and escape close and remember the selection"] = function()
  local context, calls = make_context()
  local handle = overview.open(context)
  vim.api.nvim_win_set_cursor(handle.winnr, { 3, 0 })
  press(handle.bufnr, "q")
  MiniTest.expect.equality(context.state.selected_call_id, "call-2")
  MiniTest.expect.equality(calls.close_preview, 1)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(handle.winnr), false)

  local reopened = overview.open(context)
  MiniTest.expect.equality(cursor_call_id(reopened), "call-2")
  overview.close(reopened)
end

T["actions"]["close is safe to call more than once"] = function()
  local handle = overview.open(make_context())
  overview.close(handle)
  overview.close(handle)
  overview.close(nil)
  MiniTest.expect.equality(handle.closed, true)
end

T["grouping"] = MiniTest.new_set()

T["grouping"]["outcome grouping adds headers and keeps selection"] = function()
  local context = make_context({
    state = { selected_call_id = "call-3" },
    group_picker = function(choices, on_choice)
      MiniTest.expect.equality(#choices, 3)
      on_choice("outcome")
    end,
  })
  local handle = overview.open(context)
  press(handle.bufnr, "<M-g>")
  local lines = buffer_lines(handle)
  MiniTest.expect.equality(lines[2], "▼ Completed · 2 calls")
  MiniTest.expect.equality(context.state.grouping, "outcome")
  MiniTest.expect.equality(cursor_call_id(handle), "call-3")
  MiniTest.expect.equality(vim.api.nvim_win_get_config(handle.winnr).title[1][1]:find("Outcome", 1, true) ~= nil, true)
  overview.close(handle)
end

T["grouping"]["cancelled picker leaves grouping unchanged"] = function()
  local context = make_context({
    group_picker = function(_, on_choice) on_choice(nil) end,
  })
  local handle = overview.open(context)
  local before = buffer_lines(handle)
  press(handle.bufnr, "<M-g>")
  MiniTest.expect.equality(buffer_lines(handle), before)
  MiniTest.expect.equality(context.state.grouping, "none")
  overview.close(handle)
end

T["grouping"]["tool grouping uses first-appearance headers"] = function()
  local context = make_context({
    group_picker = function(_, on_choice) on_choice("tool") end,
  })
  local handle = overview.open(context)
  press(handle.bufnr, "<M-g>")
  local headers = {}
  for _, line in ipairs(buffer_lines(handle)) do
    if vim.startswith(line, "▼ ") then
      headers[#headers + 1] = line
    end
  end
  MiniTest.expect.equality(headers, { "▼ grep_search · 2 calls", "▼ read_file · 1 call", "▼ run_command · 1 call" })
  overview.close(handle)
end

T["grouping"]["unknown grouping from picker is ignored"] = function()
  local context = make_context({
    group_picker = function(_, on_choice) on_choice("agent_turn") end,
  })
  local handle = overview.open(context)
  press(handle.bufnr, "<M-g>")
  MiniTest.expect.equality(context.state.grouping, "none")
  overview.close(handle)
end

T["grouping"]["folds are restored for the same grouping after reopening"] = function()
  local context = make_context({
    state = { grouping = "outcome" },
  })
  local handle = overview.open(context)
  -- Collapse the first group by moving to its header and closing its fold.
  vim.api.nvim_win_call(handle.winnr, function()
    vim.api.nvim_win_set_cursor(handle.winnr, { 2, 0 })
    vim.cmd("silent! normal! zc")
  end)
  overview.close(handle)
  MiniTest.expect.equality(context.state.collapsed["outcome:completed"], true)

  local reopened = overview.open(context)
  local folded = vim.api.nvim_win_call(reopened.winnr, function() return vim.fn.foldclosed(2) end)
  MiniTest.expect.equality(folded, 2)
  overview.close(reopened)
end

T["grouping"]["flat grouping disables folds"] = function()
  local handle = overview.open(make_context())
  MiniTest.expect.equality(vim.wo[handle.winnr].foldenable, false)
  overview.close(handle)
end

return T
