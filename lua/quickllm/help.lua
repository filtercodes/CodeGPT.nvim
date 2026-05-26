local Utils = require("quickllm.utils")
local Ui = require("quickllm.ui")

local M = {}

local command_descriptions = {
    chat = "General purpose chat assistant. Use this for general questions, brainstorming, or when no code is selected. It maintains conversation history.",
    search = "Triggers a web search (grounding) before answering to provide up-to-date information and reduce LLM hallucinations.",
    complete = "Completes the current code selection. Useful for finishing a function or block of code based on the context provided by the selection.",
    edit = "Modifies the selected code based on your instructions. Use this to refactor, change logic, or apply specific transformations to existing code.",
    explain = "Provides a detailed explanation of the selected code. It breaks down the logic and explains it in simple terms, useful for understanding complex legacy code.",
    doc = "Generates documentation for the selected code. It produces function/method documentation (e.g., Javadoc, Doxygen) following best practices for the language.",
    tests = "Generates unit tests for the selected code. It attempts to use standard testing frameworks appropriate for the language (e.g., JUnit for Java, gtest for C++).",
    opt = "Suggests optimizations for the selected code. It looks for performance improvements or cleaner ways to implement the same logic.",
    debug = "Analyzes the selected code for potential bugs or issues. It acts as a static analysis tool to spot logical errors or common pitfalls.",
    question = "Allows you to ask a specific question about the selected code. Unlike 'chat', this focuses context specifically on the selection.",
    generate = "Generates new code from scratch based on a prompt. Use this when you want to create a new function or class without starting from existing code.",
    clear = "Clears the chat history for the current buffer. This resets the conversation context.",
    recall = "Displays the last response from the assistant in a popup window. Accepts an optional number to go further back (e.g., `:Chat recall 2` for the second-to-last response).",
    last = "Alias for 'recall'. Displays a previous response from the assistant.",
    rewind = "Removes the last exchange (your prompt and the assistant's response) from the chat history. Useful for undoing a bad conversation turn.",
    undo = "Alias for 'rewind'. Removes the last exchange from the history.",
    help = "Displays this help file, listing available commands, keybindings, and configuration options.",
}

