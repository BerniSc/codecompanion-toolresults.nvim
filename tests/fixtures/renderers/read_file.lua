return {
  markdown = {
    reference = { name = "read_file", call_id = "call-read-markdown" },
    result = {
      content = "Read file `README.md` from lines 0 - 2 (3 lines total):\n````md\n# Project\n\nDescription\n````",
    },
  },
  lua = {
    reference = { name = "read_file", call_id = "call-read-lua" },
    result = {
      content = "Read file `lua/example.lua` from lines 10 - 12 (40 lines total):\n````lua\nlocal value = 42\nreturn value\n````",
    },
  },
  error = {
    reference = { name = "read_file", call_id = "call-read-error" },
    result = {
      content = "Error reading `missing.lua`\nNo such file or directory",
    },
  },
}
