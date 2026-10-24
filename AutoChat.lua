-- Standalone AutoChat v0.1.6. RXDEV itself is unchanged.
local BASE="https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/81a29889b1eed53c56ad9d6d85f9e2627fbafd4b/autochat/v0.1.6/"
local specs={Engine={"new","parse","validate"},RobloxChat={"discover","availability","send"},App={"mount"},Diagnostics={"new"},Storage={"new"},RouteProbe={"new"}}
local cache={}
local function get(name)
    assert(specs[name],"Unknown AutoChat module")
    if cache[name] then return cache[name] end
    local chunk,why=loadstring(game:HttpGet(BASE..name..".lua"),"AutoChat_"..name)
    assert(chunk,why)
    local value=chunk()
    assert(type(value)=="table","Invalid AutoChat module: "..name)
    for _,method in ipairs(specs[name]) do assert(type(value[method])=="function",name.."."..method.." missing") end
    cache[name]=value
    return value
end
local ok,result=pcall(function() return get("App").mount(get) end)
if not ok then warn("[AutoChat] Startup: "..tostring(result));return end
return result

