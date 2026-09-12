---@class CodeCompanion.Toolresults
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.toolresults
local Toolresults = {}

---Setup the extension
---@param opts table Configuration options
function Toolresults.setup(opts)
  -- Init extension
  local chat_keymaps = require("codecompanion.config").interactions.chat.keymaps

  chat_keymaps.display_toolresults = {
    modes = {
      n = opts.keymap or "gT",
    },
    description = "Display toolresult under cursor",
    callback = function(chat)
        vim.notify("Displaying toolresult in chat " .. chat.id)
    end
  }
end

-- Functions exposed via codecompanion.extensions.toolresults
Toolresults.exports = {

}

return Toolresults
