local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

local GeminiProvider = {}

function GeminiProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    -- Get the history of past messages
    local past_messages = History.get_messages(bufnr)

    -- Render new user message
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    -- Payload
    local messages_for_api = {}
    for _, msg in ipairs(past_messages) do
        local role = (msg.role == "assistant" and "model" or "user")
        table.insert(messages_for_api, {
            role = role,
            parts = { { text = msg.content } },
        })
    end
    table.insert(messages_for_api, {
        role = "user",
        parts = { { text = new_user_message_text } },
    })

    -- Request object
    local request = {
        contents = messages_for_api,
        model = cmd_opts.model,
    }

    return request, new_user_message_text
end

function GeminiProvider.make_headers()
    local api_key = vim.g["codegpt_gemini_api_key"] or os.getenv("GEMINI_API_KEY")

    if not api_key then
        error(
            "Gemini API Key not found, set in vim with 'codegpt_gemini_api_key' or as the env variable 'GEMINI_API_KEY'"
        )
    end

    return {
        ["Content-Type"] = "application/json",
        ["x-goog-api-key"] = api_key,
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
        GeminiProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end


function GeminiProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        print("Response empty")
    elseif json.error then
        print("Error: " .. json.error.message)
    elseif not json.candidates or not json.candidates[1] then
        print("Response is incomplete. Payload: " .. vim.fn.json_encode(json))
    else
        if json.candidates[1].content and json.candidates[1].content.parts and json.candidates[1].content.parts[1] then
            local response_text = json.candidates[1].content.parts[1].text

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

function GeminiProvider.make_call(payload, user_message_text, cb, bufnr)
    local model_name = payload.model
    if not model_name or model_name == "" then
        print("Error: Gemini provider requires a model to be configured for the command.")
        Api.run_finished_hook()
        return
    end
    payload.model = nil -- remove model from payload
    local payload_str = vim.fn.json_encode(payload)
    -- Correct the URL to include the /v1beta path
    local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model_name .. ":generateContent"
    local headers = GeminiProvider.make_headers()
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

return GeminiProvider
