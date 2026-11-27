local MiniTest = require("mini.test")

local acp = require("codecompanion_toolresults.adapters.acp")

local T = MiniTest.new_set()

T["ACP references"] = MiniTest.new_set()

T["ACP references"]["sorts existing IDs, then appends newly observed IDs without retaining payloads"] = function()
  local chat = { tool_calls = { acp = {
    zeta = { toolCallId = "zeta", kind = "execute", status = "completed", rawInput = { command = "secret" } },
    alpha = { toolCallId = "alpha", title = "Read", status = "pending" },
  } } }
  local references = acp.list_references(chat)
  MiniTest.expect.equality(vim.tbl_map(function(ref) return ref.call_id end, references), { "alpha", "zeta" })
  MiniTest.expect.equality(references[1].name, "Read")
  MiniTest.expect.equality(references[1].outcome, "active")
  MiniTest.expect.equality(references[1].provider_status, "pending")
  MiniTest.expect.equality(vim.tbl_contains(vim.tbl_keys(references[1]), "rawInput"), false)

  chat.tool_calls.acp.beta = { toolCallId = "beta", kind = "read", status = "in_progress" }
  references = acp.list_references(chat)
  MiniTest.expect.equality(vim.tbl_map(function(ref) return ref.call_id end, references), { "alpha", "zeta", "beta" })
end

T["ACP references"]["maps terminal outcomes deliberately and handles malformed stores"] = function()
  local chat = { tool_calls = { acp = {
    ok = { toolCallId = "ok", kind = "read", status = "completed" },
    bad = { toolCallId = "bad", kind = "execute", status = "failed" },
    reject = { toolCallId = "reject", status = "rejected" },
    cancel = { toolCallId = "cancel", status = "cancelled" },
    unknown = { toolCallId = "unknown", status = "surprise" },
    mismatched = { toolCallId = "different", status = "completed" },
  } } }
  local refs = acp.list_references(chat)
  local by_id = {}
  for _, ref in ipairs(refs) do by_id[ref.call_id] = ref end
  MiniTest.expect.equality(by_id.ok.outcome, "completed")
  MiniTest.expect.equality(by_id.bad.outcome, "failed")
  MiniTest.expect.equality(by_id.reject.outcome, "unavailable")
  MiniTest.expect.equality(by_id.cancel.outcome, "unavailable")
  MiniTest.expect.equality(by_id.unknown.outcome, "unavailable")
  MiniTest.expect.equality(by_id.different, nil)
  MiniTest.expect.equality(acp.list_references({ tool_calls = { acp = false } }), {})
  ---@diagnostic disable-next-line: param-type-mismatch
  MiniTest.expect.equality(acp.list_references(nil), {})
end

T["ACP lookups"] = MiniTest.new_set()

T["ACP lookups"]["returns native current records by map call ID only"] = function()
  local current = { toolCallId = "provider-id", status = "completed", rawOutput = "latest" }
  local chat = { messages = { { role = "tool", content = "must not be read" }, }, tool_calls = { acp = { ["provider-id"] = current } } }
  MiniTest.expect.equality(acp.find_call(chat, "map-id"), nil)
  MiniTest.expect.equality(acp.find_call(chat, "provider-id"), current)
  MiniTest.expect.equality(acp.find_result(chat, "provider-id"), current)
  local replacement = { toolCallId = "provider-id", status = "completed", rawOutput = "replacement" }
  chat.tool_calls.acp["provider-id"] = replacement
  MiniTest.expect.equality(acp.find_call(chat, "provider-id"), replacement)
  MiniTest.expect.equality(acp.find_result(chat, "provider-id"), replacement)
  MiniTest.expect.equality(acp.find_result(chat, "provider-id").rawOutput, "replacement")
  MiniTest.expect.equality(acp.find_result(chat, "missing"), nil)
  MiniTest.expect.equality(acp.find_result({ tool_calls = { acp = { x = { toolCallId = "x", status = "completed" } } } }, "x").status, "completed")
  MiniTest.expect.equality(acp.find_result({ tool_calls = { acp = { x = { toolCallId = "x", status = "in_progress" } } } }, "x"), nil)
end

T["ACP lookups"]["does not treat empty active content as an available result"] = function()
  local chat = {
    tool_calls = {
      acp = {
        active = { toolCallId = "active", status = "in_progress", content = {} },
        completed = { toolCallId = "completed", status = "completed", content = {} },
      },
    },
  }

  MiniTest.expect.equality(acp.find_result(chat, "active"), nil)
  MiniTest.expect.equality(acp.find_result(chat, "completed"), chat.tool_calls.acp.completed)
end

T["ACP overview"] = MiniTest.new_set()

T["ACP overview"]["summarises current raw input without exposing it in items"] = function()
  local chat = { tool_calls = { acp = {
    one = { toolCallId = "one", kind = "execute", status = "in_progress", rawInput = { command = "inspect me" } },
  } } }
  local items = acp.overview_items(chat, function(_, input) return input.command end)
  MiniTest.expect.equality(items[1], {
    call_id = "one", index = 1, name = "execute", outcome = "active", summary = "inspect me",
  })
end

T["ACP positions"] = MiniTest.new_set()

local function with_buffer(lines, callback)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local ok, err = pcall(callback, bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  if not ok then error(err) end
end

T["ACP positions"]["uses earliest live mark and ignores duplicate marks on later calls"] = function()
  with_buffer({ "first summary", "approval", "second summary" }, function(bufnr)
    local ns = vim.api.nvim_create_namespace("CodeCompanion-tool_calls")
    local summary = vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {})
    local approval = vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {})
    local other = vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 3, {})
    local chat = { tool_call_marks = { [summary] = "same", [approval] = "same", [other] = "other" } }
    local refs = {
      { call_id = "same" }, { call_id = "other" }, { call_id = "pending" },
    }
    local found, diagnostics = acp.find_lines(chat, bufnr, refs)
    MiniTest.expect.equality(found, { same = 1, other = 2 })
    MiniTest.expect.equality(#diagnostics.unresolved, 1)
    MiniTest.expect.equality(diagnostics.ambiguous, 0)
  end)
end

T["ACP positions"]["rejects two IDs on one line without invalidating unrelated IDs"] = function()
  with_buffer({ "ambiguous", "safe" }, function(bufnr)
    local ns = vim.api.nvim_create_namespace("CodeCompanion-tool_calls")
    local first = vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {})
    local second = vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 1, {})
    local safe = vim.api.nvim_buf_set_extmark(bufnr, ns, 1, 0, {})
    local chat = { tool_call_marks = { [first] = "one", [second] = "two", [safe] = "three" } }
    local found, diagnostics = acp.find_lines(chat, bufnr, {
      { call_id = "one", status = "available" },
      { call_id = "two", status = "available" },
      { call_id = "three", status = "available" },
    })
    MiniTest.expect.equality(found, { three = 2 })
    MiniTest.expect.equality(diagnostics.ambiguous, 2)
    MiniTest.expect.equality(#diagnostics.unresolved, 2)
  end)
end

T["ACP positions"]["reports invalid buffers"] = function()
  local found, diagnostics = acp.find_lines({}, -1, { { call_id = "x", status = "available" } })
  MiniTest.expect.equality(found, {})
  MiniTest.expect.equality(diagnostics.invalid_buffer, true)
end

return T
