-- Standalone AutoChat v0.1.3. RXDEV itself is unchanged.
local BASE="https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/a62cbf93fc32a070de6db27ab342a41d0f3d59ed/autochat/v0.1.3/"
local specs={Engine={"new","parse","validate"},RobloxChat={"discover","availability","send"},App={"mount"},Diagnostics={"new"}}
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

