-- Compatibility entry: existing Utilities.lua URLs now start RXDEV.
-- RXDEV v1.0.0. All modules come from one immutable release commit.
local BASE = "https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/23f076f811a8b32062d89abe7c695c610d9c19de/rxdev/v1.0.0/"
local ok, result = pcall(function()
    local chunk, why = loadstring(game:HttpGet(BASE .. "Loader.lua"), "RXDEV_Loader")
    assert(chunk, why)
    local loader = chunk()
    assert(type(loader)=="table" and type(loader.new)=="function", "Invalid RXDEV loader")
    local modules = loader.new(BASE)
    local config = modules.get("Manifest")
    assert(config.version=="1.0.0", "RXDEV release version mismatch")
    modules.configure(config.modules)
    return modules.get("App").start(modules.get, config)
end)
if not ok then warn("[RXDEV v1.0.0] " .. tostring(result));return end
return result
