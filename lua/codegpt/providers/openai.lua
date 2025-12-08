local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

OpenAIProvider = {}

function OpenAIProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
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
        model = cmd_opts.model,
        messages = messages_for_api,
    }

    request = vim.tbl_extend("force", request, cmd_opts.extra_params)
    return request, new_user_message_text
end

local function curl_callback(response, user_message_text, cb, bufnr)
    local status = response.status
    local body = response.body

    if status ~= 200 then
        body = body:gsub("%s+", " ")
        print("Error: " .. status .. " " .. body)
        Api.run_finished_hook()
        return
    end

    if body == nil or body == "" then
        print("Error: No body")
        Api.run_finished_hook()
        return
    end

    vim.schedule_wrap(function(msg)
        local ok, json = pcall(vim.fn.json_decode, msg)
        if not ok or json == vim.NIL then
            print("Error: Failed to decode API response. Body was:")
            print(msg)
            Api.run_finished_hook()
            return
        end
        OpenAIProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end

function OpenAIProvider.make_headers()
    local token = vim.g["codegpt_openai_api_key"] or os.getenv("OPENAI_API_KEY")
    if not token then
        error(
            "OpenAIApi Key not found, set in vim with 'codegpt_openai_api_key' or as the env variable 'OPENAI_API_KEY'"
        )
    end

    return { ["Content-Type"] = "application/json", Authorization = "Bearer " .. token }
end

function OpenAIProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.error and json.error.message then
        print("Error: " .. json.error.message)
    elseif json.choices and json.choices[1] and json.choices[1].message then
        local response_text = json.choices[1].message.content
        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
            else
                -- Add history
                History.add_message(bufnr, "user", user_message_text)
                History.add_message(bufnr, "assistant", response_text)

                if vim.g["codegpt_clear_visual_selection"] then
                    vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                    vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                end
                cb(Utils.parse_lines(response_text))
            end
        else
            print("Error: No message in response")
        end
    else
        print("Error: Unexpected response format: " .. vim.fn.json_encode(json))
    end
end

function OpenAIProvider.make_call(payload, user_message_text, cb, bufnr)
    local url = vim.g["codegpt_chat_completions_url"]
    local payload_str = vim.fn.json_encode(payload)
    local headers = OpenAIProvider.make_headers()

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

return OpenAIProvider
