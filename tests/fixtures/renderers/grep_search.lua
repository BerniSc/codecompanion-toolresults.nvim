return {
  matches = {
    reference = { name = "grep_search", call_id = "call-grep-matches" },
    result = {
      content = [[<grepSearchTool>Searched text for `renderer`, 3 results
````
lua/codecompanion_toolresults/renderers.lua:1
lua/codecompanion_toolresults/display.lua:4
tests/test_renderers.lua:2
````

NOTE:
- The output format is {filepath}:{line_number}.
- For example:
/home/berni/Projects/codecompanion-toolresults.nvim/lua/init.lua:10
Refers to the matching line in the file</grepSearchTool>]],
    },
  },
  no_matches = {
    reference = { name = "grep_search", call_id = "call-grep-none" },
    result = {
      content = [[<grepSearchTool>Searched text for `does-not-exist`, no results

NOTE:
- The output format is {filepath}:{line_number}.
- For example:
/home/berni/Projects/codecompanion-toolresults.nvim/lua/init.lua:10
Refers to the matching line in the file</grepSearchTool>]],
    },
  },
  error = {
    reference = { name = "grep_search", call_id = "call-grep-error" },
    result = {
      content = "Searched text for `[`, error:\n````\nregex parse error\n````",
    },
  },
}
