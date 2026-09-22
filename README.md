# CodeCompanion Toolresults

Keep CodeCompanion chats readable while retaining access to tool results.

Tool calls remain compact in the conversation. When you want more context, open the result behind a search, file read, command, or edit without bringing every line of output back into the chat.

Follow what the agent found, check its work, or catch it heading in the wrong direction, while keeping the conversation easy to scan.

Place the cursor on a tool call and press `gT` to inspect its result. Use `gtn` and `gtp` in the chat to jump between tool calls.

Inside the result float, use `<Tab>` and `<S-Tab>` to browse results, or press `gT` to return to the tool call.

## Demo

## Installation

Install with your Neovim plugin manager alongside CodeCompanion. Defaults work without further configuration:

````lua
extensions = {
  toolresults = {
    enabled = true,
  },
},
````

Customise the extension inside `require("codecompanion").setup` when needed:

````lua
extensions = {
  toolresults = {
    enabled = true,
    opts = {
      keymaps = {
        chat = {
          show = "gT",
          next = "gtn",
          previous = "gtp",
        },
        float = {
          next = "<Tab>",
          previous = "<S-Tab>",
          close = "q",
          escape = "<Esc>",
          return_to_chat = "gT",
        },
      },
      float = {
        show_keymaps = true,
      },
      run_command_language = "bash", -- Display command snippets as bash; change label or set false to keep raw output.
    },
  },
},
````

## Current scope

The extension lets you inspect and navigate current tool results in a per-chat floating window. It reads CodeCompanion's current messages rather than keeping its own output history. Results changed or removed by context management are therefore changed or unavailable here too.

Features:

- CodeCompanion extension loading.
- Per-chat tool-call observation.
- Partial lookup in batched calls.
- Cursor-based lookup with `gT`.
- Configurable cursor navigation with `gtn` and `gtp`.
- Inheriting CodeCompanions floating-window dimensions and options.
- One reusable managed result float per chat.
- Float-local result navigation and close mappings.
- Result position in the float title.
- Safe float recreation after manual close.
- Renderer registry with fallback rendering.
- Tool-specific renderers for common file, search, command, and diagnostic results.

## Usage

1. Open a CodeCompanion chat.
2. Allow one or more tools to run.
3. Move the cursor to a rendered tool-call line, such as `run_command: date`.
4. Press `gT` to display its result. Use `gtn` to move to the next tool-call line or `gtp` to move to the previous one.

The current result opens in a floating window. The result is looked up from CodeCompanion's current message stack when requested; this extension does not maintain a second output history.
This means it will match CodeCompanions context management.

For runtime issues, call `codecompanion.extensions.toolresults.dump()` from inside Neovim. It writes a focused, on-demand diagnostic snapshot to a unique temporary directory and returns the directory path. Each tracked chat gets separate `messages.json`, `references.json`, `tools.json`, `buffer-metadata.json`, and human-readable `buffer.txt` files. Message content may contain sensitive data; inspect the files before sharing them.

For purposes of copying:

`
:lua print(require("codecompanion").extensions.toolresults.dump())
`

## Result float

The extension reuses one managed result float per chat. Displaying another result updates that float instead of opening a second window. The title includes the ordered result position, for example `Tool Result: read_file [2/5]`.

While focused inside the float:

- `<Tab>` shows the next result.
- `<S-Tab>` shows the previous result.
- `q` closes the float.
- `<Esc>` closes the float.
- `gT` closes the float and returns to the corresponding tool-call line in the chat.

Navigation wraps from last result to first and from first result to last. It uses ordered tool references, independently of chat-buffer cursor position. If the float is manually closed, the next display or navigation action recreates it safely. Closing the parent chat also closes its managed result float.

Mappings are configurable under `keymaps.float`: `next`, `previous`, `close`, `escape`, and `return_to_chat`. Set an option to `false` to disable its mapping.

The optional winbar displays configured float-local mappings at the top of the result window. Keymap options set to `false` are not shown. Set `float.show_keymaps = false` to hide the winbar while keeping keymap behavior unchanged.


## Options

| Option | Default | Description |
| --- | --- | --- |
| `keymaps.chat.show` | `"gT"` | Chat-buffer keymap for displaying a result. Set to `false` to disable. |
| `keymaps.chat.next` | `"gtn"` | Chat-buffer keymap for moving to next tool result. Set to `false` to disable. |
| `keymaps.chat.previous` | `"gtp"` | Chat-buffer keymap for moving to previous tool result. Set to `false` to disable. |
| `keymaps.float.next` | `"<Tab>"` | Float-local next-result mapping. Set to `false` to disable. |
| `keymaps.float.previous` | `"<S-Tab>"` | Float-local previous-result mapping. Set to `false` to disable. |
| `keymaps.float.close` | `"q"` | Float-local close mapping. Set to `false` to disable. |
| `keymaps.float.escape` | `"<Esc>"` | Float-local Escape mapping. Set to `false` to disable. |
| `keymaps.float.return_to_chat` | `"gT"` | Float-local mapping that closes result float and returns to its originating tool-call line. Set to `false` to disable. |
| `float.show_keymaps` | `true` | Show float-local mappings in result window winbar. |
| `run_command_language` | `"bash"` | Language label for displayed `run_command` commands. Set to another shell or `false`; default is only a display label, not a shell assumption. |
| `debug` | `false` | Enable lifecycle and reference logging. |
| `debug_buffer` | `false` | Log rendered chat-buffer lines and calculated positions. |

The diagnostic dump does not require `debug` or `debug_buffer` to be enabled.

## Behavior after context management

CodeCompanion may edit or compact older tool results. If a result is still present, `gT` displays its current content. If CodeCompanion has replaced or removed it, the extension reports that the result is unavailable.

The extension does not preserve removed output.

## Architecture

The result renderer is separate from float lifecycle. `lua/codecompanion_toolresults/renderers.lua` selects a tool-specific renderer or fallback renderer and returns buffer lines. `display.lua` remains responsible for result lookup handoff, float lifecycle, cursor placement, and float-local mappings.

See [`docs/concept.md`](docs/concept.md) for detailed design, data flow, boundaries, and planned work.

## Compatibility

The extension uses CodeCompanion's chat callbacks and message structure. It also uses the internal `codecompanion.utils.ui.create_float` helper to match CodeCompanion's floating-window behavior. That dependency is isolated in `lua/codecompanion_toolresults/adapters/ui.lua`.

CodeCompanion changes may require adapter updates.

`run_command` formatting uses the renderer registry's display-only code-fence renderer and does not assume a shell for execution. Results from tools without a dedicated renderer use fallback string or `vim.inspect` formatting.

## Testing

Tests use `mini.test` from `mini.nvim` as a development-only dependency. `make test` fetches it automatically into ignored `deps/mini.nvim`; it is not a runtime dependency.

Run the full test suite:

```sh
make test
```

Show detailed test groups:

```sh
make test VERBOSE=1
```

Run one test file:

```sh
make test_file FILE=tests/test_messages.lua
```

Message adapter tests use both a more realistic CodeCompanion message-batch fixture and smaller atomic fixtures. The full fixture checks compatibility with real message structure; atomic fixtures keep individual behaviors easy to diagnose.

## Acknowledgements

Thanks to [Oli Morris](https://github.com/olimorris) for creating [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim), which made this extension possible.

This extension grew out of [CodeCompanion discussion #3360](https://github.com/olimorris/codecompanion.nvim/discussions/3360).

Feedback, compatibility reports, and ideas for useful result renderers are welcome.

