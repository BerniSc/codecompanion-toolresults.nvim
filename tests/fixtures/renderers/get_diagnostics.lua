return {
  diagnostics = {
    reference = { name = "get_diagnostics", call_id = "call-diagnostics" },
    result = {
      content = "Diagnostics for `lua/example.lua` (2 found):\n1:1 ERROR lua-language-server undefined global `vim`\n4:5 WARNING lua-language-server unused local `value`\n\nCode:\n1: local value = vim.api.nvim_get_current_buf()\n4: return value",
    },
  },
  none = {
    reference = { name = "get_diagnostics", call_id = "call-diagnostics-none" },
    result = {
      content = "No diagnostics found for `lua/example.lua`",
    },
  },
}
