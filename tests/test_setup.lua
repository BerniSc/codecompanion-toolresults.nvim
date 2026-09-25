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
