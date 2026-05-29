# QuickLLM.nvim

QuickLLM is a quick way to access LLM - directly from your terminal through the Neovim editor. Simply run `command + prompt` and the response will open in a popup window. It also includes additional commands for code completion, refactoring, generating documentation, and more — with a strong focus on coding workflows and extensive configurability.

## Installation

* Set environment variable for your prefered API key e.g. `ANTHROPIC_API_KEY` [Claude API key](https://platform.claude.com/settings/workspaces/default/keys).
* The plugins 'plenary' and 'nui' are also required.

Installing with [lazy.nvim](https://github.com/folke/lazy.nvim).

```lua
{
   "filtercodes/QuickLLM.nvim",
   dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
   },
   config = function()
      require("quickllm.config")
      vim.g.quickllm_api_provider = "ollama" -- Run a local model with ollama
      vim.g.quickllm_provider_defaults = {
          ollama = { model = "gemma4" }
      }
      -- Add other commands (explained below)
   end
}
```

Installing with [vim-plug](https://github.com/junegunn/vim-plug).

```vim
" Install plugins
Plug("nvim-lua/plenary.nvim")
Plug("MunifTanjim/nui.nvim")
Plug('filtercodes/QuickLLM.nvim')

call plug#end()

" Configuration after the plugins are loaded
lua << EOF
    require("quickllm.config")
    vim.g.quickllm_api_provider = "gemini"
EOF
```

Note on Neovim 0.12 and later - to fix problems with status line duplication, enable new UI engine

```lua
pcall(function() require('vim._core.ui2').enable() end)
```

## Commands

The top-level command is `:Chat`. The behavior is different depending on whether text is selected and/or arguments are passed.

### Direct Provider Commands & Presets
In addition to `:Chat` (which uses globally configured default provider), you can invoke specific providers directly, bypassing default settings eg.:
* `:Gemini <prompt>`
* `:Claude <prompt>` etc.

Using these commands behaves exactly like `:Chat`, but routes the request to the specified API with its default model.

There are also configurable presets: `:Chat1`, `:Chat2`, and `:Chat3`. To quickly switch between different models and providers without changing global configuration (e.g., setting `:Chat2` to always use Anthropic's Claude 3.5 Sonnet while `:Chat` remains local Ollama instance). See the "Overriding Command Configurations" section below for details.

### Chat
* `:Chat hello world` (with or without text selection) will trigger the `chat` command. This will send the arguments `hello world` and show the results in a popup.

![chat](examples/chat.gif?raw=true)

### Completion
* `:Chat complete` with text selection will trigger the `complete` command, LLM will try to complete the selected code snippet.

![complete](examples/completion.gif?raw=true)

### Code Edit
* `:Chat edit some instructions` with text selection and command args will invoke the `edit` command. This will treat the command args as instructions on what to do with the code snippet. In the below example, `:Chat refactor to use iteration` will apply the instruction `refactor to use iteration` to the selected code.

![edit](examples/code_edit.gif?raw=true)

### Coustom Commands
* `:Chat <command>` if there is only one argument and that argument matches a command, it will invoke that command with the given text selection. In the below example `:Chat tests` will attempt to write units for the selected code.

![tests](examples/tests.gif?raw=true)

### A list of predefined commands

| command      | input | Description |
|--------------|---- |------------------------------------|
| chat  |  prompt | Will pass the given prompt to LLM and return the response in a popup. |
| search |  prompt (optional text selection) | Will trigger a web search (grounding) before answering to provide up-to-date information and reduce LLM hallucinations. Will show the grounded answer in the popup. |
| complete |  text selection | Will ask LLM to complete the selected code directly in the editor. |
| edit  |  text selection + prompt | Will ask LLM to apply the given instructions to the selected code in the editor. |
| explain  |  text selection | Will ask LLM to explain the selected code and return the answer in a text popup. |
| question  |  text selection + prompt | Will pass the question to LLM and return the answer in a popup. |
| debug  |  text selection | Will pass the code selectiont to LLM analyze it for bugs, the results will be in a popup. |
| doc  |  text selection | Will ask LLM to document the selected code. Will update the text directly in the editor. |
| opt  |  text selection | Will ask LLM to optimize the selected code. Will update the code directly in the editor. |
| tests  |  text selection | Will ask LLM to write unit tests for the selected code in the popup window. |
| recall | none or number | Will display the last assistant response from the chat history in a popup without altering the history. Optionally accept a number to go further back (e.g., `:Chat recall 2`). |
| undo | none | Will remove the last exchange (your prompt and the assistant's response) from the chat history. Useful for reverting a bad conversation turn. |
| clear | none | Will delete complete chat short-term memory to start blank. |
| help | none | Displays the help guide. |

## Overriding Command Configurations

The primary configuration table is `vim.g.quickllm_commands_defaults`. It is a **dual-purpose table** that allows you to set options both globally (to all commands) and directly for specific commands.

### Setting Defaults

Any key placed directly in `quickllm_commands_defaults` acts as a global default. To override a setting for a specific command, add a sub-table with the command's name.

```lua
vim.g.quickllm_commands_defaults = {
    -- GLOBAL SETTINGS
    system_message_template = "",
    loading_message = "Generating...",

    -- COMMAND OVERRIDES
    complete = {
        thinking = false, -- Disable thinking for instant code completion
        temperature = 0.1, -- Low creativity for completions
    },
    edit = {
        thinking = true, -- Apply background reasoning only when running edit command
    },
    explain = {
        model = "claude-opus-4-7", -- Use a smarter model just for explanations
        provider = "anthropic", -- Make sure to target the right API provider for the model
    }
}
```

### Other Supported Overrides

| name | value | description |
|------|---------|-------------|
| `max_tokens` | 16384 | The maximum number of tokens to use including the prompt tokens. |
| `system_message_template` | `""` | Behavioral instructions for the assistant. |
| `user_message_template` | `""` | The primary prompt template. |
| `callback_type` | `"text_popup"` | Controls UI behavior (`replace_lines`, `text_popup`, `code_popup`). |
| `loading_message` | `"Generating..."` | Spinner text shown during requests. |
| `allow_empty_text_selection` | `false` | If true, command runs without a visual selection. |
| `language_instructions` | `{}` | Map of `filetype` -> specific instructions. |
| `extra_params` | `{}` | Table of custom parameters for the API (e.g., `top_p`, `stop_sequences`). |

---

### Configuring Providers and Models

Define base models for each provider using `vim.g.quickllm_provider_defaults`. This is the fallback model if no global or command-specific model is set.

```lua
vim.g.quickllm_provider_defaults = {
    ollama = { 
        model = "qwen3:8b",
        thinking = true -- Enable reasoning for this provider
    },
    anthropic = { model = "claude-haiku-4-5" },
}

-- Search (grounding) command setup for different providers
vim.g.quickllm_search_model_defaults = {
    local_grounding = { model = "gemma4" },
    gemini = { model = "gemini-3.5-flash" }
}

-- Global UI toggle: Show or hide the thinking context in the popup
vim.g.quickllm_show_thinking = true
```

### Configuring Presets (:Chat1, :Chat2, :Chat3)

Each preset has its own configuration scope. Append `1`, `2`, or `3` to the variables. This is perfect for mapping a preset to a completely different stack.

```lua
-- Configure :Chat1 to be your "Local Dev" preset
vim.g.quickllm_api_provider1 = "ollama"
vim.g.quickllm_commands_defaults1 = {
    model = "qwen3-coder",
    thinking = true,
    temperature = 0.2
}
```

### Configuration Merge Logic (The Waterfall)

When you run a command, QuickLLM determines the settings by merging tables in this order (highest priority from the top):

1.  **User Commands**: Custom logic in `vim.g.quickllm_commands[cmd]`.
2.  **Command-Specific Override**: Nested table in `vim.g.quickllm_commands_defaults[cmd]`.
3.  **Global Defaults**: Flat keys in `vim.g.quickllm_commands_defaults`.
4.  **Global Provider Defaults**: `vim.g.quickllm_provider_defaults[provider]`.
5.  **Preset Provider Defaults**: `vim.g.quickllm_provider_defaults1[provider]`.
6.  **Hardcoded Defaults**: Base values defined in the plugin code.

### Chat History (short-term memory)

QuickLLM manages history automatically. You can tune its behavior using the `vim.g.quickllm_history_opts` table.

| option | default | description |
|--------|---------|-------------|
| `max_messages` | `50` | Total messages to retain before summarizing older ones. |
| `time_based_expiry` | `false` | If `true`, history automatically clears after the `timeout`. |
| `timeout` | `1800` | Inactivity window (in seconds) before history expires (if `time_based_expiry` set to `true`). |
| `summarize_history` | `true` | If `true`, compresses the first half of the buffer into a summary when `max_messages` is reached. |
| `summarize_model` | *(Global)* | The model to use for background summarization. |
| `summarize_provider` | *(Global)* | The provider to use for background summarization. |

Example configuration (`init.lua`):

```lua
-- Modern history setup with background summarization
vim.g.quickllm_history_opts = {
    max_messages = 50,
    time_based_expiry = false,
    summarize_history = true,
    summarize_provider = "openai",
    summarize_model = "gpt-4o-mini" -- Use a cheap model for background work
}
```

#### Chat History Navigation

Quickly walk through previous assistant responses using keyboard shortcuts.

```lua
local qllm = require("quickllm")

-- Map keys 1-9 to jump to specific history items (e.g., <leader>q1 is last, q2 is one before, etc.)
-- You can increase the range to 20 or more if needed.
for i = 1, 9 do
    vim.keymap.set("n", "<leader>q" .. i, function() qllm.recall(i) end)
end

-- Walk backward/forward through history
vim.keymap.set("n", "<leader>qw", function() qllm.recall("backward") end)
vim.keymap.set("n", "<leader>qf", function() qllm.recall("forward") end)

-- Other history actions
vim.keymap.set("n", "<leader>qu", function() qllm.undo() end)
vim.keymap.set("n", "<leader>qc", function() qllm.clear() end)
```

### Search (grounding) configuration

`vim.g.quickllm_search_provider` - Defines which provider to use for the `:Chat search` command. Current supported options are `"gemini"`, `"openai"`, `"anthropic"` and `"local_grounding"`. Defaults to `"gemini"`.

`vim.g.quickllm_show_search_sources` - Boolean (Default: `true`). Allows you to see the links/citations used by the LLM during a search displayed in the popup UI. If you are using a smaller model you can set it to `false` to deal with strict context limits.

`vim.g.quickllm_ground_with_history` - Boolean (Default: `false`). If you want to send previous conversation history to the grounding model set it to `true`. This might be useful for model to pick up more info about the search term from the context, but also conversation history might confuse smaller models or create biased grounding.

```lua
vim.g.quickllm_search_provider = "anthropic"
vim.g.quickllm_show_search_sources = true
vim.g.quickllm_ground_with_history = false
```

Note that `"local_grounding"` requires `TAVILY_API_KEY` as an enviroment variable. Local Ollama model uses internet search results from [Tavily](https://app.tavily.com/home) to construct a grounded answer.


### Optimizing Local Models (Ollama)

To get that "Quick" inference speed with local models via Ollama, you may want to set an empty system prompt for better prompt caching. If you configured a custom one in your `Modelfile`, then be sure to disable it globally in the Ollama provider settings:

```lua
-- Optimize a preset (e.g., :Chat1) for super-fast local work
vim.g.quickllm_api_provider1 = "ollama"
vim.g.quickllm_commands_defaults1 = {
    system_message_template = "", -- Empty system prompt for better caching
    search = {
        provider = "local_grounding",
        system_message_template = "" -- Also clear for search
    }
}
```

### Templates

The `system_message_template` and the `user_message_template` can contain template macros. For example:

| macro | description |
|------|-------------|
| `{{filetype}}` | The `filetype` of the current buffer. |
| `{{text_selection}}` | The selected text in the current buffer. |
| `{{language}}` | The name of the programming language in the current buffer. |
| `{{command_args}}` | Everything passed to the command as an argument, joined with spaces. See below. |
| `{{language_instructions}}` | The found value in the `language_instructions` map. See below. |


### Language Instructions

Some commands have templates that use the `{{language_instructions}}` macro to allow for additional instructions for specific [filetypes](https://neovim.io/doc/user/filetype.html).

```lua
vim.g.quickllm_commands_defaults = {
  complete = {
      language_instructions = {
          cpp = "Use trailing return type.",
      },
  }
}
```

The above adds a specific `Use trailing return type.` to the command `complete` for the filetype `cpp`.


### Command Args

Commands are normally a single value, for example `:Chat complete`. You can make commands accept additional arguments by using the `{{command_args}}` macro anywhere in either `user_message_template` or `system_message_template`. For example:

```lua
vim.g.quickllm_commands = {
  testwith = {
      user_message_template =
        "Write tests for the following code: ```{{filetype}}\n{{text_selection}}```\n{{command_args}} " ..
        "Only return the code snippet and nothing else."
  }
}
```

After defining this command, any `:Chat` command that has `testwith` as its first argument will be handled. For example, `:Chat testwith some additional instructions` will be interpreted as `testwith` with `"some additional instructions"`.


## Custom Commands

Custom commands can be added to the `vim.g.quickllm_commands` configuration option to extend the available commands.

```lua
vim.g.quickllm_commands = {
  modernize = {
      user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nModernize the above code. Use current best practices. Only return the code snippet and comments. {{language_instructions}}",
      language_instructions = {
          cpp = "Refactor the code to use trailing return type, and the auto keyword where applicable.",
      },
  }
}
```
The above configuration adds the command `:Chat modernize` that attempts modernize the selected code snippet.

## More Configuration Options

### Custom status hooks

You can add custom hooks to update your status line or other ui elements, for example, this code updates the status line colour to yellow whilst the request is in progress.

```lua
vim.g.quickllm_hooks = {
	request_started = function()
		vim.cmd("hi StatusLine ctermbg=NONE ctermfg=yellow")
	end,
  request_finished = vim.schedule_wrap(function()
		vim.cmd("hi StatusLine ctermbg=NONE ctermfg=NONE")
	end)
}
```

### Lualine Status Component

There is a convenience function `get_status` so that you can add a status component to lualine. This function provides an animated progress spinner while a request is running, followed by the name of the last command and the active LLM model (e.g., `⠋ chat  🤖 qwen3.6:27b`).

```lua
local QuickllmModule = require("quickllm")

require('lualine').setup({
    sections = {
        -- ...
        lualine_x = { QuickllmModule.get_status, "encoding", "fileformat" },
        -- ...
    }
})
```

To enable the animation of the progress spinner, add `require('lualine').refresh()` to the QuickLLM hooks in configuration so that the status bar redraws during the request:

```lua
vim.g.quickllm_hooks = {
  request_started = function()
    require('lualine').refresh()
  end,
  request_finished = vim.schedule_wrap(function()
    require('lualine').refresh()
  end)
}
```

Alternativelly if you don't use `lualine` vim.notify print will tell you which model is currently in use. If you do use `lualine` you might want to set this to `false`.

```lua
vim.g.quickllm_print_model = false
```

## Popup options

### Popup commands

The default filetype of the text popup window is markdown. You can change this by setting the `quickllm_text_popup_filetype` variable.

```lua
vim.g.quickllm_text_popup_filetype = "markdown"
```

To make the internal code examples have syntax highlighting add your prefered languages to `init.vim`:
```vim
" Define the languages
let g:markdown_fenced_languages = ['python', 'javascript', 'lua', 'cpp']
" Disable built-in Tree-sitter parser for Markdown
autocmd FileType markdown lua vim.treesitter.stop()
```

When using reasoning models, you can set if popup will display the text or just show label "Thinking..."
```lua
-- Setting to true will show the thinking context in the popup
vim.g.quickllm_show_thinking = true
```

### Popup commands

```lua
vim.g.quickllm_ui_commands = {
  -- some default commands, you can remap the keys
  quit = "q", -- key to quit the popup
  use_as_output = "<c-o>", -- key to use the popup content as output and replace the original lines
  use_as_input = "<c-i>", -- key to use the popup content as input for a new API request
}
vim.g.quickllm_ui_commands = {
  -- tables as defined by nui.nvim https://github.com/MunifTanjim/nui.nvim/tree/main/lua/nui/popup#popupmap
  {"n", "<c-l>", function() print("do something") end, {noremap = false, silent = false}}
}
```

### Popup layouts

```lua
vim.g.quickllm_popup_layout = {
  -- a table as defined by nui.nvim https://github.com/MunifTanjim/nui.nvim/tree/main/lua/nui/popup#popupupdate_layout
  relative = "editor",
  position = "50%",
  size = {
    width = "80%",
    height = "80%"
  }
}
```

### Popup border style

```lua
vim.g.quickllm_popup_style = "rounded"
```

### Popup window options

```lua
-- Enable text wrapping and line numbers
vim.g.quickllm_popup_window_options = {
  wrap = true,
  linebreak = true,
  relativenumber = true,
  number = true,
}
```

### Popup window color setup

An example of custom dark mode in vimscript.

```vim
highlight NormalFloat guibg=#2f2f2f ctermbg=235
highlight FloatBorder guifg=#8ec07c ctermfg=108
```

### Move completion to popup window

For any command, you can override the callback type to move the completion to a popup window. An example below is for overriding the `complete` command.

```lua
require("quickllm.config")

vim.g.quickllm_commands = {
  complete = {
    callback_type = "code_popup",
  },
}
```

### Horizontal or vertical split window

If you prefer a horizontal or vertical split window, you can change the popup type to `horizontal` or `vertical`.

```lua
-- options are "horizontal", "vertical", or "popup". Default is "popup"
vim.g.quickllm_popup_type = "horizontal"
```

To set the height of the horizontal window or the width of the vertical popup, you can use `quickllm_horizontal_popup_size` and `quickllm_vertical_popup_size` variables.

```lua
vim.g.quickllm_horizontal_popup_size = "20%"
vim.g.quickllm_vertical_popup_size = "20%"
```

## Callback Types

Callback types control what to do with the response

| name      | Description |
|--------------|----------|
| replace_lines | replaces the current lines with the response. If no text is selected it will insert the response at the cursor. |
| text_popup | Will display the result in a text popup window. |
| code_popup | Will display the results in a popup window with the filetype set to the filetype of the current buffer |


## Template Variables

| name      | Description |
|--------------|----------|
| language |  Programming language of the current buffer. |
| filetype |  filetype of the current buffer. |
| text_selection |  Any selected text. |
| command_args | Command arguments. |
| filetype_instructions | filetype specific instructions. |


## Example Configuration

Note that QuickLLM should work without any configuration.
This is an example configuration that shows some of the options available:

```lua

require("quickllm.config")

-- Override the default chat completions url, this is useful to override when testing custom commands
-- vim.g.quickllm_chat_completions_url = "http://127.0.0.1:800/test"

vim.g.quickllm_commands = {
  tests = {
    -- Language specific instructions for java filetype
    language_instructions = {
        java = "Use the TestNG framework.",
    },
  },
  doc = {
    -- Language specific instructions for python filetype
    language_instructions = {
        python = "Use the Google style docstrings."
    },

    -- Overrides the max tokens to be 1024
    max_tokens = 1024,
  },
  edit = {
    -- Overrides the system message template
    system_message_template = "You are {{language}} developer.",

    -- Overrides the user message template
    user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nEdit the above code. {{language_instructions}}",

    -- Display the response in a popup window. The popup window filetype will be the filetype of the current buffer.
    callback_type = "code_popup",
  },
  -- Custom command
  modernize = {
    user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nModernize the above code. Use current best practices. Only return the code snippet and comments. {{language_instructions}}",
    language_instructions = {
        cpp = "Use modern C++ syntax. Use auto where possible. Do not import std. Use trailing return type. Use the c++11, c++14, c++17, and c++20 standards where applicable.",
    },
  }
}

```

