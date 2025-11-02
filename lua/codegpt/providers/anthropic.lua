local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

AnthropicProvider = {}

function AnthropicProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    local past_messages = History.get_messages(bufnr)
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)
    local messages_for_api = {}
    for _, msg in ipairs(past_messages) do
        table.insert(messages_for_api, msg)
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    local request = {
        temperature = cmd_opts.temperature or 1.0,
        max_tokens = cmd_opts.max_tokens,
        model = cmd_opts.model,
        system = system_message,
        messages = messages_for_api,
    }

    return request, new_user_message_text
end

function AnthropicProvider.make_headers()
    local api_key = vim.g["codegpt_anthropic_api_key"] or os.getenv("ANTHROPIC_API_KEY")

    if not api_key then
        error(
            "Anthropic API Key not found, set in vim with 'codegpt_anthropic_api_key' or as the env variable 'ANTHROPIC_API_KEY'"
        )
    end

    return {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_key,
        ["anthropic-version"] = "2023-06-01",
    }
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
        AnthropicProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end


function AnthropicProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.error then
        print("Error: " .. json.error.message)
    elseif json.stop_reason ~= "end_turn" then
        print("Response is incomplete. Payload: " .. vim.fn.json_encode(json))
    else
        if json.content[1] ~= nil then
            local response_text = json.content[1].text

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
                print("Error: No completion")
            end
        else
            print("Error: No completion")
        end
    end
end

function AnthropicProvider.make_call(payload, user_message_text, cb, bufnr)
    local payload_str = vim.fn.json_encode(payload)
    local url = "https://api.anthropic.com/v1/messages"
    local headers = AnthropicProvider.make_headers()
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

return AnthropicProvider
