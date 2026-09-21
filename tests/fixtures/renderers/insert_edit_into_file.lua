return {
  success_with_explanation = {
    reference = { name = "insert_edit_into_file", call_id = "call-edit-success" },
    result = {
      content = "Edited `README.md`\nupdated renderer documentation",
    },
  },
  success_without_explanation = {
    reference = { name = "insert_edit_into_file", call_id = "call-edit-success-no-explanation" },
    result = {
      content = "Edited `README.md`",
    },
  },
  failure = {
    reference = { name = "insert_edit_into_file", call_id = "call-edit-failure" },
    result = {
      content = "Error: Could not find the requested oldText in `README.md`",
    },
  },
}
