vim.g["quickllm_chat_completions_url"] = "https://api.openai.com/v1/chat/completions"

-- Read old config if it exists
if vim.g["quickllm_openai_api_provider"] and #vim.g["quickllm_openai_api_provider"] > 0 then
    vim.g["quickllm_api_provider"] = vim.g["quickllm_openai_api_provider"]
end

-- Alternative provider
vim.g["quickllm_api_provider"] = vim.g["quickllm_api_provider"] or "openai"

-- Default Models for Providers
vim.g["quickllm_provider_defaults"] = vim.tbl_extend("force", {
    openai = {
        model = "gpt-5.4-nano",
        reasoning = { effort = "medium" },
    },
    ollama = {
        model = "qwen3:8b",
    },
    anthropic = {
        model = "claude-haiku-4-5-20251001",
        max_tokens = 4096,
    },
    gemini = {
        model = "gemini-2.5-flash",
    },
    groq = {
        model = "qwen/qwen3-32b",
    },
    local_grounding = {
        model = "qwen3:8b",
    },
}, vim.g["quickllm_provider_defaults"] or {})

-- Default Search Models per Provider
vim.g["quickllm_search_model_defaults"] = vim.tbl_extend("force", {
    gemini = { model = "gemini-2.5-flash" },
    anthropic = { model = "claude-sonnet-4-6" },
    openai = { model = "gpt-5.5" },
    local_grounding = { model = "qwen3:8b" },
}, vim.g["quickllm_search_model_defaults"] or {})

-- Chat Presets
for i = 1, 3 do
    local provider_key = "quickllm_api_provider" .. i
    local search_key = "quickllm_search_provider" .. i
    local defaults_key = "quickllm_global_commands_defaults" .. i
    
    vim.g[provider_key] = vim.g[provider_key] or vim.g["quickllm_api_provider"]
    vim.g[search_key] = vim.g[search_key] or "gemini"
    vim.g[defaults_key] = vim.g[defaults_key] or nil
end

-- Clears visual selection after completion
vim.g["quickllm_clear_visual_selection"] = true

-- Print the model name in a notification before each request
if vim.g["quickllm_print_model"] == nil then
    vim.g["quickllm_print_model"] = true
end

-- Ensure user commands table exists
vim.g["quickllm_commands"] = vim.g["quickllm_commands"] or {}

vim.g["quickllm_hooks"] = {
    request_started = nil,
    request_finished = nil,
}

-- Border style to use for the popup
vim.g["quickllm_popup_border"] = { style = "rounded" }

-- Wraps the text on the popup window, deprecated in favor of quickllm_popup_window_options
vim.g["quickllm_wrap_popup_text"] = true

-- Passes native Neovim window options (vim.wo) to the popup window.
-- For example: { wrap = true, spell = false, cursorline = true, foldenable = false }
vim.g["quickllm_popup_window_options"] = {}

-- Set the filetype of a text popup is markdown
vim.g["quickllm_text_popup_filetype"] = "markdown"

-- Set the type of ui to use for the popup, options are "popup", "vertical" or "horizontal"
vim.g["quickllm_popup_type"] = "popup"

-- Set the height of the horizontal popup
vim.g["quickllm_horizontal_popup_size"] = "20%"

-- Set the width of the vertical popup
vim.g["quickllm_vertical_popup_size"] = "20%"

-- Set timeout for chat history
if vim.g["quickllm_chat_history_timeout"] == nil then
    vim.g["quickllm_chat_history_timeout"] = 900
end

-- Set if the chat history should expire based on time
if vim.g["quickllm_chat_history_time_based_expiry"] == nil then
    vim.g["quickllm_chat_history_time_based_expiry"] = true
end

-- Set max messages for chat history
if vim.g["quickllm_chat_history_max_messages"] == nil then
    vim.g["quickllm_chat_history_max_messages"] = 20
end

