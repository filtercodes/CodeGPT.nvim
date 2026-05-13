-- add public vim commands
require("codegpt.config")
local CodeGptModule = require("codegpt")
local function create_command(name)
    vim.api.nvim_create_user_command(name, function(opts)
        opts.name = name
        return CodeGptModule.run_cmd(opts)
    end, {
        range = true,
        nargs = "*",
        complete = function()
            local cmd = {}
            for k in pairs(vim.g["codegpt_commands_defaults"]) do
                table.insert(cmd, k)
            end
            for k in pairs(vim.g["codegpt_commands"] or {}) do
                table.insert(cmd, k)
            end
            return cmd
        end,
    })
end

create_command("Chat")
create_command("Chat1")
create_command("Chat2")
create_command("Chat3")
create_command("Gemini")
create_command("Claude")
create_command("Openai")
create_command("Ollama")
create_command("Groq")

vim.api.nvim_create_user_command("CodeGPTStatus", function(opts)
	return CodeGptModule.get_status(opts)
end, {
	range = true,
	nargs = "*",
})
