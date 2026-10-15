local MiniTest = require("mini.test")
local hover = require("codecompanion_toolresults.hover")

local T = MiniTest.new_set()

local function preview_opts(overrides)
  return vim.tbl_extend("force", { max_lines = 4, max_width = 30 }, overrides or {})
end

local function with_overrides(overrides, callback)
  local originals = {}
  for _, override in ipairs(overrides) do
    originals[#originals + 1] = { owner = override.owner, key = override.key, value = rawget(override.owner, override.key) }
    rawset(override.owner, override.key, override.value)
  end

  local ok, result = pcall(callback)
  for index = #originals, 1, -1 do
    local original = originals[index]
    rawset(original.owner, original.key, original.value)
  end
  if not ok then
    error(result, 0)
  end
  return result
end

local function with_buffer(callback)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local original_buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(callback, bufnr)
  pcall(vim.api.nvim_set_current_buf, original_buf)
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  if not ok then
    error(err, 0)
  end
end

local function with_hover(chat_state, bufnr, callback, on_preview)
  local stop = hover.attach(chat_state, bufnr, { delay = 500 }, on_preview or function() end)
  local ok, err = pcall(callback, stop)
  stop()
  if not ok then
    error(err, 0)
  end
end

local function with_preview(chat_state, callback)
  local ok, err = pcall(callback)
  local cleanup_ok, cleanup_err = pcall(hover.close, chat_state)
  if not ok then
    error(err, 0)
  end
  if not cleanup_ok then
    error(cleanup_err, 0)
  end
end

T["preview"] = MiniTest.new_set()

T["preview"]["keeps result lines unchanged and displays tool and hints"] = function()
  local chat_state = {}
  local lines = { "one", "two", "three", "four", "five" }
  local called = false
  local keymaps, configs = {}, {}
  local original_open_win = vim.api.nvim_open_win

  with_preview(chat_state, function()
    with_overrides({
      {
        owner = vim.api,
        key = "nvim_open_win",
        value = function(bufnr, enter, config)
          configs[#configs + 1] = vim.deepcopy(config)
          return original_open_win(bufnr, enter, config)
        end,
      },
      {
        owner = vim.keymap,
        key = "set",
        value = function(mode, lhs, callback, opts)
          if opts.desc == "Open full tool result" then
            keymaps[#keymaps + 1] = { mode = mode, lhs = lhs, callback = callback, opts = opts }
          end
        end,
      },
    }, function()
      hover.show(chat_state, lines, { screenrow = 1, screencol = 1 }, preview_opts({ max_lines = 2, max_width = 50 }), "search_grep", "gT", function()
        called = true
      end)
    end)

    local preview = chat_state.hover_preview
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.bufnr, 0, -1, false), lines)
    MiniTest.expect.equality(configs[1].title, " search_grep ")
    MiniTest.expect.equality(configs[1].title_pos, "center")
    MiniTest.expect.equality(configs[2].row, configs[1].row + configs[1].height)
    local hint = "gT: open    ↓ scroll for more"
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.footer_bufnr, 0, -1, false), {
      string.rep(" ", configs[1].width - vim.fn.strdisplaywidth(hint)) .. hint,
    })
    MiniTest.expect.equality(vim.api.nvim_win_get_height(preview.winnr), 2)
    MiniTest.expect.equality(vim.bo[preview.bufnr].filetype, "markdown")
    MiniTest.expect.equality(keymaps[1].lhs, "gT")
    keymaps[1].callback()
    MiniTest.expect.equality(called, true)
  end)
  MiniTest.expect.equality(chat_state.hover_preview, nil)
end

T["preview"]["places preview to the left near the right screen edge"] = function()
  local chat_state = {}
  local columns = vim.o.columns
  local captured_config
  local original_open_win = vim.api.nvim_open_win

  with_preview(chat_state, function()
    with_overrides({ {
      owner = vim.api,
      key = "nvim_open_win",
      value = function(bufnr, enter, config)
        captured_config = vim.deepcopy(config)
        return original_open_win(bufnr, enter, config)
      end,
    } }, function()
      hover.show(chat_state, { "result" }, { screenrow = 1, screencol = columns - 3 }, preview_opts(), "run_command", false, function() end)
    end)

    MiniTest.expect.equality(captured_config.col < columns - 3, true)
    MiniTest.expect.equality(captured_config.width <= 30, true)
    MiniTest.expect.equality(captured_config.col + captured_config.width + 2 <= columns, true)
  end)
end

T["preview"]["close removes preview and footer windows and buffers"] = function()
  local chat_state = {}
  hover.show(chat_state, { "result" }, { screenrow = 1, screencol = 1 }, preview_opts(), "read_file", "gT", function() end)
  local preview = chat_state.hover_preview

  hover.close(chat_state)

  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.winnr), false)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview.bufnr), false)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.footer_winnr), false)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview.footer_bufnr), false)
end

T["preview"]["omits full-result mapping when disabled"] = function()
  local chat_state = {}
  local mappings = {}

  with_preview(chat_state, function()
    with_overrides({ {
      owner = vim.keymap,
      key = "set",
      value = function(_, lhs, _, opts)
        if opts.desc == "Open full tool result" then
          mappings[#mappings + 1] = lhs
        end
      end,
    } }, function()
      hover.show(chat_state, { "result" }, { screenrow = 1, screencol = 1 }, preview_opts(), "read_file", false, function() end)
    end)

    local preview = chat_state.hover_preview
    MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.bufnr, 0, -1, false), { "result" })
    MiniTest.expect.equality(mappings, {})
  end)
end

T["lifecycle"] = MiniTest.new_set()

