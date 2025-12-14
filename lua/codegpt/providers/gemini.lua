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
        if msg.content and vim.trim(msg.content) ~= "" then
            table.insert(messages_for_api, {
                role = role,
                parts = { { text = msg.content } },
            })
        end
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

GeminiProvider.has_streaming = true

function GeminiProvider.make_call(payload, user_message_text, cb, bufnr)
    local model_name = payload.model
    if not model_name or model_name == "" then
        print("Error: Gemini provider requires a model to be configured for the command.")
        Api.run_finished_hook()
        return
    end
    payload.model = nil -- remove model from payload
    local payload_str = vim.fn.json_encode(payload)
    
    local headers = GeminiProvider.make_headers()
    Api.run_started_hook()

    if type(cb) == "table" then
        -- Streaming Mode
        local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model_name .. ":streamGenerateContent?alt=sse"
        
        local partial_data = ""
        local full_text = ""

        local function parse_chunk_line(line)
            local trimmed_line = vim.trim(line)
            if vim.startswith(trimmed_line, "data:") then
                local json_str = vim.trim(string.sub(trimmed_line, 6)) -- remove "data:"
                if json_str ~= "[DONE]" then
                    local ok, json = pcall(vim.json.decode, json_str) 
                    if not ok then
                        return nil, nil
                    end

                    if json.error then
                        return nil, json.error.message or "Unknown Gemini API Error"
                    end

                    if json and json.candidates and json.candidates[1] then
                         local candidate = json.candidates[1]
                         if candidate.content and candidate.content.parts and candidate.content.parts[1] then
                             return candidate.content.parts[1].text, nil
                         elseif candidate.finishReason and candidate.finishReason ~= "STOP" then
                             return nil, "Gemini Stopped: " .. candidate.finishReason
                         end
                    end
                end
            end
            return nil, nil
        end

        curl.post(url, {
            body = payload_str,
            headers = headers,
            raw = { "--no-buffer" },
            timeout = 20000, -- 20 seconds timeout
            stream = function(err, chunk)
                if err then
                    vim.schedule(function() 
                        cb.on_error(err) 
                        Api.run_finished_hook()
                    end)
                    return
                end
                
                if not chunk then 
                    -- End of stream: Flush remaining partial data
                    vim.schedule(function()
                         if partial_data and partial_data ~= "" then
                            local text_fragment, err_msg = parse_chunk_line(partial_data)
                            if err_msg then
                                 cb.on_error(err_msg)
                            elseif text_fragment then
                                full_text = full_text .. text_fragment
                                cb.on_chunk(text_fragment)
                            end
                        end
                        cb.on_complete(full_text)
                        Api.run_finished_hook()
                    end)
                    return 
                end

                partial_data = partial_data .. chunk

                local current_buffer = partial_data -- Work on a mutable copy
                local processed_segment_end = 0

                while true do
                    local data_start_idx = string.find(current_buffer, "data: ", processed_segment_end + 1, true)
                    if not data_start_idx then break end

                    local json_start_idx = data_start_idx + string.len("data: ")

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
                    processed_segment_end = json_end_idx -- Move processed_segment_end to the end of this JSON object

                    if json_str == "[DONE]" then
                        -- This is typically the last message, but for robustness we still process
                        -- parse_chunk_line will handle this correctly
                    end

                    -- Process the extracted JSON string
                    local line_to_parse = "data: " .. json_str -- Re-add data: for parse_chunk_line
                    local text_fragment, err_msg = parse_chunk_line(line_to_parse)

                    if err_msg then
                        vim.schedule(function() cb.on_error(err_msg) end)
                    elseif text_fragment then
                        full_text = full_text .. text_fragment
                        cb.on_chunk(text_fragment)
                    end

                    -- After processing a JSON object, check for and skip any immediate trailing newlines
                    local next_char_idx = processed_segment_end + 1
                    while next_char_idx <= #current_buffer and string.sub(current_buffer, next_char_idx, next_char_idx) == "\n" do
                        processed_segment_end = next_char_idx
                        next_char_idx = next_char_idx + 1
                    end
                end

                -- Update partial_data with any remaining unprocessed part
                partial_data = string.sub(current_buffer, processed_segment_end + 1)
            end,
            on_error = function(err)
                print('Curl error:', err.message)
                cb.on_error(err.message)
                Api.run_finished_hook()
            end,
        })

    else
        -- Legacy / Blocking Mode
        local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model_name .. ":generateContent"
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

return GeminiProvider
