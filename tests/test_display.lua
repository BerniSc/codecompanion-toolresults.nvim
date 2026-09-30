local MiniTest = require("mini.test")
local display = require("codecompanion_toolresults.display")

local T = MiniTest.new_set()

T["build_winbar"] = MiniTest.new_set()

local defaults = {
  keymaps = {
    float = {
      toggle_view = "K",
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
    "%=K Tool call   <Tab> Next   <S-Tab> Previous   gT Return   q Close   <Esc> Close%=")
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
    "%=K Tool call   <S-Tab> Previous   gT Return   q Close%=")
end

T["build_winbar"]["shows result action while call view is selected"] = function()
  MiniTest.expect.equality(display._build_winbar(defaults, "call"),
    "%=K Result   <Tab> Next   <S-Tab> Previous   gT Return   q Close   <Esc> Close%=")
end

T["build_winbar"]["escapes percent signs in mappings"] = function()
  local opts = vim.deepcopy(defaults)
  opts.keymaps.float.return_to_chat = "g%T"
  MiniTest.expect.equality(display._build_winbar(opts, "result"),
    "%=K Tool call   <Tab> Next   <S-Tab> Previous   g%%T Return   q Close   <Esc> Close%=")
end

return T
