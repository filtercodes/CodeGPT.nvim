local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

OllaMaProvider = {}


function OllaMaProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    -- Get the history of past messages
    local past_messages = History.get_messages(bufnr)

    -- Render the new user message
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    -- Render the system message
    local system_message_text = Render.render(command, cmd_opts.system_message_template, command_args, text_selection, cmd_opts)

    -- Construct the payload for the request
    local messages_for_api = {}
    if system_message_text and system_message_text ~= "" then
        table.insert(messages_for_api, {role="system", content=system_message_text})
    end
    for _, msg in ipairs(past_messages) do
        table.insert(messages_for_api, msg)
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    -- Request object
    local request = {
        temperature = cmd_opts.temperature,
        model = cmd_opts.model,
        messages = messages_for_api,
        stream = false,
    }

    return request, new_user_message_text
end

function OllaMaProvider.make_headers()
    return { ["Content-Type"] = "application/json" }
end

function OllaMaProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.done == nil or json.done == false then
        print("Response is incomplete " .. vim.fn.json_encode(json))
    elseif json.message == nil or json.message.content == nil then
        print("Error: No response content. Full response: " .. vim.fn.json_encode(json))
    else
        local response_text = json.message.content

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
            else
                -- Add both user and assistant messages to history at the same time
                History.add_message(bufnr, "user", user_message_text)
                History.add_message(bufnr, "assistant", response_text)

                if vim.g["codegpt_clear_visual_selection"] then
                    vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                    vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                end
                cb(Utils.parse_lines(response_text))
            end
        else
            print("Error: No text")
        end
    end
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
        OllaMaProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end

function OllaMaProvider.make_call(payload, user_message_text, cb, bufnr)
    local payload_str = vim.fn.json_encode(payload)
    local url = vim.g["codegpt_ollama_url"] or "http://localhost:11434/api/chat"
    local headers = OllaMaProvider.make_headers()
    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        callback = function(response)
            curl_callback(response, user_message_text, cb, bufnr)
        end,
        on_error = function(err)
            print('Curl error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return OllaMaProvider
