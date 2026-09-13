---@class CodeCompanion.Toolresults
---@field setup fun(opts: table) Function called when extension is loaded
---@field exports? table Functions exposed via codecompanion.extensions.toolresults
local Toolresults = {}

---Setup the extension. Thin wrapper with interface for CodeCompanion loading from custom namespace
---@param opts table Configuration options
function Toolresults.setup(opts)
  require("codecompanion_toolresults").setup(opts)
end

-- Functions exposed via codecompanion.extensions.toolresults.XXX
Toolresults.exports = {
  state = function()
    return require("codecompanion_toolresults").state()
  end,
}

return Toolresults
