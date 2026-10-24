-- Read-only metadata probes. No messages, phrase contents, input injection or hidden API calls.
local module={}
function module.new()
    local service=game:GetService("TextChatService")
    local RunService=game:GetService("RunService")
    local previous,ids={},setmetatable({}, {__mode="k"})
    local nextId,serial=0,0
    local connection,deadline,nextPoll
    local closed=false
    local last="DIAG ready"
    local polls,changes=0,0
    local controller={}
    local function short(value)
        return tostring(value):gsub("[\r\n]"," "):sub(1,180)
    end
    local function ref(object)
        if not ids[object] then nextId+=1;ids[object]=nextId end
        local ok,path=pcall(function() return object:GetFullName() end)
        return (ok and path or "<unreadable path>").." #"..ids[object]
    end
    local function valueText(value)
        if typeof(value)=="Instance" then return ref(value) end
        return short(value)
    end
    local function field(data,key,object,property)
        local ok,value=pcall(function() return object[property] end)
        data[key]=ok and valueText(value) or "UNAVAILABLE: "..short(value)
    end
    local function walk(root,limit,visit,data,label)
        local queue={root}
        local head,count=1,0
        local truncated=false
        while head<=#queue and count<limit do
            local object=queue[head];head+=1;count+=1
            local visited,why=pcall(visit,object)
            if not visited then data[label..".visitError"]=short(why) end
            local ok,children=pcall(function() return object:GetChildren() end)
            if ok then
                for _,child in ipairs(children) do
                    if #queue>=limit then truncated=true;break end
                    table.insert(queue,child)
                end
            else data[label..".accessError"]=short(children) end
        end
        data[label..".scan"]=tostring(count).." nodes"..(truncated and " (TRUNCATED)" or "")
    end
    local function collect(deep)
        local data={}
        for _,property in ipairs({"PlatformIntegratedChat","ChatVersion","CreateDefaultTextChannels"}) do
            field(data,"service."..property,service,property)
        end
        local player=game:GetService("Players").LocalPlayer
        local function channel(object)
            local key="channel."..ref(object)
            field(data,key..".ClassName",object,"ClassName")
            if object.Name=="RBXSystem" then data[key..".role"]="system (not a send target)" end
            for _,source in ipairs(object:GetChildren()) do
                if source:IsA("TextSource") then
                    local ok,userId=pcall(function() return source.UserId end)
                    if ok and player and userId==player.UserId then field(data,key..".own.CanSend",source,"CanSend") end
                end
            end
        end
        walk(service,256,function(object)
            if object:IsA("TextChannel") then channel(object)
            elseif object:IsA("ChatInputBarConfiguration") then
                field(data,"input."..ref(object)..".TargetTextChannel",object,"TargetTextChannel")
                field(data,"input."..ref(object)..".Enabled",object,"Enabled")
                field(data,"input."..ref(object)..".IsFocused",object,"IsFocused")
            elseif object:IsA("ChatWindowConfiguration") or object:IsA("ChannelTabsConfiguration") then
                field(data,"config."..ref(object)..".Enabled",object,"Enabled")
            end
        end,data,"TextChatService")
        if deep then
            local function ui(object)
                if object:IsA("TextChannel") then channel(object) end
                if object:IsA("TextChannelWindow") then
                    field(data,"window."..ref(object)..".Target",object,"Target")
                    field(data,"window."..ref(object)..".Visible",object,"Visible")
                elseif object:IsA("TextButton") or object:IsA("TextLabel") then
                    local name=object.Name:lower()
                    -- Restrict text reads to tab/channel controls, not chat message labels.
                    if name:find("tab",1,true) or name:find("channel",1,true) or name:find("global",1,true) or name:find("friend",1,true) then
                        local ok,text=pcall(function() return object.Text end)
                        local lower=ok and text:lower() or ""
                        local labels={global=true,localchat=true,["local"]=true,friends=true,friend=true,here=true,
                            ["global chat"]=true,["friends chat"]=true,["グローバル"]=true,["ローカル"]=true,["フレンド"]=true}
                        local normalized=lower:gsub("^%s+",""):gsub("%s+$",""):gsub("%s*%(%d+%)$","")
                        if labels[normalized] and not name:find("message",1,true) then
                            local key="tab."..ref(object)
                            data[key..".label"]=short(text)
                            field(data,key..".Visible",object,"Visible")
                            data[key..".evidence"]="UI label only; no send route confirmed"
                        end
                    end
                end
            end
            local gui=player and player:FindFirstChildOfClass("PlayerGui")
            if gui then walk(gui,800,ui,data,"PlayerGui") end
            local ok,core=pcall(function() return game:GetService("CoreGui") end)
            if ok then walk(core,1600,ui,data,"CoreGui") else data["CoreGui.accessError"]=short(core) end
        end
        return data
    end
    local function dump(label,deep,quiet)
        if closed then return end
        local ok,data=pcall(collect,deep)
        if not ok then last="DIAG error";warn("[AutoChat DIAG] "..short(data));return end
        local mode=deep and "full" or "light"
        local before=previous[mode]
        local keys={}
        for key in pairs(data) do table.insert(keys,key) end
        if before then for key in pairs(before) do if data[key]==nil then table.insert(keys,key) end end end
        table.sort(keys)
        local lines={}
        for _,key in ipairs(keys) do
            if not before then table.insert(lines,"BASE "..key.." = "..data[key])
            elseif before[key]~=data[key] then
                table.insert(lines,(data[key]==nil and "REMOVED " or before[key]==nil and "ADDED " or "CHANGED ")..key
                    ..": "..tostring(before[key]).." -> "..tostring(data[key]))
            end
        end
        previous[mode]=data
        serial+=1;last="DIAG #"..serial.." "..mode..": "..#lines.." "..(before and "changes" or "baseline fields")
        if not quiet or #lines>0 then
            warn("[AutoChat DIAG] BEGIN #"..serial.." "..label.." ("..mode..")")
            for _,line in ipairs(lines) do warn("[AutoChat DIAG] "..line) end
            if #lines==0 then warn("[AutoChat DIAG] NO METADATA CHANGE") end
            warn("[AutoChat DIAG] END #"..serial)
        end
        return #lines
    end
    function controller.capture(label) return dump(label or "manual SNAP/DIFF",true,false) end
    function controller.stopWatch(reason)
        if connection then
            connection:Disconnect();connection=nil
            warn(string.format("[AutoChat DIAG] WATCH stopped (%s): %d polls, %d changed polls",reason or "button",polls,changes))
        end
    end
    function controller.watch()
        if closed then return end
        if connection then controller.stopWatch("button");return end
        deadline=os.clock()+60;nextPoll=os.clock()+1;polls,changes=0,0
        dump("WATCH start: switch Local/Global/Friends now",false,false)
        connection=RunService.Heartbeat:Connect(function()
            local now=os.clock()
            if now>=deadline then controller.stopWatch("60s complete");return end
            if now<nextPoll then return end
            nextPoll=now+1;polls+=1
            local n=dump("WATCH",false,true)
            if n and n>0 then changes+=1 end
        end)
        warn("[AutoChat DIAG] WATCH 60s; one lightweight sample/second. No chat is sent by diagnostics.")
    end
    function controller.watching() return connection~=nil end
    function controller.status() return last end
    function controller.destroy()
        if closed then return end
        controller.stopWatch("closed");closed=true;table.clear(previous);table.clear(ids)
    end
    dump("startup",false,false)
    return controller
end
return module
