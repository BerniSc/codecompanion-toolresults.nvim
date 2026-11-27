local MiniTest = require("mini.test")

local providers = require("codecompanion_toolresults.adapters.providers")

local T = MiniTest.new_set()

T["provider selection"] = MiniTest.new_set()

T["provider selection"]["selects HTTP provider by adapter type"] = function()
  local provider, err = providers.for_chat({ adapter = { type = "http" } })
  MiniTest.expect.no_equality(provider, nil)
  ---@diagnostic disable-next-line: need-check-nil
  MiniTest.expect.equality(provider.id, "http")
  MiniTest.expect.equality(err, nil)
end

T["provider selection"]["keeps ACP disabled until its shared rendering integration is ready"] = function()
  local provider, err = providers.for_chat({ adapter = { type = "acp" } })
  MiniTest.expect.equality(provider, nil)
  MiniTest.expect.equality(err, "Unsupported CodeCompanion adapter type: acp")
end

T["provider selection"]["returns a useful error for unsupported or absent type"] = function()
  local provider, unsupported_error = providers.for_chat({ adapter = { type = "future" } })
  MiniTest.expect.equality(provider, nil)
  MiniTest.expect.equality(unsupported_error, "Unsupported CodeCompanion adapter type: future")

  local absent_provider, absent_error = providers.for_chat({})
  MiniTest.expect.equality(absent_provider, nil)
  MiniTest.expect.equality(absent_error, "CodeCompanion adapter type unavailable")
end

T["HTTP provider"] = MiniTest.new_set()

T["HTTP provider"]["reads current chat messages through its facade"] = function()
  local chat = {
    messages = {
      { role = "assistant", tools = { calls = { { call_id = "call-1", ["function"] = { name = "read_file", arguments = '{"filepath":"a.lua"}' } } } } },
      { role = "tool", tools = { call_id = "call-1", name = "read_file" }, content = "contents" },
    },
  }
  local refs = providers.http.list_references(chat)
  MiniTest.expect.equality(#refs, 1)
  MiniTest.expect.equality(refs[1].call_id, "call-1")
  MiniTest.expect.equality(providers.http.find_call(chat, "call-1").arguments, { filepath = "a.lua" })
  MiniTest.expect.equality(providers.http.find_result(chat, "call-1").content, "contents")
  MiniTest.expect.equality(providers.http.overview_items(chat, function() return "a.lua" end)[1].call_id, "call-1")
end

return T