T["lifecycle"]["replaces pending hover timer and rejects a stale pointer location"] = function()
  with_buffer(function(chat_buf)
    local original_keymap_set = vim.keymap.set
    local timers, previews = {}, {}
    local mouse_line, mapping = 1, nil
    local chat_state = {}

    with_overrides({
      {
        owner = vim.keymap,
        key = "set",
        value = function(mode, lhs, callback, opts)
          if lhs == "<MouseMove>" and opts.buffer == chat_buf then
            mapping = callback
          else
            original_keymap_set(mode, lhs, callback, opts)
          end
        end,
      },
      {
        owner = vim.fn,
        key = "getmousepos",
        value = function()
          return { winid = vim.api.nvim_get_current_win(), line = mouse_line, screenrow = 1, screencol = 1 }
        end,
      },
      {
        owner = vim.uv,
        key = "new_timer",
        value = function()
          local timer = {
            start = function(self, _, _, callback) self.callback = callback end,
            stop = function(self) self.stopped = true end,
            close = function(self) self.closed = true end,
          }
          timers[#timers + 1] = timer
          return timer
        end,
      },
      { owner = vim, key = "schedule_wrap", value = function(callback) return callback end },
    }, function()
      vim.api.nvim_set_current_buf(chat_buf)
      with_hover(chat_state, chat_buf, function()
        MiniTest.expect.equality(mapping ~= nil, true)
        -- Replace first target before its timer fires; only the latest target should preview.
        mapping()
        mouse_line = 2
        mapping()
        MiniTest.expect.equality(timers[1].stopped, true)
        MiniTest.expect.equality(timers[1].closed, true)
        timers[1].callback()
        MiniTest.expect.equality(#previews, 0)
        timers[2].callback()
        MiniTest.expect.equality(#previews, 1)

        -- Pointer moves again before the pending callback; stale location must not preview.
        mouse_line = 3
        mapping()
        mouse_line = 4
        timers[3].callback()
        MiniTest.expect.equality(#previews, 1)
        MiniTest.expect.equality(chat_state.hover_timer, nil)
      end, function(mouse)
        previews[#previews + 1] = mouse
      end)
    end)
  end)
end

T["lifecycle"]["updates hover target after window scroll"] = function()
  with_buffer(function(chat_buf)
    local timers, previews = {}, {}
    local mouse_line = 1
    local chat_state = {}

    with_overrides({
      {
        owner = vim.fn,
        key = "getmousepos",
        value = function()
          return { winid = vim.api.nvim_get_current_win(), line = mouse_line, screenrow = 1, screencol = 1 }
        end,
      },
      {
        owner = vim.uv,
        key = "new_timer",
        value = function()
          local timer = {
            start = function(self, _, _, callback) self.callback = callback end,
            stop = function(self) self.stopped = true end,
            close = function(self) self.closed = true end,
          }
          timers[#timers + 1] = timer
          return timer
        end,
      },
      { owner = vim, key = "schedule_wrap", value = function(callback) return callback end },
    }, function()
      vim.api.nvim_set_current_buf(chat_buf)
      local stop = hover.attach(chat_state, chat_buf, { delay = 500 }, function(mouse)
        previews[#previews + 1] = mouse
      end)
      local ok, err = pcall(function()
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        MiniTest.expect.equality(#timers, 1)

        mouse_line = 2
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        MiniTest.expect.equality(#timers, 2)
        MiniTest.expect.equality(timers[1].stopped, true)
        timers[2].callback()
        MiniTest.expect.equality(#previews, 1)
        MiniTest.expect.equality(previews[1].line, 2)
      end)
      stop()
      if not ok then
        error(err, 0)
      end
    end)
  end)
end

T["lifecycle"]["closes preview on InsertEnter"] = function()
  with_buffer(function(chat_buf)
    local chat_state = {}
    vim.api.nvim_set_current_buf(chat_buf)
    with_hover(chat_state, chat_buf, function()
      hover.show(chat_state, { "result" }, { screenrow = 1, screencol = 1 }, preview_opts(), "read_file", "gT", function() end)
      local preview = chat_state.hover_preview

      -- Verify the event itself closes the preview, independent of mode() checks.
      vim.api.nvim_exec_autocmds("InsertEnter", {})

      MiniTest.expect.equality(chat_state.hover_preview, nil)
      MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.winnr), false)
      MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview.bufnr), false)
      MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.footer_winnr), false)
      MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview.footer_bufnr), false)
    end)
  end)
end

T["lifecycle"]["cleanup cancels timer and removes mouse mapping"] = function()
  with_buffer(function(chat_buf)
    local original_keymap_set, original_keymap_del = vim.keymap.set, vim.keymap.del
    local timer = {
      stop = function(self) self.stopped = true end,
      close = function(self) self.closed = true end,
    }
    local registered, deleted = false, false

    with_overrides({
      {
        owner = vim.keymap,
        key = "set",
        value = function(mode, lhs, callback, opts)
          if lhs == "<MouseMove>" and opts.buffer == chat_buf then
            registered = true
          else
            original_keymap_set(mode, lhs, callback, opts)
          end
        end,
      },
      {
        owner = vim.keymap,
        key = "del",
        value = function(mode, lhs, opts)
          if lhs == "<MouseMove>" and opts.buffer == chat_buf then
            deleted = true
          else
            original_keymap_del(mode, lhs, opts)
          end
        end,
      },
    }, function()
      local chat_state = { hover_timer = timer }
      with_hover(chat_state, chat_buf, function(stop)
        MiniTest.expect.equality(registered, true)
        stop()
        MiniTest.expect.equality(timer.stopped, true)
        MiniTest.expect.equality(timer.closed, true)
        MiniTest.expect.equality(deleted, true)
      end)
    end)
  end)
end

return T
