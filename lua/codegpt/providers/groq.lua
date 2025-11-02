local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

GroqProvider = {}

function GroqProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    local past_messages = History.get_messages(bufnr)
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)
    local system_message_text = Render.render(command, cmd_opts.system_message_template, command_args, text_selection, cmd_opts)
    local messages_for_api = {}
    if system_message_text and system_message_text ~= "" then
        table.insert(messages_for_api, {role="system", content=system_message_text})
    end
    for _, msg in ipairs(past_messages) do
        table.insert(messages_for_api, msg)
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    local request = {
        temperature = cmd_opts.temperature,
        n = cmd_opts.number_of_choices,
        model = cmd_opts.model,
        messages = messages_for_api,
        max_tokens = cmd_opts.max_tokens,
    }

    return request, new_user_message_text
end

local function curl_callback(response, user_message_text, cb, bufnr)
    local status = response.status
    local body = response.body
    if status ~= 200 then
        body = body:gsub("%s+", " ")
        print("Error: " .. status .. " " .. body)
        return
    end

    if body == nil or body == "" then
        print("Error: No body")
        return
    end

    vim.schedule_wrap(function(msg)
        local json = vim.fn.json_decode(msg)
        GroqProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end

function GroqProvider.make_headers()
    local token = vim.env["GROQ_API_KEY"]
    if not token then
        error(
            "GroqApi Key not found, set the env variable 'GROQ_API_KEY'"
        )
    end

    return { Content_Type = "application/json", Authorization = "Bearer " .. token }
end

function GroqProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.error then
        print("Error: " .. json.error.message)
    elseif not json.choices or 0 == #json.choices or not json.choices[1].message then
        print("Error: " .. vim.fn.json_encode(json))
    else
        local response_text = json.choices[1].message.content

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
            else
                History.add_message(bufnr, "user", user_message_text)
                History.add_message(bufnr, "assistant", response_text)

                if vim.g["codegpt_clear_visual_selection"] then
                    vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                    vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                end
                cb(Utils.parse_lines(response_text))
            end
        else
            print("Error: No message")
        end
    end
end

function GroqProvider.make_call(payload, user_message_text, cb, bufnr)
    local payload_str = vim.fn.json_encode(payload)
    local url = "https://api.groq.com/openai/v1/chat/completions"
    local headers = GroqProvider.make_headers()
    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        callback = function(response)
            curl_callback(response, user_message_text, cb, bufnr)
        end,
        on_error = function(err)
            print('Error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return GroqProvider
