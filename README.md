# CodeCompanion Toolresults

Keep CodeCompanion chats readable while retaining access to tool results.

Tool calls remain compact in the conversation. When you want more context, open the result behind a search, file read, command, or edit without bringing every line of output back into the chat.

Follow what the agent found, check its work, or catch it heading in the wrong direction, while keeping the conversation easy to scan.

Place the cursor on a tool call and press `gT` to inspect its result. By default, `gT` requires the cursor to be on the tool label; set `cursor.mode` to opt into selecting a nearby result. Use `gtn` and `gtp` in the chat to jump between tool calls.

Inside the result float, use `<Tab>` and `<S-Tab>` to browse results, or press `gT` to return to the tool call.

## Demo

https://github.com/user-attachments/assets/464935d3-c149-401c-8439-28025183f4f4

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
      cursor = {
        mode = "exact", -- "exact" (default), "nearest", "above", or "below".
      },
      keymaps = {
        chat = {
          show = "gT",
          next = "gtn",
          previous = "gtp",
        },
        float = {
          next = "<Tab>",
          previous = "<S-Tab>",
          toggle_view = "K",
          clear_result = "r",
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
- Cursor-based lookup with `gT`, supporting exact (default), nearest, above, and below selection modes.
- Configurable cursor navigation with `gtn` and `gtp`.
- Inheriting CodeCompanions floating-window dimensions and options.
- One reusable managed result float per chat.
- Float-local result navigation, call/result view toggle, and close mappings.
- Manual tool-result context curation, removing selected results from future local chat context.
- Result position in the float title.
- Safe float recreation after manual close.
- Renderer registry with fallback rendering.
- Tool-specific renderers for common file, search, command, and diagnostic results.

## Usage

1. Open a CodeCompanion chat.
2. Allow one or more tools to run.
3. Move the cursor to a rendered tool-call line, such as `run_command: date`.
4. Press `gT` to display its result. By default, the cursor must be on that line. Optionally configure `cursor.mode` to select the nearest tool label or nearest label strictly above or below the cursor. Use `gtn` to move to the next tool-call line or `gtp` to move to the previous one.

The float title shows an approximate token estimate for the selected result message, including in call view, for example `Tool Result: grep_search [1/3] (~240 tokens)`.
This is CodeCompanion's lightweight heuristic, not an exact provider token count.
The estimate follows the current result by `call_id` and refreshes after navigation, checkpoints, and context edits.
The title shows `estimate unavailable` when estimate metadata is absent.

### Manually clear a tool result

Press `r` in the result float to remove the selected result from future local chat context.
The action requires confirmation and is available only when the current request and tool batch have finished.
See [Clear a result](#clear-a-result) for reasons, cancellation, and limitations.


For runtime issues, call `codecompanion.extensions.toolresults.dump()` from inside Neovim. It writes a focused, on-demand diagnostic snapshot to a unique temporary directory and returns the directory path. Each tracked chat gets separate `messages.json`, `references.json`, `tools.json`, `buffer-metadata.json`, and human-readable `buffer.txt` files. Message content may contain sensitive data; inspect the files before sharing them.

For purposes of copying:

`
:lua print(require("codecompanion").extensions.toolresults.dump())
`

## Result float

The extension reuses one managed result float per chat. Displaying another result updates that float instead of opening a second window. The title includes the ordered result position, for example `Tool Result: read_file [2/5]`.

While focused inside the float:

`K` toggles between the current tool call and its result.
Structured arguments display as fenced JSON; `run_command` input displays in a `text` fence.
Result view is the default when first opening a chat's float.
The selected view persists while browsing with `<Tab>` and `<S-Tab>`, and after closing and reopening the float in the same chat.

- `<Tab>` shows the next result.
- `<S-Tab>` shows the previous result.
- `q` closes the float.
- `<Esc>` closes the float.
- `gT` closes the float and returns to the corresponding tool-call line in the chat.

Navigation wraps from last result to first and from first result to last.
It uses ordered tool references, independently of chat-buffer cursor position.
If the float is manually closed, the next display or navigation action recreates it safely in the last selected view for that chat.
Closing the parent chat discards that view preference and closes its managed result float.

Float mappings are configurable under `keymaps.float`: `toggle_view`, `clear_result`, `next`, `previous`, `close`, `escape`, and `return_to_chat`.
Set an option to `false` to disable its mapping.
`K` is the default call/result toggle; it is buffer-local to the managed float and overrides Neovim's keyword lookup there.

The optional winbar displays configured float-local mappings at the top of the result window.
Keymap options set to `false` are not shown.
Set `float.show_keymaps = false` to hide the winbar while keeping keymap behavior unchanged.


## Options

| Option | Default | Description |
| --- | --- | --- |
| `cursor.mode` | `"exact"` | How `gT` selects a result relative to cursor line: `exact` requires a tool label on that line; `nearest` selects closest label and prefers one above on ties; `above` selects closest label strictly above; `below` selects closest label strictly below. |
| `keymaps.chat.show` | `"gT"` | Chat-buffer keymap for displaying a result. Set to `false` to disable. |
| `keymaps.chat.next` | `"gtn"` | Chat-buffer keymap for moving to next tool result. Set to `false` to disable. |
| `keymaps.chat.previous` | `"gtp"` | Chat-buffer keymap for moving to previous tool result. Set to `false` to disable. |
| `keymaps.float.toggle_view` | `"K"` | Float-local toggle between tool-call arguments and result. Result view is the initial default; the selected view persists during result navigation and after closing/reopening the float in the same chat. Set to `false` to disable. |
| `keymaps.float.clear_result` | `"r"` | Open cancelable flow to clear selected result from future local chat context. Set to `false` to disable. |
| `keymaps.float.next` | `"<Tab>"` | Float-local next-result mapping. Set to `false` to disable. |
| `keymaps.float.previous` | `"<S-Tab>"` | Float-local previous-result mapping. Set to `false` to disable. |
| `keymaps.float.close` | `"q"` | Float-local close mapping. Set to `false` to disable. |
| `keymaps.float.escape` | `"<Esc>"` | Float-local Escape mapping. Set to `false` to disable. |
| `keymaps.float.return_to_chat` | `"gT"` | Float-local mapping that closes result float and returns to its originating tool-call line. Set to `false` to disable. |
| `float.show_keymaps` | `true` | Show float-local mappings in result window winbar. |
| `run_command_language` | `"bash"` | Language label for `run_command` result snippets. Set to another label or `false` to show result without a fence. Call-view input always uses a neutral `text` fence. |
| `debug` | `false` | Enable lifecycle and reference logging. |
| `debug_buffer` | `false` | Log rendered chat-buffer lines and calculated positions. |

The diagnostic dump does not require `debug` or `debug_buffer` to be enabled.

## Clear a result

In the result float, press `r` to remove the selected result from future local chat context.
Choose a preset reason, select `Other…` to enter a short explanation, or clear without a reason.
Prompts explain cancellation: press `<Esc>`, choose `Cancel`, or leave the custom reason empty.
Custom reasons are limited to 160 UTF-8 bytes and normalised to one line.
Nothing changes until you accept the final confirmation.
Clearing is available only after CodeCompanion finishes the current request and tool batch; while either is active, the action is refused without changing messages.
The action is irreversible in this plugin because the original output is not retained for undo.

Clearing replaces only the selected tool message's stored content with `User cleared this tool result.` and the optional reason.
The tool-call/result pairing remains intact.
Clearing does not edit the rendered chat buffer or other messages, which may repeat the tool output.
It curates one tool result for future local context; it does not redact every copy from the conversation.
The replacement is written to the current tool message, but session save/restore behaviour has not been integration-tested.
CodeCompanion's current session serialiser preserves only `_meta.tag`, so the plugin's cleared-state flag is lost on restore and the action may be offered again.
Clearing cannot change past requests or guarantee removal from provider-managed context.
No token-savings estimate is shown because per-message token metadata is heuristic, not an exact provider count.


## Behaviour after context management

CodeCompanion may edit or compact older tool results. If a result is still present, `gT` displays its current content. If CodeCompanion has replaced or removed it, the extension reports that the result is unavailable.

The extension does not preserve removed output.


## Architecture

The result renderer is separate from float lifecycle. `lua/codecompanion_toolresults/renderers.lua` selects a tool-specific renderer or fallback renderer and returns buffer lines. `display.lua` remains responsible for result lookup handoff, float lifecycle, cursor placement, and float-local mappings.

See [`docs/concept.md`](docs/concept.md) for detailed design, data flow, boundaries, and planned work.

## Compatibility

The extension uses CodeCompanion's chat callbacks and message structure. It also uses the internal `codecompanion.utils.ui.create_float` helper to match CodeCompanion's floating-window behavior. That dependency is isolated in `lua/codecompanion_toolresults/adapters/ui.lua`.

CodeCompanion changes may require adapter updates.

`run_command` result formatting uses display-only code fences and does not assume a shell for execution. Tool-call arguments use fenced JSON for structured input and a neutral `text` fence for command input. Results from tools without a dedicated renderer use fallback string or `vim.inspect` formatting.

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

