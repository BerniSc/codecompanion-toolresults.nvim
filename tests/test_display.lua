local MiniTest = require("mini.test")
local display = require("codecompanion_toolresults.display")

local T = MiniTest.new_set()

T["build_winbar"] = MiniTest.new_set()

local defaults = {
  keymaps = {
    float = {
      toggle_view = "K",
      clear_result = "r",
      next = "<Tab>",
      previous = "<S-Tab>",
      return_to_chat = "gT",
      close = "q",
      escape = "<Esc>",
    },
  },
  float = {
    show_keymaps = true,
  },
}

T["build_winbar"]["uses nested keymap options"] = function()
  MiniTest.expect.equality(display._build_winbar(defaults, "result"),
    "%=K Tool call   r Clear result   <Tab> Next   <S-Tab> Previous   gT Return   q Close   <Esc> Close%=")
end

T["build_winbar"]["returns nil when disabled"] = function()
  local opts = vim.deepcopy(defaults)
  opts.float.show_keymaps = false
  MiniTest.expect.equality(display._build_winbar(opts, "result"), nil)
end

T["build_winbar"]["omits disabled mappings"] = function()
  local opts = vim.deepcopy(defaults)
  opts.keymaps.float.next = false
  opts.keymaps.float.escape = false

  MiniTest.expect.equality(display._build_winbar(opts, "result"),
    "%=K Tool call   r Clear result   <S-Tab> Previous   gT Return   q Close%=")
end

T["build_winbar"]["omits clear action in call view"] = function()
  local opts = vim.deepcopy(defaults)
  MiniTest.expect.equality(display._build_winbar(opts, "call"):find("Clear result", 1, true), nil)
end

T["build_winbar"]["shows result action while call view is selected"] = function()
  MiniTest.expect.equality(display._build_winbar(defaults, "call"),
    "%=K Result   <Tab> Next   <S-Tab> Previous   gT Return   q Close   <Esc> Close%=")
end

T["build_winbar"]["escapes percent signs in mappings"] = function()
  local opts = vim.deepcopy(defaults)
  opts.keymaps.float.return_to_chat = "g%T"
  MiniTest.expect.equality(display._build_winbar(opts, "result"),
    "%=K Tool call   r Clear result   <Tab> Next   <S-Tab> Previous   g%%T Return   q Close   <Esc> Close%=")
end

T["build_winbar"]["omits disabled clear mapping"] = function()
  local opts = vim.deepcopy(defaults)
  opts.keymaps.float.clear_result = false
  MiniTest.expect.equality(display._build_winbar(opts, "result"):find("Clear result", 1, true), nil)
end

T["result title estimates"] = MiniTest.new_set()

