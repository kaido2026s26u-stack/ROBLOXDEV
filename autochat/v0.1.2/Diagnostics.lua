-- Temporary one-button investigation. Read metadata, finish, report and disconnect.
local module={}
function module.new()
    local service=game:GetService("TextChatService")
    local RunService=game:GetService("RunService")
    local player=game:GetService("Players").LocalPlayer
    local connection,job
    local closed,serial=false,0
    local last="調査待ち"
    local controller={}
    local MAX_NODES,MAX_SECONDS=25000,20
    local TAB_LABELS={global=true,["global chat"]=true,["local"]=true,here=true,
        friends=true,friend=true,["friends chat"]=true,["グローバル"]=true,["ローカル"]=true,["フレンド"]=true}
    local function short(value)
        return (tostring(value):gsub("[\r\n]"," ")):sub(1,180)
    end
    local function path(object)
        local ok,value=pcall(function() return object:GetFullName() end)
        return ok and short(value) or "<path unavailable>"
    end
    local function read(object,key)
        local ok,value=pcall(function() return object[key] end)
        if not ok then return "UNAVAILABLE: "..short(value) end
        if typeof(value)=="Instance" then return path(value) end
        return short(value)
    end
    local function noteError(where,why)
        job.errorCount+=1
        if #job.errors<6 then table.insert(job.errors,where..": "..short(why)) end
    end
    local function priority(object)
        local ok,name=pcall(function() return object.Name:lower() end)
        if not ok then return 0 end
        if name:find("chat",1,true) then return 100 end
        if name:find("channel",1,true) then return 90 end
        if name:find("global",1,true) or name:find("friend",1,true) then return 80 end
        if name:find("tab",1,true) then return 60 end
        if name=="robloxgui" then return 40 end
        return 0
    end
    local function queue(object,scope)
        if job.seen[object] then return end
        if job.queued>=MAX_NODES then job.truncated=true;return end
        job.seen[object]=true;job.queued+=1
        table.insert(job.stack,{object=object,scope=scope})
    end
    local function effectiveVisible(object)
        local ancestor=object
        for _=1,40 do
            if not ancestor then return "true" end
            if ancestor:IsA("GuiObject") and not ancestor.Visible then return "false ("..path(ancestor)..")" end
            if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return "false ("..path(ancestor)..")" end
            ancestor=ancestor.Parent
        end
        return "unknown (ancestor limit)"
    end
    local function targetSample()
        local input=service:FindFirstChildOfClass("ChatInputBarConfiguration")
        local value=input and read(input,"TargetTextChannel") or "no ChatInputBarConfiguration"
        if job.lastTarget~=value then
            if job.lastTarget~=nil then job.targetChanges+=1 end
            if #job.targets<8 then table.insert(job.targets,value) end
            job.lastTarget=value
        end
    end
    local function visit(object,scope)
        local objectPath=path(object)
        if object:IsA("TextChannel") then
            job.channelCount+=1
            if object.Name:lower():find("global",1,true) then job.globalChannels+=1 end
            if #job.channels<16 then
                local own="unknown"
                for _,source in ipairs(object:GetChildren()) do
                    if source:IsA("TextSource") and player then
                        local ok,id=pcall(function() return source.UserId end)
                        if ok and id==player.UserId then own=read(source,"CanSend") end
                    end
                end
                table.insert(job.channels,objectPath.." | own.CanSend="..own.." | scope="..scope)
            end
        elseif object:IsA("ChatInputBarConfiguration") then
            table.insert(job.settings,"Input.Enabled="..read(object,"Enabled").." | IsFocused="..read(object,"IsFocused"))
        elseif object:IsA("ChatWindowConfiguration") or object:IsA("ChannelTabsConfiguration") then
            table.insert(job.settings,object.ClassName..".Enabled="..read(object,"Enabled"))
        elseif object:IsA("TextChannelWindow") then
            job.windowCount+=1
            if #job.windows<8 then table.insert(job.windows,objectPath.." | Target="..read(object,"Target").." | visible="..effectiveVisible(object)) end
        elseif object:IsA("TextButton") or object:IsA("TextLabel") then
            local name=object.Name:lower()
            local controlName=name:find("tab",1,true) or name:find("channel",1,true)
                or name:find("global",1,true) or name:find("friend",1,true)
            if controlName and not name:find("message",1,true) then
                local ok,text=pcall(function() return object.Text end)
                local label=ok and text:lower():gsub("^%s+",""):gsub("%s+$",""):gsub("%s*%(%d+%)$","") or ""
                if TAB_LABELS[label] then
                    job.tabCount+=1
                    if label:find("global",1,true) or label=="グローバル" then job.globalTabs+=1 end
                    if #job.tabs<12 then table.insert(job.tabs,objectPath.." | label="..short(text).." | visible="..effectiveVisible(object).." | bg="..read(object,"BackgroundColor3")) end
                end
            end
        end
        local name=object.Name:lower()
        if scope~="TextChatService" and (name:find("chat",1,true) or name:find("channel",1,true)) and not object:IsA("TextLabel")
            and not object:IsA("TextBox") and #job.branches<8 then
            table.insert(job.branches,object.ClassName.." "..objectPath)
        end
    end
    local function finish(reason)
        local result=job
        if not result then return end
        if connection then connection:Disconnect();connection=nil end
        job=nil
        local prefix="[AutoChat 調査 v0.1.2 #"..serial.."] "
        local function log(text) warn(prefix..text) end
        log("===== REPORT BEGIN =====")
        log("Result="..reason.." | scanned="..result.processed.." | queued="..result.queued.." | errors="..result.errorCount)
        log(string.format("Channels=%d | Global-named channels=%d | Tab labels=%d | Global tab labels=%d | Windows=%d",
            result.channelCount,result.globalChannels,result.tabCount,result.globalTabs,result.windowCount))
        log("PlatformIntegratedChat="..result.platform.." | ChatVersion="..result.version.." | CreateDefaultTextChannels="..result.defaults)
        log("TargetTextChannel changes="..result.targetChanges.." | samples: "..table.concat(result.targets," -> "))
        log("Scope: TextChatService="..(result.scopes.TextChatService or 0).." / CoreGui="..(result.scopes.CoreGui or 0).." / PlayerGui="..(result.scopes.PlayerGui or 0))
        for _,line in ipairs(result.settings) do log("SETTING "..line) end
        for _,line in ipairs(result.channels) do log("CHANNEL "..line) end
        for _,line in ipairs(result.tabs) do log("TAB "..line) end
        for _,line in ipairs(result.windows) do log("WINDOW "..line) end
        for _,line in ipairs(result.branches) do log("CHAT BRANCH "..line) end
        for _,line in ipairs(result.errors) do log("ERROR "..line) end
        if result.truncated then log("INCOMPLETE: node limit reached; remaining objects were not examined.") end
        if result.channelCount>#result.channels or result.tabCount>#result.tabs or result.windowCount>#result.windows then
            log("DETAIL LIMIT: channel/tab/window counts exceed the displayed detail lines.")
        end
        if result.globalTabs>0 and result.globalChannels==0 then
            log("Global UI label found; no Global-named TextChannel found in the examined range. Send route UNCONFIRMED.")
        else log("UI existence and send-route availability are separate. This report does not prove a Global send route.") end
        log("===== 調査完了 / REPORT END =====")
        last=reason=="complete" and not result.truncated and result.errorCount==0 and "調査完了：Consoleを確認" or "調査終了（一部未取得）：Consoleを確認"
    end
    function controller.investigate()
        if closed or job then return false end
        serial+=1
        local now=os.clock()
        job={stack={},seen={},processed=0,queued=0,truncated=false,started=now,nextSample=now+1,
            scopes={},channels={},tabs={},windows={},settings={},branches={},errors={},errorCount=0,
            channelCount=0,globalChannels=0,tabCount=0,globalTabs=0,windowCount=0,targets={},targetChanges=0,
            platform=read(service,"PlatformIntegratedChat"),version=read(service,"ChatVersion"),defaults=read(service,"CreateDefaultTextChannels")}
        last="調査中：0件"
        local gui=player and player:FindFirstChildOfClass("PlayerGui")
        if gui then queue(gui,"PlayerGui") end
        local ok,core=pcall(function() return game:GetService("CoreGui") end)
        if ok then queue(core,"CoreGui") else noteError("CoreGui",core) end
        queue(service,"TextChatService")
        targetSample()
        warn("[AutoChat 調査 v0.1.2 #"..serial.."] 調査開始：完了までお待ちください。診断からは送信しません。")
        connection=RunService.Heartbeat:Connect(function()
            if not job then return end
            local now=os.clock()
            if now-job.started>=MAX_SECONDS then finish("time limit (incomplete)");return end
            if now>=job.nextSample then targetSample();job.nextSample=now+1 end
            local started=os.clock()
            for _=1,96 do
                local item=table.remove(job.stack)
                if not item then break end
                job.processed+=1;job.scopes[item.scope]=(job.scopes[item.scope] or 0)+1
                local ok,why=pcall(visit,item.object,item.scope)
                if not ok then noteError(path(item.object),why) end
                local got,children=pcall(function() return item.object:GetChildren() end)
                if got then
                    -- DFS with chat branches last on the stack, so they are examined first.
                    table.sort(children,function(a,b) return priority(a)<priority(b) end)
                    for _,child in ipairs(children) do queue(child,item.scope) end
                else noteError(path(item.object),children) end
                if os.clock()-started>=0.003 then break end
            end
            last="調査中："..job.processed.."件"
            if #job.stack==0 and now-job.started>=3 then targetSample();finish("complete") end
        end)
        return true
    end
    function controller.busy() return job~=nil end
    function controller.status() return last end
    function controller.destroy()
        if closed then return end
        closed=true
        if connection then connection:Disconnect();connection=nil end
        if job then warn("[AutoChat 調査 v0.1.2 #"..serial.."] 調査中止：画面が終了しました。") end
        job=nil
    end
    return controller
end
return module
