local http = require("codecompanion_toolresults.adapters.http")

local M = {}
local providers = { http = http }

---Select provider from CodeCompanion's adapter type.
---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@return CodeCompanionToolresults.Provider? provider
---@return string? error
function M.for_chat(chat)
  local adapter_type = chat and chat.adapter and chat.adapter.type
  local provider = providers[adapter_type]
  if provider then
    return provider
  end

  if adapter_type == nil then
    return nil, "CodeCompanion adapter type unavailable"
  end
  return nil, "Unsupported CodeCompanion adapter type: " .. tostring(adapter_type)
end

M.http = http
M._providers = providers

return M
