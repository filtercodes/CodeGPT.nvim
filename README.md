# QuickLLM.nvim

QuickLLM is a quick way to access LLM - directly from your terminal through the Neovim editor. Simply run `command + prompt` and the response will open in a popup window. It also includes additional commands for code completion, refactoring, generating documentation, and more — with a strong focus on coding workflows.

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
          ollama = { model = "qwen3.6" }
      }
      -- Add other commands (explained further in this readme file)
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
| recall / last | none or number | Will display the last assistant response from the chat history in a popup without altering the history. Optionally accept a number to go further back (e.g., `:Chat recall 2`). |
| rewind / undo | none | Will remove the last exchange (your prompt and the assistant's response) from the chat history. Useful for reverting a bad conversation turn. |
| clear | none | Will delete complete chat short-term memory to start blank. |
| help | none | Displays the help guide. |

## Overriding Command Configurations

The configuration option `vim.g.quickllm_commands_defaults = {}` allows you to override settings for specific commands. This is particularly useful for controlling **latency vs. reasoning**.

For instance, you may want `Chat` command to use a "thinking" model for deep reasoning, but not the `Complete` or `Edit` commands. Disabling reasoning tokens will make these commands faster but with a possible loss of model accuracy.

```lua
vim.g.quickllm_commands_defaults = {
  ["complete"] = {
      thinking = false, -- Disable reasoning for quick autocompletion
      user_message_template = "Complete the following code: {{text_selection}}"
  },
  ["edit"] = {
      thinking = true, -- Apply background reasoning only when running edit command
  }
}
```

### Full list of overrides

| name                    | default         | description                                                                                                                                                       |
|-------------------------|-----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| model                   | "gpt-5-nano" | The model to use.                                                                                                                                                    |
| max_tokens              | 16384            | The maximum number of tokens to use including the prompt tokens.                                                                                                 |
| temperature             | 0.2             | 0 -> 1, what sampling temperature to use.                                                                                                                         |
| system_message_template | ""              | Helps set the behavior of the assistant.                                                                                                                          |
| user_message_template   | ""              | Instructs the assistant.                                                                                                                                          |
| callback_type           | "replace_lines" | Controls what the plugin does with the response                                                                                                                   |
| loading_message         | "Generating..." | The message displayed in the spinner while waiting for a response.                                                                                                |
| allow_empty_text_selection | false        | If true, the command can be run without a visual selection.                                                                                                       |
| language_instructions   | {}              | A table of filetype => instructions. The current buffer's filetype is used in this lookup. This is useful trigger different instructions for different languages. |
| extra_params            | {}              | A table of custom parameters to be sent to the API.                                                                                                               |


### Configuring Providers and Models

Define default models for each provider using `vim.g.quickllm_provider_defaults` and `vim.g.quickllm_search_model_defaults`.

```lua
vim.g.quickllm_provider_defaults = {
    ollama = {
        model = "deepseek-r1:7b",
        thinking = true -- Enable reasoning for this provider
    },
    anthropic = { model = "claude-haiku-4-5" },
}

vim.g.quickllm_search_model_defaults = {
    local_grounding = { model = "gemma4" },
    gemini = { model = "gemini-3.5-flash" }
}

-- Global UI toggle: Show or hide the thinking context in the popup
vim.g.quickllm_show_thinking = true
```

### Overriding Global Defaults

Generic options (like temperature) can be set globally using `vim.g.quickllm_global_commands_defaults`.

```lua
vim.g.quickllm_global_commands_defaults = {
    temperature = 0.4,
    -- extra_params = { presence_penalty = 1 }
}
```

### Configuring Presets (:Chat1, :Chat2, :Chat3)

Configure the preset commands (`:Chat1`, `:Chat2`, `:Chat3`) by appending numbers to the global variables. This is useful for mapping specific commands to different APIs or models without changing your default `:Chat` settings.

```lua
-- Configure :Chat1 to use Ollama with a specific model
vim.g.quickllm_api_provider1 = "ollama"
vim.g.quickllm_search_provider1 = "local_grounding"
vim.g.quickllm_global_commands_defaults1 = {
    model = "deepseek-coder-v2"
}
```

### Configuration Merging Logic

The system uses a "Waterfall" merging logic to determine the final settings (like model, temperature, or thinking) for any given request. Settings are applied in the following order:

1. **Hardcoded Defaults**: Base values defined in the code (lowest priority).
2. **Provider Defaults**: Values defined in `vim.g.quickllm_provider_defaults`.
3. **Preset-Specific Provider Defaults**: Values in `vim.g.quickllm_provider_defaults1`, `defaults2`, etc.
4. **Global Overrides**: Values defined in `vim.g.quickllm_global_commands_defaults`.
5. **Command-Specific Overrides**: Values defined in `vim.g.quickllm_commands` (highest priority).


### Optimizing Local Models (Ollama)

To get that "Quick" local models execution speed via Ollama, you may want to set an empty system prompt for better prompt caching. If you configured a custom one in your `Modelfile`, then be sure to disable it globally in the Ollama provider settings:

```lua
vim.g.quickllm_provider_defaults = {
  ollama = {
    system_message_template = ""
  }
}

-- Also clear for the search command specifically
vim.g.quickllm_commands = {
  search = {
    system_message_template = ""
  }
}
```

#### Templates

The `system_message_template` and the `user_message_template` can contain template macros. For example:

| macro | description |
|------|-------------|
| `{{filetype}}` | The `filetype` of the current buffer. |
| `{{text_selection}}` | The selected text in the current buffer. |
| `{{language}}` | The name of the programming language in the current buffer. |
| `{{command_args}}` | Everything passed to the command as an argument, joined with spaces. See below. |
| `{{language_instructions}}` | The found value in the `language_instructions` map. See below. |


#### Language Instructions

Some commands have templates that use the `{{language_instructions}}` macro to allow for additional instructions for specific [filetypes](https://neovim.io/doc/user/filetype.html).

```lua
vim.g.quickllm_commands_defaults = {
  ["complete"] = {
      language_instructions = {
          cpp = "Use trailing return type.",
      },
  }
}
```

The above adds a specific `Use trailing return type.` to the command `complete` for the filetype `cpp`.


#### Command Args

Commands are normally a single value, for example `:Chat complete`. You can make commands accept additional arguments by using the `{{command_args}}` macro anywhere in either `user_message_template` or `system_message_template`. For example:

```lua
vim.g.quickllm_commands = {
  ["testwith"] = {
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
  ["modernize"] = {
      user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nModernize the above code. Use current best practices. Only return the code snippet and comments. {{language_instructions}}",
      language_instructions = {
          cpp = "Refactor the code to use trailing return type, and the auto keyword where applicable.",
      },
  }
}
```
The above configuration adds the command `:Chat modernize` that attempts modernize the selected code snippet.


##  Command Defaults

The base configuration for all commands is:

```lua
{
    temperature = 0.2,
    thinking = false,
    system_message_template = "You are a {{language}} coding assistant.",
    user_message_template = "",
    callback_type = "replace_lines",
    allow_empty_text_selection = false,
    extra_params = {},
}
```


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

### Popup options

#### Popup commands

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

#### Popup commands

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

#### Popup layouts

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

#### Popup border style

```lua
vim.g.quickllm_popup_style = "rounded"
```
#### Popup window options

``` lua
-- Enable text wrapping and line numbers
vim.g.quickllm_popup_window_options = {
  wrap = true,
  linebreak = true,
  relativenumber = true,
  number = true,
}
```

#### Popup window color setup

An example of custom dark mode in vimscript.

``` vim
highlight NormalFloat guibg=#2f2f2f ctermbg=235
highlight FloatBorder guifg=#8ec07c ctermfg=108
```

#### Move completion to popup window

For any command, you can override the callback type to move the completion to a popup window. An example below is for overriding the `complete` command.

```lua
require("quickllm.config")

vim.g.quickllm_commands = {
  ["complete"] = {
    callback_type = "code_popup",
  },
}
```

#### Horizontal or vertical split window

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

### History (short-term memory) configuration

`vim.g.quickllm_chat_history_timeout` - Defines the maximum idle time in seconds before a conversation's history is considered "stale" and is automatically reset.

`vim.g.quickllm_chat_history_time_based_expiry`: Boolean (Default: `true`). - Allows disabiling history_timeout so that memory is preserved until nvim restart.

`vim.g.quickllm_chat_history_max_messages` - Sets a "sliding window" to limit the total number of messages (user + assistant) kept in memory for a conversation. This prevents the context from growing too large. Once the max_messages is reached, older messages are summarised to keep the context small.

These can be configured globally (`init.lua` or `plugins.lua`):

```lua
-- To set custom values
vim.g.quickllm_chat_history_timeout = 900   -- 15 minutes
vim.g.quickllm_chat_history_max_messages = 20 -- 20 messages total
vim.g.quickllm_chat_history_time_based_expiry = true
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


# Example Configuration

Note that QuickLLM should work without any configuration.
This is an example configuration that shows some of the options available:

``` lua

require("quickllm.config")

-- Override the default chat completions url, this is useful to override when testing custom commands
-- vim.g.quickllm_chat_completions_url = "http://127.0.0.1:800/test"

vim.g.quickllm_commands = {
  ["tests"] = {
    -- Language specific instructions for java filetype
    language_instructions = {
        java = "Use the TestNG framework.",
    },
  },
  ["doc"] = {
    -- Language specific instructions for python filetype
    language_instructions = {
        python = "Use the Google style docstrings."
    },

    -- Overrides the max tokens to be 1024
    max_tokens = 1024,
  },
  ["edit"] = {
    -- Overrides the system message template
    system_message_template = "You are {{language}} developer.",

    -- Overrides the user message template
    user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nEdit the above code. {{language_instructions}}",

    -- Display the response in a popup window. The popup window filetype will be the filetype of the current buffer.
    callback_type = "code_popup",
  },
  -- Custom command
  ["modernize"] = {
    user_message_template = "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nModernize the above code. Use current best practices. Only return the code snippet and comments. {{language_instructions}}",
    language_instructions = {
        cpp = "Use modern C++ syntax. Use auto where possible. Do not import std. Use trailing return type. Use the c++11, c++14, c++17, and c++20 standards where applicable.",
    },
  }
}

```

# Goals
* Code related usages.
* Simple.
* Easy to add custom commands.
