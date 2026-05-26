local Utils = require("quickllm.utils")
local Ui = require("quickllm.ui")

local CommandsList = {}
local cmd_default = {
    temperature = 0.2,
    number_of_choices = 1,
    system_message_template = "You are a {{language}} coding assistant.",
    user_message_template = "",
    callback_type = "replace_lines",
    allow_empty_text_selection = false,
    extra_params = {}, -- extra parameters sent to the API
}

CommandsList.CallbackTypes = {
    ["text_popup"] = function(lines, bufnr, start_row, start_col, end_row, end_col)
        local popup_filetype = vim.g.quickllm_text_popup_filetype
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

function CommandsList.get_cmd_opts(cmd, overrides)
    -- Start with hardcoded defaults for all commands
    local opts = vim.deepcopy(cmd_default)

    local preset_suffix = (overrides and overrides.preset) and tostring(overrides.preset) or ""

    -- Resolve Provider Name
    local provider_name = (overrides and overrides.provider) 
        or vim.g["quickllm_api_provider" .. preset_suffix]
        or vim.g.quickllm_api_provider 
        or "openai"
    provider_name = string.lower(provider_name)

    -- Merge provider defaults (which already include the user's plugin.lua overrides via config.lua)
    local provider_defaults = vim.g.quickllm_provider_defaults or {}
    if provider_defaults[provider_name] then
        opts = vim.tbl_extend("force", opts, provider_defaults[provider_name])
    end

    -- Merge the user's generic global defaults (base or preset-specific)
    -- We do NOT want the global 'model' to overwrite the provider-specific model we just loaded,
    -- unless the user is intentionally overriding it for the generic default provider.
    local global_defaults_key = "quickllm_global_commands_defaults" .. preset_suffix
    if vim.g[global_defaults_key] ~= nil then
        local global_defaults = vim.deepcopy(vim.g[global_defaults_key])
        
        -- If an explicit provider was requested (e.g., :Gemini), strip the generic global model
        -- because we already applied the provider's specific model above.
        if overrides and (overrides.provider or overrides.search_provider) then
             global_defaults.model = nil
             global_defaults.search_model = nil
        end

        opts = vim.tbl_extend("force", opts, global_defaults)
    end

    -- Get settings from default commands and user-defined commands
    local default_cmd_opts = vim.g.quickllm_commands_defaults[cmd]
    local user_cmd_opts = (vim.g.quickllm_commands or {})[cmd]

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

    -- Handle decoupled search model logic
    if opts.is_search_command then
        local search_provider = (overrides and overrides.search_provider) 
            or vim.g["quickllm_search_provider" .. preset_suffix]
            or vim.g.quickllm_search_provider
            or "gemini"

        -- Get default search model settings for this provider
        local search_model_defaults = vim.g.quickllm_search_model_defaults or {}
        local provider_search_settings = search_model_defaults[search_provider] or {}
        local default_search_model = provider_search_settings.model

        -- Safely fetch generic global search model
        local global_search_model = vim.g["quickllm_search_model" .. preset_suffix] or vim.g.quickllm_search_model
        
        -- If an explicit provider was requested (e.g., :Gemini), strip the generic global search model
        -- because we must use the provider's specific search model we just loaded.
        if overrides and (overrides.provider or overrides.search_provider) then
             global_search_model = nil
             opts.search_model = nil
        end

        -- Resolution order:
        -- 1. Global user setting (`global_search_model`)
        -- 2. Command-specific `search_model` override
        -- 3. Provider specific default for search (`default_search_model`)
        opts.model = global_search_model or opts.search_model or default_search_model
    end

    -- Model is configured?
    if opts.model == nil or opts.model == "" then
        vim.notify(
            "QuickLLM.vim: Model not configured for command '"
                .. cmd
                .. "'. Please set it in vim.g.quickllm_commands or vim.g.quickllm_global_commands_defaults",
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
    
    return opts
end

return CommandsList
