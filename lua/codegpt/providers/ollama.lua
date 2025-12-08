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

OllaMaProvider.has_streaming = true

function OllaMaProvider.make_call(payload, user_message_text, cb, bufnr)
    local url = vim.g["codegpt_ollama_url"] or "http://127.0.0.1:11434/api/chat"
    local headers = OllaMaProvider.make_headers()
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
                
                if not chunk then 
                    return 
                end

                -- Process synchronously (off-main-thread)
                partial_data = partial_data .. chunk
                
                local current_buffer = partial_data
                local processed_segment_end = 0

                while true do
                    -- Find the start of a JSON object
                    local json_start_idx = string.find(current_buffer, "{", processed_segment_end + 1, true)
                    
                    if not json_start_idx then break end

                    -- Find the matching '}' for the JSON object
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

                    if json_end_idx == -1 then
                        -- Incomplete JSON object, leave it in partial_data for the next chunk
                        break
                    end

                    local json_str = string.sub(current_buffer, json_start_idx, json_end_idx)
                    processed_segment_end = json_end_idx

                    local ok, json = pcall(vim.json.decode, json_str)
                    if ok and json and json.message then
                        local content = json.message.content
                        if content and content ~= "" then
                            full_text = full_text .. content
                            cb.on_chunk(content)
                        end
                    end
                end
                
                partial_data = string.sub(current_buffer, processed_segment_end + 1)
            end,
            callback = function(response)
                -- Final callback when stream ends
                vim.schedule(function()
                    -- Process any remaining data in partial_data
                    if partial_data and partial_data ~= "" then
                        local ok, json = pcall(vim.json.decode, partial_data)
                        if ok and json and json.message and json.message.content then
                            local text_fragment = json.message.content
                            full_text = full_text .. text_fragment
                            cb.on_chunk(text_fragment)
                        end
                    end

                    if response.status ~= 200 then
                         local error_msg = "Error: " .. response.status .. " " .. (response.body or "")
                         cb.on_error(error_msg)
                    else
                         cb.on_complete(full_text)
                    end
                    Api.run_finished_hook()
                end)
            end,
            on_error = function(err)
                print('Curl error:', err.message)
                cb.on_error(err.message)
                Api.run_finished_hook()
            end,
        })
    else
        -- Legacy / Blocking Mode
        payload.stream = false
        local payload_str = vim.fn.json_encode(payload)
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
end

return OllaMaProvider