-- Default Command Templates
vim.g["quickllm_commands_defaults"] = {
    ["complete"] = {
        user_message_template =
        "I have the following {{language}} code snippet: ```{{filetype}}\n{{text_selection}}```\nComplete the rest. Use best practices and write really good documentation. {{language_instructions}} Only return the code snippet and nothing else.",
        language_instructions = {
            ["*"] = "Use modern {{language}} syntax and features.",
        },
    },
    ["generate"] = {
        user_message_template =
        "Write code in {{language}} using best practices and write really good documentation. {{language_instructions}} Only return the code snippet and nothing else. {{command_args}}",
        language_instructions = {
            ["*"] = "Use modern {{language}} syntax and features.",
        },
        allow_empty_text_selection = true,
    },
    ["edit"] = {
        user_message_template =
        "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\n{{command_args}}. {{language_instructions}} Only return the code snippet and nothing else.",
        language_instructions = {
            ["*"] = "Use modern {{language}} syntax and features.",
        },
    },
    ["explain"] = {
        user_message_template =
        "Explain the following {{language}} code: ```{{filetype}}\n{{text_selection}}``` Explain as if you were explaining to another developer.",
        callback_type = "text_popup",
    },
    ["question"] = {
        user_message_template =
        "I have a question about the following {{language}} code: ```{{filetype}}\n{{text_selection}}``` {{command_args}}",
        callback_type = "text_popup",
    },
    ["debug"] = {
        user_message_template =
        "Analyze the following {{language}} code for bugs: ```{{filetype}}\n{{text_selection}}```",
        callback_type = "text_popup",
    },
    ["doc"] = {
        user_message_template =
        "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nWrite really good documentation using best practices for the given language. Attention paid to documenting parameters, return types, any exceptions or errors. {{language_instructions}} Only return the code snippet and nothing else.",
        language_instructions = {
            ["*"] = "Use the standard documentation style (e.g. Docstrings, JSDoc, Doxygen) typical for {{language}}.",
        },
    },
    ["opt"] = {
        user_message_template =
        "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nOptimize this code. {{language_instructions}} Only return the code snippet and nothing else.",
        language_instructions = {
            ["*"] = "Use modern {{language}} syntax and best practices.",
        },
    },
    ["tests"] = {
        user_message_template =
        "I have the following {{language}} code: ```{{filetype}}\n{{text_selection}}```\nWrite really good unit tests using best practices for the given language. {{language_instructions}} Only return the unit tests. Only return the code snippet and nothing else. ",
        callback_type = "code_popup",
        language_instructions = {
            ["*"] = "Use modern {{language}} syntax. Generate unit tests using a standard testing framework appropriate for {{language}}.",
        },
    },
    ["chat"] = {
        user_message_template = "{{command_args}}",
        callback_type = "text_popup",
        allow_empty_text_selection = true,
    },
    ["search"] = {
        user_message_template = "{{command_args}}",
        system_message_template = "You are a helpful assistant. Use the web search tool to find up-to-date information to answer the user's query comprehensively.",
        callback_type = "text_popup",
        allow_empty_text_selection = true,
        is_search_command = true,
        loading_message = "Searching the web...",
    },
    ["clear"] = {
        allow_empty_text_selection = true,
    },
    ["recall"] = {
        allow_empty_text_selection = true,
    },
    ["last"] = {
        allow_empty_text_selection = true,
    },
    ["rewind"] = {
        allow_empty_text_selection = true,
    },
    ["undo"] = {
        allow_empty_text_selection = true,
    },
    ["help"] = {
        allow_empty_text_selection = true,
    },
}

-- Search Options
if vim.g["quickllm_show_search_sources"] == nil then
    vim.g["quickllm_show_search_sources"] = true
end

if vim.g["quickllm_ground_with_history"] == nil then
    vim.g["quickllm_ground_with_history"] = false
end

-- Popup commands
vim.g["quickllm_ui_commands"] = {
    quit = "q",
    use_as_output = "<c-o>",
    use_as_input = "<c-i>",
}

vim.g["quickllm_ui_custom_commands"] = {}