local function result_display_harness(estimate, call_id)
  local current = {
    call_id = call_id or "call-current",
    name = "grep_search",
    content = "current output",
    estimated_tokens = estimate,
  }
  local state = {
    references = {
      { call_id = "call-old", name = "grep_search" },
      { call_id = current.call_id, name = "grep_search" },
    },
    float = { bufnr = 1, winnr = 1, call_id = current.call_id, view = "result" },
    chat = { messages = { current } },
  }
  -- Capture every title emitted by show(), so repeated displays can verify refreshed metadata.
  local titles = {}
  local adapter = {
    find_result = function(_, requested_call_id)
      MiniTest.expect.equality(requested_call_id, current.call_id)
      return state.chat.messages[1]
    end,
  }
  local ui = {
    update_float = function(_, _, _, opts)
      titles[#titles + 1] = opts.title
      return true
    end,
  }
  local opts = vim.deepcopy(defaults)
  opts.run_command_language = false

  return {
    current = current,
    titles = titles,
    show = function()
      display.show(state, state.references[2], 2, opts, adapter, ui, function() end, {
        normalize_result = function(content) return content end,
      })
    end,
  }
end

T["result title estimates"]["shows the estimate stored on current result message"] = function()
  local harness = result_display_harness(240)
  harness.show()
  MiniTest.expect.equality(harness.titles[1], "Tool Result: grep_search [2/2] (~240 tokens)")
end

T["result title estimates"]["shows unavailable when estimate metadata is missing"] = function()
  local harness = result_display_harness(nil)
  harness.show()
  MiniTest.expect.equality(harness.titles[1], "Tool Result: grep_search [2/2] (estimate unavailable)")
end

T["result title estimates"]["shows updated estimate metadata on redisplay"] = function()
  local harness = result_display_harness(240)
  harness.show()
  harness.current.content = "edited"
  harness.current.estimated_tokens = 12
  harness.show()

  MiniTest.expect.equality(harness.titles, {
    "Tool Result: grep_search [2/2] (~240 tokens)",
    "Tool Result: grep_search [2/2] (~12 tokens)",
  })
end

T["managed float state"] = MiniTest.new_set()

local function with_stubbed_keymaps(callback)
  local original_keymap_set = vim.keymap.set
  rawset(vim.keymap, "set", function() end)
  local ok, err = pcall(callback)
  rawset(vim.keymap, "set", original_keymap_set)
  if not ok then error(err) end
end

local function show_new_float(state, reference, adapter, renderer_context)
  local title
  local opts = vim.deepcopy(defaults)
  opts.run_command_language = false
  with_stubbed_keymaps(function()
    display.show(state, reference, 1, opts, adapter, {
      create_float = function(_, float_opts)
        title = float_opts.title
        return 2, 3
      end,
    }, function() end, renderer_context)
  end)
  return title
end

local function float_state(view, call_id)
  local reference = { call_id = call_id or "call-current", name = "grep_search" }
  return {
    chat = { messages = { { call_id = reference.call_id, name = reference.name, content = "current output" } } },
    references = { reference },
    float = { bufnr = 1, winnr = 1, call_id = reference.call_id, view = view },
  }, reference
end

T["managed float state"]["reopens in last selected view after float closes"] = function()
  local state, reference = float_state("result")
  state.float = nil
  local mappings = {}
  local title
  local adapter = {
    find_call = function() return { call_id = reference.call_id, name = reference.name, arguments = {} } end,
    find_result = function(chat) return chat.messages[1] end,
  }
  local ui = {
    create_float = function(_, opts)
      title = opts.title
      return 2, 3
    end,
    update_float = function(_, _, _, opts)
      title = opts.title
      return true
    end,
    close_float = function() end,
  }
  local opts = vim.deepcopy(defaults)
  opts.run_command_language = false

  local original_keymap_set = vim.keymap.set
  rawset(vim.keymap, "set", function(_, lhs, callback) mappings[lhs] = callback end)
  local original_set_cursor = vim.api.nvim_win_set_cursor
  rawset(vim.api, "nvim_win_set_cursor", function() end)
  local ok, err = pcall(function()
    local renderer_context = { normalize_result = function(content) return content end }
    display.show(state, reference, 1, opts, adapter, ui, function() end, renderer_context)
    mappings.K()
    MiniTest.expect.equality(state.view, "call")
    mappings.q()
    MiniTest.expect.equality(state.float, nil)
    display.show(state, reference, 1, opts, adapter, ui, function() end, renderer_context)
  end)
  rawset(vim.api, "nvim_win_set_cursor", original_set_cursor)
  rawset(vim.keymap, "set", original_keymap_set)
  if not ok then error(err) end

  MiniTest.expect.equality(title, "Tool Call: grep_search [1/1] (estimate unavailable)")
end

T["managed float state"]["defaults to result view before user changes it"] = function()
  local state, reference = float_state("result")
  state.float = nil
  local adapter = {
    find_result = function(chat) return chat.messages[1] end,
  }

  local title = show_new_float(state, reference, adapter, {
    normalize_result = function(content) return content end,
  })

  MiniTest.expect.equality(title, "Tool Result: grep_search [1/1] (estimate unavailable)")
  MiniTest.expect.equality(state.view, "result")
end

T["managed float state"]["does not clear result while call view is active"] = function()
  local state, reference = float_state("result")
  state.float = nil
  local mappings = {}
  local clear_count = 0
  local original_keymap_set = vim.keymap.set
  local original_set_cursor = vim.api.nvim_win_set_cursor
  rawset(vim.keymap, "set", function(_, lhs, callback) mappings[lhs] = callback end)
  rawset(vim.api, "nvim_win_set_cursor", function() end)

  local ok, err = pcall(function()
    local adapter = {
      find_call = function() return { call_id = reference.call_id, name = reference.name, arguments = {} } end,
      find_result = function(chat) return chat.messages[1] end,
    }
    local ui = {
      create_float = function() return 2, 3 end,
      update_float = function() return true end,
      close_float = function() end,
    }
    local opts = vim.deepcopy(defaults)
    opts.run_command_language = false
    display.show(state, reference, 1, opts, adapter, ui, function() end, {
      normalize_result = function(content) return content end,
      remove_run_command_prefix = function(content) return content end,
      clear_result = function() clear_count = clear_count + 1 end,
    })

    mappings.K()
    MiniTest.expect.equality(state.float.view, "call")
    mappings.r()
  end)

  rawset(vim.keymap, "set", original_keymap_set)
  rawset(vim.api, "nvim_win_set_cursor", original_set_cursor)
  if not ok then error(err) end
  MiniTest.expect.equality(clear_count, 0)
end

T["managed float state"]["q reopens the overview when the float came from it"] = function()
  local state, reference = float_state("result")
  state.float = nil
  local mappings = {}
  local reopened = 0
  local closed = 0
  local adapter = {
    find_result = function(chat) return chat.messages[1] end,
  }
  local ui = {
    create_float = function() return 2, 3 end,
    update_float = function() return true end,
    close_float = function() closed = closed + 1 end,
  }
  local opts = vim.deepcopy(defaults)
  opts.run_command_language = false

  local original_keymap_set = vim.keymap.set
  local original_set_cursor = vim.api.nvim_win_set_cursor
  rawset(vim.keymap, "set", function(_, lhs, callback) mappings[lhs] = callback end)
  rawset(vim.api, "nvim_win_set_cursor", function() end)
  local ok, err = pcall(function()
    display.show(state, reference, 1, opts, adapter, ui, function() end, {
      normalize_result = function(content) return content end,
      open_overview = function(chat_state)
        reopened = reopened + 1
        MiniTest.expect.equality(chat_state, state)
      end,
    }, "result", true)
    mappings.q()
  end)
  rawset(vim.keymap, "set", original_keymap_set)
  rawset(vim.api, "nvim_win_set_cursor", original_set_cursor)
  if not ok then error(err) end

  MiniTest.expect.equality(state.float, nil)
  MiniTest.expect.equality(closed, 1)
  MiniTest.expect.equality(reopened, 1)
end

T["managed float state"]["q does not reopen the overview for a plain float"] = function()
  local state, reference = float_state("result")
  state.float = nil
  local mappings = {}
  local reopened = 0
  local adapter = {
    find_result = function(chat) return chat.messages[1] end,
  }
  local ui = {
    create_float = function() return 2, 3 end,
    update_float = function() return true end,
    close_float = function() end,
  }
  local opts = vim.deepcopy(defaults)
  opts.run_command_language = false

  local original_keymap_set = vim.keymap.set
  local original_set_cursor = vim.api.nvim_win_set_cursor
  rawset(vim.keymap, "set", function(_, lhs, callback) mappings[lhs] = callback end)
  rawset(vim.api, "nvim_win_set_cursor", function() end)
  local ok, err = pcall(function()
    display.show(state, reference, 1, opts, adapter, ui, function() end, {
      normalize_result = function(content) return content end,
      open_overview = function() reopened = reopened + 1 end,
    })
    mappings.q()
  end)
  rawset(vim.keymap, "set", original_keymap_set)
  rawset(vim.api, "nvim_win_set_cursor", original_set_cursor)
  if not ok then error(err) end

  MiniTest.expect.equality(reopened, 0)
end

T["managed float state"]["resets cursor when changing tools in reused float"] = function()
  local state = float_state("result")
  local next_reference = { call_id = "call-next", name = "grep_search" }
  table.insert(state.references, next_reference)
  local cursor
  local original_set_cursor = vim.api.nvim_win_set_cursor
  rawset(vim.api, "nvim_win_set_cursor", function(_, position) cursor = position end)

  local ok, err = pcall(function()
    local adapter = { find_result = function() return { name = "grep_search", content = "output" } end }
    local ui = { update_float = function() return true end }
    local opts = vim.deepcopy(defaults)
    opts.run_command_language = false
    display.show(state, next_reference, 2, opts, adapter, ui, function() end, {
      normalize_result = function(content) return content end,
    }, "result")
  end)

  vim.api.nvim_win_set_cursor = original_set_cursor
  if not ok then error(err) end
  MiniTest.expect.equality(cursor, { 1, 0 })
end

T["return to chat"] = MiniTest.new_set()

T["return to chat"]["moves the cursor to the tool line in the chat window"] = function()
  local chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, { "one", "two", "three", "four" })
  local chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(chat_win, chat_buf)

  local float_buf = vim.api.nvim_create_buf(false, true)
  local float_win = vim.api.nvim_open_win(float_buf, true, { relative = "editor", row = 0, col = 0, width = 10, height = 2 })
  local state = {
    bufnr = chat_buf,
    tools = { ["call-3"] = { call_id = "call-3", line = 3 } },
    references = {},
  }

  display.return_to_chat(state, "call-3", function() end, function()
    if vim.api.nvim_win_is_valid(float_win) then vim.api.nvim_win_close(float_win, true) end
  end)

  MiniTest.expect.equality(vim.api.nvim_get_current_win(), chat_win)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(chat_win), { 3, 0 })
  vim.api.nvim_buf_delete(chat_buf, { force = true })
end

T["return to chat"]["warns and closes when the tool line is unknown"] = function()
  local notified
  local original_notify = vim.notify
  vim.notify = function(message) notified = message end
  local closed = 0
  local state = { bufnr = -1, tools = {}, references = {} }

  local ok, err = pcall(display.return_to_chat, state, "call-missing", function() end, function() closed = closed + 1 end)
  vim.notify = original_notify
  if not ok then error(err) end

  MiniTest.expect.equality(closed, 1)
  MiniTest.expect.equality(notified, "Tool call location unavailable in the current chat.")
end

return T
