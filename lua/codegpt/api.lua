local curl = require("plenary.curl")

local Api = {}

CODEGPT_CALLBACK_COUNTER = 0

local status_index = 0
Api.progress_bar_dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

Api.last_model = ""
Api.last_command = ""

function Api.set_status(command, model)
    Api.last_command = command
    Api.last_model = model
end

function Api.get_status(...)
    local status = ""
    if CODEGPT_CALLBACK_COUNTER > 0 then
        status_index = status_index + 1
        if status_index > #Api.progress_bar_dots then
            status_index = 1
        end
        status = Api.progress_bar_dots[status_index]
    end

    if Api.last_model ~= "" then
        local model_info = string.format("%s  🤖 %s", Api.last_command, Api.last_model)
        if status ~= "" then
            status = status .. " " .. model_info
        else
            status = model_info
        end
    end

    return status
end

function Api.run_started_hook()
    if vim.g["codegpt_hooks"]["request_started"] ~= nil then
        vim.g["codegpt_hooks"]["request_started"]()
    end

    CODEGPT_CALLBACK_COUNTER = CODEGPT_CALLBACK_COUNTER + 1
end

function Api.run_finished_hook()
    CODEGPT_CALLBACK_COUNTER = CODEGPT_CALLBACK_COUNTER - 1
    if CODEGPT_CALLBACK_COUNTER <= 0 then
        if vim.g["codegpt_hooks"]["request_finished"] ~= nil then
            vim.g["codegpt_hooks"]["request_finished"]()
        end
    end
end


return Api
