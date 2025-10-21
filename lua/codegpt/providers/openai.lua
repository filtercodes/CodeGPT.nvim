local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")

OpenAIProvider = {}

function OpenAIProvider.make_request(command, cmd_opts, command_args, text_selection)
    local user_message = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    local request = {
        model = cmd_opts.model,
        input = user_message,
        reasoning = cmd_opts.reasoning,
    }

    request = vim.tbl_extend("force", request, cmd_opts.extra_params)
    return request
end

local function curl_callback(response, cb)
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
        OpenAIProvider.handle_response(json, cb)
    end)(body)

    -- Api.run_finished_hook()
end

function OpenAIProvider.make_headers()
    local token = vim.g["codegpt_openai_api_key"]
    if not token then
        error(
            "OpenAIApi Key not found, set in vim with 'codegpt_openai_api_key' or as the env variable 'OPENAI_API_KEY'"
        )
    end

    return { ["Content-Type"] = "application/json", Authorization = "Bearer " .. token, ["User-Agent"] = "CodeGPT-Lua" }
end

function OpenAIProvider.handle_response(json, cb)
    if json == nil then
        print("Response empty")

    -- FIX: Check if json.error is a REAL error, not just 'null'
    elseif json.error and json.error ~= vim.NIL then
        if type(json.error) == "table" and json.error.message then
            print("Error: " .. json.error.message)
        else
            print("Error: " .. tostring(json.error))
        end

    -- No real error, so now we process the output
    else
        local response_text
        if json.output and json.output[2] and json.output[2].content and json.output[2].content[1] and json.output[2].content[1].text then
            response_text = json.output[2].content[1].text
        else
            print("Error: Unexpected GPT-5 response format: " .. vim.fn.json_encode(json))
            return
        end

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
            else
                local bufnr = vim.api.nvim_get_current_buf()
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

function OpenAIProvider.make_call(payload, cb)
    local url = "https://api.openai.com/v1/responses"
    local payload_str = vim.fn.json_encode(payload)
    local headers = OpenAIProvider.make_headers()

    headers["Content-Length"] = #payload_str

    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        callback = function(response)
            curl_callback(response, cb)
        end,
        on_error = function(err)
            print('Error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return OpenAIProvider
