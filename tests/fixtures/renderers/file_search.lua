return {
  matches = {
    reference = { name = "file_search", call_id = "call-file-matches" },
    result = {
      content = "<fileSearchTool>Searched files for `**/*.lua`, 2 results\n````\nlua/init.lua\nlua/module.lua\n````</fileSearchTool>",
    },
  },
  no_matches = {
    reference = { name = "file_search", call_id = "call-file-none" },
    result = {
      content = "<fileSearchTool>Searched files for `**/*.does-not-exist`, no results</fileSearchTool>",
    },
  },
  error = {
    reference = { name = "file_search", call_id = "call-file-error" },
    result = {
      content = "Invalid glob pattern `[`: malformed pattern",
    },
  },
}
