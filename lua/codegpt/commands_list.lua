local Utils = require("codegpt.utils")
local Ui = require("codegpt.ui")

local CommandsList = {}
local cmd_default = {
    temperature = 0.8,
    number_of_choices = 1,
    system_message_template = "You are a {{language}} coding assistant.",
    user_message_template = "",
    callback_type = "replace_lines",
    allow_empty_text_selection = false,
    extra_params = {}, -- extra parameters sent to the API
}

local provider_defaults = {
    openai = {
        model = "gpt-5-nano",
        reasoning = { effort = "medium" },
    },
    ollama = {
        model = "qwen3:8b",
    },
    anthropic = {
        model = "claude-haiku-4-5",
        max_tokens = 4096,
    },
    gemini = {
        -- model = "gemini-2.5-flash",
        model = "gemini-3-pro-preview",

    },
    groq = {
        model = "mixtral-8x7b-32768",
    },
}

CommandsList.CallbackTypes = {
    ["text_popup"] = function(lines, bufnr, start_row, start_col, end_row, end_col)
        local popup_filetype = vim.g["codegpt_text_popup_filetype"]
        Ui.popup(lines, popup_filetype, bufnr, start_row, start_col, end_row, end_col)
    end,
    ["code_popup"] = function(lines, bufnr, start_row, start_col, end_row, end_col)
        lines = Utils.trim_to_code_block(lines)
        Utils.fix_indentation(bufnr, start_row, end_row, lines)
        Ui.popup(lines, Utils.get_filetype(), bufnr, start_row, start_col, end_row, end_col)
    end,
    ["replace_lines"] = function(lines, bufnr, start_row, start_col, end_row, end_col)
        lines = Utils.trim_to_code_block(lines)
        lines = Utils.remove_trailing_whitespace(lines)
        Utils.fix_indentation(bufnr, start_row, end_row, lines)
        if vim.api.nvim_buf_is_valid(bufnr) == true then
            Utils.replace_lines(lines, bufnr, start_row, start_col, end_row, end_col)
        else
            -- if the buffer is not valid, open a popup. This can happen when the user closes the previous popup window before the request is finished.
            Ui.popup(lines, Utils.get_filetype(), bufnr, start_row, start_col, end_row, end_col)
        end
    end,
    ["custom"] = nil,
}

function CommandsList.get_cmd_opts(cmd)
    -- Start with hardcoded defaults for all commands
    local opts = vim.deepcopy(cmd_default)

    -- Merge provider defaults
    local provider_name = string.lower(vim.g.codegpt_api_provider or "openai")
    if provider_defaults[provider_name] then
        opts = vim.tbl_extend("force", opts, provider_defaults[provider_name])
    end

    -- Merge the user's global defaults, if they exist
    if vim.g["codegpt_global_commands_defaults"] ~= nil then
        opts = vim.tbl_extend("force", opts, vim.g["codegpt_global_commands_defaults"])
    end

    -- Get settings from default commands and user-defined commands
    local default_cmd_opts = vim.g["codegpt_commands_defaults"][cmd]
    local user_cmd_opts = (vim.g["codegpt_commands"] or {})[cmd]

    -- A command must exist in one of the tables
    if default_cmd_opts == nil and user_cmd_opts == nil then
        return nil
    end

    -- Merge settings, with user settings taking precedence
    if default_cmd_opts ~= nil then
        opts = vim.tbl_extend("force", opts, default_cmd_opts)
    end
    if user_cmd_opts ~= nil then
        opts = vim.tbl_extend("force", opts, user_cmd_opts)
    end

    -- Model is configured?
    if opts.model == nil or opts.model == "" then
        vim.notify(
            "CodeGPT.vim: Model not configured for command '"
                .. cmd
                .. "'. Please set it in vim.g.codegpt_commands or vim.g.codegpt_global_commands_defaults",
            vim.log.levels.ERROR
        )
        return nil
    end

    -- Callback function
    if opts.callback_type == "custom" then
        if type(opts.callback) ~= "function" then
            vim.notify("Custom callback for command '" .. cmd .. "' is not a function.", vim.log.levels.ERROR)
            return nil
        end
    else
        opts.callback = CommandsList.CallbackTypes[opts.callback_type]
    end
    -- print("--- CodeGPT.vim Debug: Loaded model -> " .. opts.model .. " ---")
    -- vim.notiry is less intrusive than print
    vim.notify("LLM Model -> " .. opts.model, vim.log.levels.INFO, { title = "CodeGPT.vim" })
    return opts
end

return CommandsList
