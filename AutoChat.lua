-- Standalone AutoChat v0.1.7. RXDEV itself is unchanged.
local BASE="https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/d01df3168c2e13ab61b4bc37cb9581f05cfdcdaa/autochat/v0.1.7/"
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