function M.get_help_lines()
    local lines = {
        "# QuickLLM.nvim Help",
        "",
        "## Usage",
        "- `:Chat <prompt>`: Send a general prompt to the LLM.",
        "- `:Chat <command>`: Execute a specific command (e.g., `:Chat explain`).",
        "- `:'<,'>Chat <command>`: Execute a command on a visual selection.",
        "",
        "## UI Keybindings",
    }

    local ui_cmds = vim.g.quickllm_ui_commands
    table.insert(lines, "- `" .. ui_cmds.quit .. "`: Quit window")
    table.insert(lines, "- `" .. ui_cmds.use_as_output .. "`: Use as output (replace original selection with response)")
    table.insert(lines, "- `" .. ui_cmds.use_as_input .. "`: Use as input (select response and start new chat)")
    
    table.insert(lines, "")
    table.insert(lines, "## Commands")

    local commnds_listed = {
        "chat", "search", "complete", "edit", "explain", "doc", "tests",
        "opt", "debug", "question", "generate", "clear",
        "recall", "last", "rewind", "undo", "help"
    }

    local all_commands = {}
    local seen = {}

    for _, name in ipairs(commnds_listed) do
        -- Only add it if it actually exists in the defaults or descriptions
        if command_descriptions[name] or (vim.g.quickllm_commands_defaults and vim.g.quickllm_commands_defaults[name]) then
            table.insert(all_commands, name)
            seen[name] = true
        end
    end
    
    local function collect_cmds(source)
        if not source then return end
        for name, _ in pairs(source) do
            if not seen[name] then
                table.insert(all_commands, name)
                seen[name] = true
            end
        end
    end

    collect_cmds(vim.g.quickllm_commands_defaults)
    collect_cmds(vim.g.quickllm_commands)

    for _, name in ipairs(all_commands) do
        local desc = command_descriptions[name] or "Custom user command."
        table.insert(lines, "### " .. name)
        table.insert(lines, desc)
        table.insert(lines, "")
    end

    table.insert(lines, "## Configuration")
    table.insert(lines, "You can customize QuickLLM by setting global variables in your Neovim config (init.lua).")
    table.insert(lines, "")
    
    table.insert(lines, "### Provider Settings")
    table.insert(lines, "`vim.g.quickllm_api_provider` (string)")
    table.insert(lines, "Sets the active LLM provider. Default: `'openai'`.")
    table.insert(lines, "Available options: `'openai'`, `'anthropic'`, `'gemini'`, `'ollama'`, `'groq'`.")
    table.insert(lines, "")
    
    table.insert(lines, "### Model Configuration")
    table.insert(lines, "To change the model, you can set defaults per command or globally.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_global_commands_defaults` (table)")
    table.insert(lines, "Sets default parameters for ALL commands. Useful for forcing a specific model everywhere.")
    table.insert(lines, "Example: `vim.g.quickllm_global_commands_defaults = { model = 'gpt-4o' }`")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_commands` (table)")
    table.insert(lines, "Overrides specific commands. Useful for using different models for different tasks (e.g., a cheaper model for docs, a smarter one for coding).")
    table.insert(lines, "Example: `vim.g.quickllm_commands = { doc = { model = 'gpt-3.5-turbo' } }`")
    table.insert(lines, "")

    table.insert(lines, "### Search (Grounding)")
    table.insert(lines, "To set the search model.")
    table.insert(lines, "")
    table.insert(lines, "Example: `vim.g.quickllm_search_provider = anthropic`")
    table.insert(lines, "`vim.g.quickllm_global_commands_defaults = { search_model = 'claude-sonnet-4-6' }`")
    table.insert(lines, "Overrides default grounding model. Be aware that API specs might be different for older models")
    table.insert(lines, "")

    table.insert(lines, "### Chat History (Memory)")
    table.insert(lines, "`vim.g.quickllm_chat_history_max_messages` (number)")
    table.insert(lines, "Maximum number of messages to retain in the chat context window. Default: `20`.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_chat_history_timeout` (number)")
    table.insert(lines, "Time in seconds before the chat history expires and is cleared. Default: `900` (15 minutes).")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_chat_history_time_based_expiry` (boolean)")
    table.insert(lines, "Whether to auto-clear history after the timeout. Default: `true`.")
    table.insert(lines, "")

    table.insert(lines, "### UI Customization")
    table.insert(lines, "`vim.g.quickllm_popup_type` (string)")
    table.insert(lines, "Determines how the result window opens.")
    table.insert(lines, "Options:")
    table.insert(lines, "- `'popup'`: Centered floating window (default).")
    table.insert(lines, "- `'horizontal'`: Split window at the bottom.")
    table.insert(lines, "- `'vertical'`: Split window on the right.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_horizontal_popup_size` (string)")
    table.insert(lines, "Height of the horizontal split. Default: `'20%'`.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_vertical_popup_size` (string)")
    table.insert(lines, "Width of the vertical split. Default: `'20%'`.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_popup_border` (table)")
    table.insert(lines, "Border style for the popup window. Default: `{ style = 'rounded' }`.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_text_popup_filetype` (string)")
    table.insert(lines, "Filetype for the result window (for syntax highlighting). Default: `'markdown'`.")
    table.insert(lines, "")
    table.insert(lines, "`vim.g.quickllm_ui_commands` (table)")
    table.insert(lines, "Customizes keybindings within the QuickLLM window.")
    table.insert(lines, "Default:")
    table.insert(lines, "```lua")
    table.insert(lines, "vim.g.quickllm_ui_commands = {")
    table.insert(lines, "    quit = 'q',")
    table.insert(lines, "    use_as_output = '<c-o>',")
    table.insert(lines, "    use_as_input = '<c-i>'")
    table.insert(lines, "}")
    table.insert(lines, "```")
    table.insert(lines, "")
    
    table.insert(lines, "### Miscellaneous")
    table.insert(lines, "`vim.g.quickllm_clear_visual_selection` (boolean)")
    table.insert(lines, "Whether to clear the visual selection after a command runs. Default: `true`.")

    table.insert(lines, "")
    table.insert(lines, "## Workflow Examples")
    
    table.insert(lines, "### 1. The Iterative Refactor")
    table.insert(lines, "1. Select a function visually.")
    table.insert(lines, "2. Run `:Chat opt` to request an optimized version.")
    table.insert(lines, "3. If the result is close but not quite right, press `<c-i>` (Use as Input).")
    table.insert(lines, "4. This selects the new code and opens the chat prompt.")
    table.insert(lines, "5. Type: \"Make it more functional style\" and hit Enter.")
    table.insert(lines, "6. Once satisfied, press `<c-o>` (Use as Output) to replace your original code.")
    table.insert(lines, "")

    table.insert(lines, "### 2. The TDD Helper")
    table.insert(lines, "Writing tests before (or immediately after) the code.")
    table.insert(lines, "1. Write a function signature or select an existing class.")
    table.insert(lines, "2. Run `:Chat tests`.")
    table.insert(lines, "3. Copy the generated tests into your test file.")
    table.insert(lines, "4. If you need a specific framework, use: `:Chat generate unit tests for this using Vitest`.")
    table.insert(lines, "")

    table.insert(lines, "### 3. The Legacy Code Understanding")
    table.insert(lines, "1. Select a complex, undocumented block of legacy code.")
    table.insert(lines, "2. Run `:Chat explain`.")
    table.insert(lines, "3. Read the explanation in the popup.")
    table.insert(lines, "4. Ask additional questions for a specific variable -> Press `<c-i>` and ask: \"What is the purpose of the 'flag' variable here?\"")
    
    return lines
end

function M.show_help(bufnr)
    local lines = M.get_help_lines()
    local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
    
    -- If no visual selection, we still need generic coordinates for the popup
    -- The popup function handles "empty" coordinates gracefully by centering or defaulting
    Ui.popup(lines, "markdown", bufnr, start_row, start_col, end_row, end_col)
end

return M
