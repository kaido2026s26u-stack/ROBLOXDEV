-- Discover exposed TextChannels only; never invent a Global/Friends route.
local module={}
function module.availability(channel)
    local service=game:GetService("TextChatService")
    if not channel:IsA("TextChannel") or not channel:IsDescendantOf(service) then return false,"Unavailable" end
    if channel.Name=="RBXSystem" then return false,"System channel" end
    local player=game:GetService("Players").LocalPlayer
    for _,source in ipairs(channel:GetChildren()) do
        if source:IsA("TextSource") and player and source.UserId==player.UserId then
            return source.CanSend,source.CanSend and "Ready" or "Read only"
        end
    end
    return nil,"Permission unconfirmed"
end
function module.discover()
    local channels={}
    for _,object in ipairs(game:GetService("TextChatService"):GetDescendants()) do
        if object:IsA("TextChannel") and object.Name~="RBXSystem" then
            table.insert(channels,object)
        end
    end
    table.sort(channels,function(a,b) return a.Name<b.Name end)
    return channels
end
function module.send(text,channel)
    local allowed,why=module.availability(channel)
    if allowed==false then return false,channel.Name..": "..why end
    local message=channel:SendAsync(text)
    if not message then return false,channel.Name..": no SendAsync status." end
    local status=message.Status
    if status==Enum.TextChatMessageStatus.Success then
        return true,channel.Name..": API Success; delivery unverified",status
    end
    return false,channel.Name..": "..tostring(status),status
end
return module

