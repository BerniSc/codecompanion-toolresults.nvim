local http = require("codecompanion_toolresults.adapters.http")
local acp = require("codecompanion_toolresults.adapters.acp")

local M = {}
local providers = { http = http }

---Select provider from CodeCompanion's adapter type.
---@param chat table CodeCompanion chat instance.
---@return table? provider
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
M.acp = acp
M._providers = providers

return M
