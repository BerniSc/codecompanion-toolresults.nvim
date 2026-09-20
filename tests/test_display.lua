local MiniTest = require("mini.test")
local display = require("codecompanion_toolresults.display")

local T = MiniTest.new_set()

T["build_winbar"] = MiniTest.new_set()

local defaults = {
  float_show_keymaps = true,
  float_next_keymap = "]t",
  float_previous_keymap = "[t",
  float_return_keymap = "gT",
  float_close_keymap = "q",
  float_escape_keymap = "<Esc>",
}

T["build_winbar"]["centers configured mappings"] = function()
  MiniTest.expect.equality(
    display._build_winbar(defaults),
    "%=]t Next   [t Previous   gT Return   q Close   <Esc> Close%="
  )
end

T["build_winbar"]["returns nil when disabled"] = function()
  local opts = vim.tbl_extend("force", defaults, { float_show_keymaps = false })
  MiniTest.expect.equality(display._build_winbar(opts), nil)
end

T["build_winbar"]["omits disabled mappings"] = function()
  local opts = vim.tbl_extend("force", defaults, {
    float_next_keymap = false,
    float_escape_keymap = false,
  })

  MiniTest.expect.equality(
    display._build_winbar(opts),
    "%=[t Previous   gT Return   q Close%="
  )
end

T["build_winbar"]["escapes percent signs in mappings"] = function()
  local opts = vim.tbl_extend("force", defaults, { float_return_keymap = "g%T" })
  MiniTest.expect.equality(
    display._build_winbar(opts),
    "%=]t Next   [t Previous   g%%T Return   q Close   <Esc> Close%="
  )
end

return T
