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
        model = "deepseek-r1:7b",
    },
    anthropic = {
        model = "claude-haiku-4-5",
        max_tokens = 1000,
    },
    gemini = {
        model = "gemini-2.5-flash",
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
    -- 1. Start with the plugin's hardcoded defaults for all commands.
    local opts = vim.deepcopy(cmd_default)

    -- Merge provider defaults
    local provider_name = string.lower(vim.g.codegpt_api_provider or "openai")
    if provider_defaults[provider_name] then
        opts = vim.tbl_extend("force", opts, provider_defaults[provider_name])
    end

    -- 2. Merge the user's global defaults, if they exist.
    if vim.g["codegpt_global_commands_defaults"] ~= nil then
        opts = vim.tbl_extend("force", opts, vim.g["codegpt_global_commands_defaults"])
    end

    -- 3. Get settings from default commands and user-defined commands.
    local default_cmd_opts = vim.g["codegpt_commands_defaults"][cmd]
    local user_cmd_opts = (vim.g["codegpt_commands"] or {})[cmd]

    -- A command must exist in one of the tables.
    if default_cmd_opts == nil and user_cmd_opts == nil then
        return nil
    end

    -- 4. Merge settings, with user settings taking precedence.
    if default_cmd_opts ~= nil then
        opts = vim.tbl_extend("force", opts, default_cmd_opts)
    end
    if user_cmd_opts ~= nil then
        opts = vim.tbl_extend("force", opts, user_cmd_opts)
    end

    -- 5. Ensure a model is configured.
    if opts.model == nil or opts.model == "" then
        vim.notify(
            "CodeGPT: Model not configured for command '"
                .. cmd
                .. "'. Please set it in vim.g.codegpt_commands or vim.g.codegpt_global_commands_defaults",
            vim.log.levels.ERROR
        )
        return nil
    end

    -- 6. Set the correct callback function.
    if opts.callback_type == "custom" then
        -- The callback function should have been defined in the user's config.
        -- It's already in `opts` if defined. We just need to ensure it's a function.
        if type(opts.callback) ~= "function" then
            vim.notify("Custom callback for command '" .. cmd .. "' is not a function.", vim.log.levels.ERROR)
            return nil
        end
    else
        opts.callback = CommandsList.CallbackTypes[opts.callback_type]
    end
    print("--- CodeGPT Debug: Loaded model -> " .. opts.model .. " ---")
    return opts
end

return CommandsList
