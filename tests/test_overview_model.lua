local MiniTest = require("mini.test")

local model = require("codecompanion_toolresults.overview_model")

local T = MiniTest.new_set()

T["summary"] = MiniTest.new_set()

T["summary"]["uses a flattened run_command command"] = function()
  MiniTest.expect.equality(model.summary("cat << EOF\na\nEOF\n", nil), "cat << EOF a EOF")
end

T["summary"]["truncates by characters instead of bytes"] = function()
  local command = string.rep("é", 60)
  local summary = model.summary(command, nil)
  MiniTest.expect.equality(vim.fn.strchars(summary), 55)
  MiniTest.expect.equality(vim.endswith(summary, "…"), true)
end

T["summary"]["uses the first known string argument"] = function()
  MiniTest.expect.equality(model.summary(nil, { query = "needle", filepath = "a.lua" }), "a.lua")
  MiniTest.expect.equality(model.summary(nil, { pattern = "*.lua" }), "*.lua")
end

T["summary"]["returns empty text for missing or unknown arguments"] = function()
  MiniTest.expect.equality(model.summary(nil, nil), "")
  MiniTest.expect.equality(model.summary(nil, { unknown = "value" }), "")
  MiniTest.expect.equality(model.summary(nil, { filepath = 42 }), "")
end

T["format_row"] = MiniTest.new_set()

T["format_row"]["renders ordinal, outcome glyph, tool name and summary"] = function()
  local row = model.format_row({ index = 3, name = "read_file", outcome = "failed", summary = "a.lua" })
  MiniTest.expect.equality(row, " 03  !  read_file         a.lua")
end

T["format_row"]["falls back for unknown tool names"] = function()
  local row = model.format_row({ index = 1, name = nil, outcome = "unavailable", summary = "" })
  MiniTest.expect.equality(row:find("unknown", 1, true) ~= nil, true)
end

T["group"] = MiniTest.new_set()

local items = {
  { index = 1, name = "grep_search", outcome = "completed" },
  { index = 2, name = "read_file", outcome = "failed" },
  { index = 3, name = "grep_search", outcome = "cancelled" },
  { index = 4, name = "run_command", outcome = "completed" },
  { index = 5, name = "read_file", outcome = "rejected" },
}

T["group"]["flat grouping returns one unlabelled group in message order"] = function()
  local groups = model.group(items, "none")
  MiniTest.expect.equality(#groups, 1)
  MiniTest.expect.equality(groups[1].label, nil)
  MiniTest.expect.equality(vim.tbl_map(function(item) return item.index end, groups[1].items), { 1, 2, 3, 4, 5 })
end

T["group"]["outcome grouping uses fixed order and keeps message order inside groups"] = function()
  local groups = model.group(items, "outcome")
  local keys, indexes = {}, {}
  for _, group in ipairs(groups) do
    keys[#keys + 1] = group.key
    indexes[#indexes + 1] = vim.tbl_map(function(item) return item.index end, group.items)
  end
  MiniTest.expect.equality(keys, { "completed", "failed", "rejected", "cancelled" })
  MiniTest.expect.equality(indexes, { { 1, 4 }, { 2 }, { 5 }, { 3 } })
  MiniTest.expect.equality(groups[1].label, "Completed")
end

T["group"]["tool grouping follows first appearance"] = function()
  local groups = model.group(items, "tool")
  local keys = vim.tbl_map(function(group) return group.key end, groups)
  MiniTest.expect.equality(keys, { "grep_search", "read_file", "run_command" })
  MiniTest.expect.equality(#groups[2].items, 2)
  MiniTest.expect.equality(groups[2].label, "read_file")
end

T["group"]["rejects unknown groupings"] = function()
  local groups, err = model.group(items, "agent_turn")
  MiniTest.expect.equality(groups, nil)
  MiniTest.expect.equality(err, "unknown overview grouping: agent_turn")
end

T["group"]["returns no groups for an empty chat"] = function()
  MiniTest.expect.equality(model.group({}, "outcome"), {})
  MiniTest.expect.equality(model.group({}, "none"), {})
end

return T
