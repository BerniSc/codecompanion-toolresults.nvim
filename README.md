# CodeCompanion - Toolresult Extension

Extension for the [awesome CodeCompanion Neovim Plugin](https://codecompanion.olimorris.dev/), based on [this conversation](https://github.com/olimorris/codecompanion.nvim/discussions/3360) and @olimorris fantastic idea.

The goal is to bring an option back to view the results of toolcalls that were performed by an LLM without cluttering the Chat-Buffer.

# Concept
How I envision it is that we bind in as an extension, we get access to the chat-buffer, listen for new messages and classify them. If they are toolcalls we "store" them per buffer, then we monitor either cursor or mouse (not yet sure) and if they are over a toolcalls allow some action to show the result of those toolcalls in a new floating window.



