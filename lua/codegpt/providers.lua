local OpenAIProvider = require("codegpt.providers.openai")
local AzureProvider = require("codegpt.providers.azure")
local AnthropicProvider = require("codegpt.providers.anthropic")
local OllaMaProvider = require("codegpt.providers.ollama")
local GroqProvider = require("codegpt.providers.groq")
local GeminiProvider = require("codegpt.providers.gemini")

Providers = {}

function Providers.get_provider()
    local provider = vim.fn.tolower(vim.g["codegpt_api_provider"])
    if provider == "openai" then
        return OpenAIProvider
    elseif provider == "azure" then
        return AzureProvider
    elseif provider == "anthropic" then
        return AnthropicProvider
    elseif provider == "ollama" then
        return OllaMaProvider
    elseif provider == "groq" then
        return GroqProvider
    elseif provider == "gemini" then
        return GeminiProvider
    else
        error("Provider not found: " .. provider)
    end
end

return Providers
