local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

AzureProvider = {}



function AzureProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
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
        max_tokens = cmd_opts.max_tokens,
        messages = messages_for_api,
    }

    return request, new_user_message_text
end

function AzureProvider.make_headers()
    local token = vim.g["codegpt_openai_api_key"]
    if not token then
        error(
            "OpenAIApi Key not found, set in vim with 'codegpt_openai_api_key' or as the env variable 'OPENAI_API_KEY'"
        )
    end

    return { Content_Type = "application/json", ["api-key"] = token }
end

function AzureProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.error then
        print("Error: " .. json.error.message)
    end

    if not json.choices or 0 == #json.choices or not json.choices[1].message then
        print("Error: " .. vim.fn.json_encode(json))
        return
    end

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

function AzureProvider.make_call(payload, user_message_text, cb, bufnr)
    local payload_str = vim.fn.json_encode(payload)
    local url = vim.g["codegpt_chat_completions_url"]
    local headers = AzureProvider.make_headers()
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

return AzureProvider
