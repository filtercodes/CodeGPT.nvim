vim.g["codegpt_chat_completions_url"] = "https://api.openai.com/v1/chat/completions"

-- Read old config if it exists
if vim.g["codegpt_openai_api_provider"] and #vim.g["codegpt_openai_api_provider"] > 0 then
    vim.g["codegpt_api_provider"] = vim.g["codegpt_openai_api_provider"]
end

-- Alternative provider
vim.g["codegpt_api_provider"] = vim.g["codegpt_api_provider"] or "openai"

-- Clears visual selection after completion
vim.g["codegpt_clear_visual_selection"] = true

-- Ensure user commands table exists
vim.g["codegpt_commands"] = vim.g["codegpt_commands"] or {}

vim.g["codegpt_hooks"] = {
    request_started = nil,
    request_finished = nil,
}

-- Border style to use for the popup
vim.g["codegpt_popup_border"] = { style = "rounded" }

-- Wraps the text on the popup window, deprecated in favor of codegpt_popup_window_options
vim.g["codegpt_wrap_popup_text"] = true

vim.g["codegpt_popup_window_options"] = {}

-- Set the filetype of a text popup is markdown
vim.g["codegpt_text_popup_filetype"] = "markdown"

-- Set the type of ui to use for the popup, options are "popup", "vertical" or "horizontal"
vim.g["codegpt_popup_type"] = "popup"

-- Set the height of the horizontal popup
vim.g["codegpt_horizontal_popup_size"] = "20%"

-- Set the width of the vertical popup
vim.g["codegpt_vertical_popup_size"] = "20%"

-- Set timeout for chat history
if vim.g["codegpt_chat_history_timeout"] == nil then
    vim.g["codegpt_chat_history_timeout"] = 900
end

-- Set if the chat history should expire based on time
if vim.g["codegpt_chat_history_time_based_expiry"] == nil then
    vim.g["codegpt_chat_history_time_based_expiry"] = true
end

-- Set max messages for chat history
if vim.g["codegpt_chat_history_max_messages"] == nil then
    vim.g["codegpt_chat_history_max_messages"] = 20
end

vim.g["codegpt_commands_defaults"] = {
    ["completion"] = {
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
    ["code_edit"] = {
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

if vim.g["codegpt_show_search_sources"] == nil then
    vim.g["codegpt_show_search_sources"] = true
end

if vim.g["codegpt_ground_with_history"] == nil then
    vim.g["codegpt_ground_with_history"] = false
end

-- Popup commands
vim.g["codegpt_ui_commands"] = {
    quit = "q",
    use_as_output = "<c-o>",
    use_as_input = "<c-i>",
}
vim.g["codegpt_ui_custom_commands"] = {}
