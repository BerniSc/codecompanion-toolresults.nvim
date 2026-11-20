local MiniTest = require("mini.test")
local transient_preview = require("codecompanion_toolresults.transient_preview")

local T = MiniTest.new_set()

local function options(overrides)
  return vim.tbl_extend("force", { max_lines = 4, max_width = 30, title = "read_file", focusable = false }, overrides or {})
end

T["open"] = MiniTest.new_set()

T["open"]["shows body lines, filetype, and title"] = function()
  local preview = transient_preview.open({ "one", "two" }, { screenrow = 1, screencol = 1 }, options())
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.bufnr, 0, -1, false), { "one", "two" })
  MiniTest.expect.equality(vim.bo[preview.bufnr].filetype, "markdown")
  MiniTest.expect.equality(vim.api.nvim_win_get_config(preview.winnr).title[1][1], " read_file ")
  transient_preview.close(preview)
end

T["open"]["adds a footer with the open hint and scroll hint when lines overflow"] = function()
  local lines = { "1", "2", "3", "4", "5" }
  local preview = transient_preview.open(lines, { screenrow = 1, screencol = 1 },
    options({ max_lines = 2, keybind = "gT", on_view_more = function() end }))
  local footer = vim.api.nvim_buf_get_lines(preview.footer_bufnr, 0, -1, false)[1]
  MiniTest.expect.equality(vim.endswith(footer, "gT: open    ↓ scroll for more"), true)
  transient_preview.close(preview)
end

T["open"]["omits footer and full-result mapping when keybind is false"] = function()
  local preview = transient_preview.open({ "only" }, { screenrow = 1, screencol = 1 },
    options({ keybind = false, on_view_more = function() end }))
  MiniTest.expect.equality(preview.footer_winnr, nil)
  local has_open_mapping = false
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(preview.bufnr, "n")) do
    if map.desc == "Open full tool result" then
      has_open_mapping = true
    end
  end
  MiniTest.expect.equality(has_open_mapping, false)
  transient_preview.close(preview)
end

T["open"]["places preview left when the anchor is near the right edge"] = function()
  local columns = vim.o.columns
  local preview = transient_preview.open({ "x" }, { screenrow = 1, screencol = columns - 3 }, options())
  local config = vim.api.nvim_win_get_config(preview.winnr)
  MiniTest.expect.equality(config.col < columns - 3, true)
  MiniTest.expect.equality(config.col + config.width + 2 <= columns, true)
  transient_preview.close(preview)
end

T["open"]["keeps the preview on screen when the anchor is low"] = function()
  local preview = transient_preview.open({ "a", "b", "c" }, { screenrow = vim.o.lines + 10, screencol = 1 }, options())
  local config = vim.api.nvim_win_get_config(preview.winnr)
  MiniTest.expect.equality(config.row + config.height <= vim.o.lines, true)
  transient_preview.close(preview)
end

T["open"]["returns nil and leaves no scratch buffer when the window cannot open"] = function()
  local original_open = vim.api.nvim_open_win
  local buffers_before = #vim.api.nvim_list_bufs()
  vim.api.nvim_open_win = function() error("cannot open") end
  local preview = transient_preview.open({ "x" }, { screenrow = 1, screencol = 1 }, options())
  vim.api.nvim_open_win = original_open
  MiniTest.expect.equality(preview, nil)
  MiniTest.expect.equality(#vim.api.nvim_list_bufs() <= buffers_before, true)
end

T["close"] = MiniTest.new_set()

T["close"]["removes windows and buffers and tolerates nil"] = function()
  local preview = transient_preview.open({ "1", "2", "3", "4", "5" }, { screenrow = 1, screencol = 1 },
    options({ max_lines = 2, keybind = "gT", on_view_more = function() end }))
  MiniTest.expect.equality(preview ~= nil, true)
  transient_preview.close(preview)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.winnr), false)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview.bufnr), false)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.footer_winnr), false)
  transient_preview.close(nil)
end

return T
