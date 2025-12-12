local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

AnthropicProvider = {}

AnthropicProvider.has_streaming = true

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
        stream = true,
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


function AnthropicProvider.make_call(payload, user_message_text, cb, bufnr)
    local url = "https://api.anthropic.com/v1/messages"
    local headers = AnthropicProvider.make_headers()

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
                        if json.type == "error" then
                            vim.schedule(function() cb.on_error(json.error.message) end)
                        elseif json.type == "content_block_delta" and json.delta and json.delta.text then
                            local text = json.delta.text
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
        payload.stream = false
        local payload_str = vim.fn.json_encode(payload)
        curl.post(url, {
            body = payload_str,
            headers = headers,
            callback = function(response)
                vim.schedule(function()
                    if response.status ~= 200 then
                        print("Error: " .. response.status .. " " .. response.body)
                        Api.run_finished_hook()
                        return
                    end
                    local ok, json = pcall(vim.fn.json_decode, response.body)
                    if ok and json and json.content and json.content[1] and json.content[1].text then
                        local text = json.content[1].text
                        History.add_message(bufnr, "user", user_message_text)
                        History.add_message(bufnr, "assistant", text)
                        if vim.g["codegpt_clear_visual_selection"] then
                            vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                            vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                        end
                        cb(Utils.parse_lines(text))
                    else
                        print("Error parsing Anthropic response")
                    end
                    Api.run_finished_hook()
                end)
            end,
            on_error = function(err)
                print('Error:', err.message)
                Api.run_finished_hook()
            end,
        })
    end
end

return AnthropicProvider
