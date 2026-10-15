local MiniTest = require("mini.test")

local T = MiniTest.new_set()

T["setup"] = MiniTest.new_set()

T["setup"]["overrides nested chat show mapping"] = function()
  local chat_keymaps = {}
  package.loaded["codecompanion.config"] = {
    interactions = {
      chat = {
        keymaps = chat_keymaps,
      },
    },
  }

  local toolresults = require("codecompanion_toolresults")
  toolresults.setup({
    keymaps = {
      chat = {
        show = "<Leader>T",
      },
    },
  })

  MiniTest.expect.equality(toolresults._opts.keymaps.chat.show, "<Leader>T")
  MiniTest.expect.equality(chat_keymaps.display_toolresults.modes.n, "<Leader>T")
end

T["setup"]["rejects unknown cursor selection modes"] = function()
  local chat_keymaps = {}
  package.loaded["codecompanion.config"] = {
    interactions = {
      chat = {
        keymaps = chat_keymaps,
      },
    },
  }

  local toolresults = require("codecompanion_toolresults")
  local ok, err = pcall(toolresults.setup, { cursor = { mode = "magnetic" } })

  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(err:match('cursor.mode must be one of "exact", "nearest", "above", or "below"') ~= nil, true)
end

T["setup"]["rejects invalid hover sizing and delay options"] = function()
  local chat_keymaps = {}
  package.loaded["codecompanion.config"] = {
    interactions = {
      chat = {
        keymaps = chat_keymaps,
      },
    },
  }

  local toolresults = require("codecompanion_toolresults")
  for _, case in ipairs({
    { opts = { delay = -1 }, message = "hover.delay must be an integer >= 0" },
    { opts = { max_lines = 0 }, message = "hover.max_lines must be an integer >= 1" },
    { opts = { max_width = 1.5 }, message = "hover.max_width must be an integer >= 1" },
  }) do
    local ok, err = pcall(toolresults.setup, { hover = case.opts })
    MiniTest.expect.equality(ok, false)
    MiniTest.expect.equality(err:match(case.message) ~= nil, true)
  end
end

T["setup"]["hover preview is opt-in"] = function()
  local chat_keymaps = {}
  package.loaded["codecompanion.config"] = {
    interactions = {
      chat = {
        keymaps = chat_keymaps,
      },
    },
  }

  local toolresults = require("codecompanion_toolresults")
  toolresults.setup()
  MiniTest.expect.equality(toolresults._opts.hover.enabled, false)
  MiniTest.expect.equality(toolresults._opts.hover.delay, 500)
end

T["setup"]["disables nested chat show mapping"] = function()
  local chat_keymaps = {}
  package.loaded["codecompanion.config"] = {
    interactions = {
      chat = {
        keymaps = chat_keymaps,
      },
    },
  }

  local toolresults = require("codecompanion_toolresults")
  toolresults.setup({
    keymaps = {
      chat = {
        show = false,
      },
    },
  })

  MiniTest.expect.equality(toolresults._opts.keymaps.chat.show, false)
  MiniTest.expect.equality(chat_keymaps.display_toolresults, nil)
end

return T
