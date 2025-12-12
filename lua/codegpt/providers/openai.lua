local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

OpenAIProvider = {}

OpenAIProvider.has_streaming = true

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
    local headers = OpenAIProvider.make_headers()

    Api.run_started_hook()

    if type(cb) == "table" then
        -- Streaming Mode
        payload.stream = true
        local payload_str = vim.fn.json_encode(payload)
        local partial_data = ""
        local full_text = ""

        curl.post(url, {
            body = payload_str,
            headers = headers,
            raw = { "--no-buffer" },
            stream = function(err, chunk)
                if err then
                    vim.schedule(function() cb.on_error(err) end)
                    return
                end
                if not chunk then return end

                partial_data = partial_data .. chunk
                local current_buffer = partial_data
                local processed_segment_end = 0

                while true do
                    local data_start_idx = string.find(current_buffer, "data: ", processed_segment_end + 1, true)
                    if not data_start_idx then break end

                    local json_start_idx = data_start_idx + string.len("data: ")

                    -- Check for [DONE]
                    if string.sub(current_buffer, json_start_idx, json_start_idx + 5) == "[DONE]" then
                        processed_segment_end = json_start_idx + 6
                        break
                    end

                    -- Find matching braces for JSON
                    local brace_level = 0
                    local json_end_idx = -1
                    for i = json_start_idx, #current_buffer do
                        local char = string.sub(current_buffer, i, i)
                        if char == "{" then
                            brace_level = brace_level + 1
                        elseif char == "}" then
                            brace_level = brace_level - 1
                        end
                        if brace_level == 0 and char == "}" then
                            json_end_idx = i
                            break
                        end
                    end

                    if json_end_idx == -1 then break end -- Incomplete JSON

                    local json_str = string.sub(current_buffer, json_start_idx, json_end_idx)
                    processed_segment_end = json_end_idx

                    local ok, json = pcall(vim.json.decode, json_str)
                    if ok and json then
                        if json.error then
                            vim.schedule(function() cb.on_error(json.error.message) end)
                        elseif json.choices and json.choices[1] and json.choices[1].delta and json.choices[1].delta.content then
                            local text = json.choices[1].delta.content
                            full_text = full_text .. text
                            cb.on_chunk(text)
                        end
                    end
                end

                partial_data = string.sub(current_buffer, processed_segment_end + 1)
            end,
            callback = function(response)
                vim.schedule(function()
                    if response.status ~= 200 then
                        cb.on_error("Error: " .. response.status)
                    else
                        cb.on_complete(full_text)
                    end
                    Api.run_finished_hook()
                end)
            end,
            on_error = function(err)
                cb.on_error(err.message)
                Api.run_finished_hook()
            end
        })
    else
        -- Legacy Mode
        local payload_str = vim.fn.json_encode(payload)
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
end

return OpenAIProvider
