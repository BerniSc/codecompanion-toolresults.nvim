local MiniTest = require("mini.test")
local navigation = require("codecompanion_toolresults.navigation")

local T = MiniTest.new_set()

T["next_index"] = MiniTest.new_set()

T["next_index"]["wraps forward"] = function()
  MiniTest.expect.equality(navigation.next_index({ {}, {}, {} }, 3, 1), 1)
  MiniTest.expect.equality(navigation.next_index({ {}, {}, {} }, 1, 1), 2)
end

T["next_index"]["wraps backward"] = function()
  MiniTest.expect.equality(navigation.next_index({ {}, {}, {} }, 1, -1), 3)
  MiniTest.expect.equality(navigation.next_index({ {}, {}, {} }, 3, -1), 2)
end

T["next_index"]["returns nil for empty references"] = function()
  MiniTest.expect.equality(navigation.next_index({}, 1, 1), nil)
end

return T
