-- Temporary one-button investigation. Read metadata, finish, report and disconnect.
local module={}
function module.new(storage)
    local service=game:GetService("TextChatService")
    local RunService=game:GetService("RunService")
    local player=game:GetService("Players").LocalPlayer
    local connection,job
    local saving=false
    local closed,serial=false,0
    local refIds,nextRef=setmetatable({}, {__mode="k"}),0
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
    local function ref(object)
        if not refIds[object] then nextRef+=1;refIds[object]=nextRef end
        return path(object).." #"..refIds[object]
    end
    local function read(object,key)
        local ok,value=pcall(function() return object[key] end)
        if not ok then return "UNAVAILABLE: "..short(value) end
        if typeof(value)=="Instance" then return ref(value) end
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
    local function queue(object,scope,depth,parentSelectorDepth,group)
        if job.seen[object] then return end
        job.seen[object]=true
        local name=object.Name:lower()
        if object:IsA("LuaSourceContainer") then job.skippedScripts+=1;return end
        if name:find("voicechat",1,true) or name=="voice" then job.skippedVoice+=1;return end
        if name:find("bubblechat",1,true) then job.skippedBubbles+=1;return end
        if object.Name=="RXDEV_AutoChat" then job.skippedOwnUI+=1;return end
        local selectorDepth=parentSelectorDepth and parentSelectorDepth+1 or nil
        if name:find("tab",1,true) or name:find("navigation",1,true) then selectorDepth=0 end
        if job.queued>=MAX_NODES then job.truncated=true;return end
        job.queued+=1
        local skipChildren=name:find("messagelist",1,true) or name:find("messagehistory",1,true)
        if skipChildren then job.skippedMessages+=1 end
        table.insert(job.stack,{object=object,scope=scope,chatDepth=depth,selectorDepth=selectorDepth,group=group,skipChildren=skipChildren})
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
    local function fullPath(object)
        local ok,value=pcall(function() return object:GetFullName() end)
        return ok and value or "<path unavailable>"
    end
    local function recordBox(object,origin)
        if not object:IsA("TextBox") or job.boxesSeen[object] then return end
        job.boxesSeen[object]=true;job.boxCount+=1
        if #job.boxes<8 then
            table.insert(job.boxes,{path=path(object),origin=origin,
                state="visible="..effectiveVisible(object).." | editable="..read(object,"TextEditable").." | multiline="..read(object,"MultiLine"),
                size="size="..read(object,"AbsoluteSize").." | ClearTextOnFocus="..read(object,"ClearTextOnFocus")})
        end
    end
    local function targetSample()
        local input=service:FindFirstChildOfClass("ChatInputBarConfiguration")
        local value=input and read(input,"TargetTextChannel") or "no ChatInputBarConfiguration"
        local boxValue="no ChatInputBarConfiguration"
        if input then
            local ok,box=pcall(function() return input.TextBox end)
            boxValue=ok and (box and ref(box) or "nil") or "UNAVAILABLE: "..short(box)
            if ok and box then
                local got,why=pcall(recordBox,box,"ChatInputBarConfiguration.TextBox")
                if not got then noteError("input.TextBox metadata",why) end
            end
        end
        if job.lastBox~=boxValue then
            if job.lastBox~=nil then job.boxChanges+=1 end
            if #job.inputBoxes<8 then table.insert(job.inputBoxes,boxValue) end
            job.lastBox=boxValue
        end
        if job.lastTarget~=value then
            if job.lastTarget~=nil then job.targetChanges+=1 end
            if #job.targets<8 then table.insert(job.targets,value) end
            job.lastTarget=value
        end
    end
    local function visit(object,scope,chatDepth,selectorDepth,group)
        local objectPath=path(object)
        if group then
            local node={path=fullPath(object),class=object.ClassName,depth=chatDepth,root=group.key}
            if object:IsA("GuiObject") then node.visible=effectiveVisible(object) end
            if object:IsA("TextBox") then
                node.editable=read(object,"TextEditable");node.size=read(object,"AbsoluteSize")
            end
            table.insert(job.nodes,node)
        end
        if group then
            group.processed+=1
            if object:IsA("TextBox") then recordBox(object,group.key) end
            if chatDepth<=4 then
                group.structureCount+=1;job.structureCount+=1
                local name=object.Name:lower()
                local rank=1000-chatDepth*100+priority(object)
                if name:find("input",1,true) or selectorDepth~=nil then rank=1800-chatDepth*40 end
                if chatDepth==0 then rank=2000 end
                local row={rank=rank,line="depth="..chatDepth.." "..object.ClassName.." "..objectPath}
                if object:IsA("GuiObject") then row.line..=" | visible="..effectiveVisible(object) end
                table.insert(group.structure,row)
                table.sort(group.structure,function(a,b) return a.rank==b.rank and a.line<b.line or a.rank>b.rank end)
                if #group.structure>18 then table.remove(group.structure) end
            end
        end
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
                or name:find("global",1,true) or name:find("friend",1,true) or (selectorDepth~=nil and selectorDepth<=3)
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

    end
    local function finish(reason)
        local result=job
        if not result then return end
        if connection then connection:Disconnect();connection=nil end
        job=nil
        local prefix="[AutoChat 調査 v0.1.5 #"..serial.."] "
        local lines={}
        local function log(text)
            table.insert(lines,prefix..text)
            warn(prefix..text)
        end
        log("===== REPORT BEGIN =====")
        log("Result="..reason.." | scanned="..result.processed.." | queued="..result.queued.." | errors="..result.errorCount)
        log(string.format("Channels=%d | Global-named channels=%d | Tab labels=%d | Global tab labels=%d | Windows=%d",
            result.channelCount,result.globalChannels,result.tabCount,result.globalTabs,result.windowCount))
        log("PlatformIntegratedChat="..result.platform.." | ChatVersion="..result.version.." | CreateDefaultTextChannels="..result.defaults)
        log("TargetTextChannel changes="..result.targetChanges.." | samples: "..table.concat(result.targets," -> "))
        log("Input.TextBox changes="..result.boxChanges.." | samples: "..table.concat(result.inputBoxes," -> "))
        log("Focused GUI roots="..#result.groups.." | TextBoxes="..result.boxCount.." | structure candidates="..result.structureCount)
        log("Excluded subtrees: scripts="..result.skippedScripts.." / voice="..result.skippedVoice.." / bubbles="..result.skippedBubbles.." / messages="..result.skippedMessages)
        for _,line in ipairs(result.rootStatus) do log("ROOT STATUS "..line) end
        log("Scope: TextChatService="..(result.scopes.TextChatService or 0).." / CoreGui="..(result.scopes.CoreGui or 0).." / PlayerGui="..(result.scopes.PlayerGui or 0))
        for _,line in ipairs(result.settings) do log("SETTING "..line) end
        for _,line in ipairs(result.channels) do log("CHANNEL "..line) end
        for _,line in ipairs(result.tabs) do log("TAB "..line) end
        for _,line in ipairs(result.windows) do log("WINDOW "..line) end

        for _,box in ipairs(result.boxes) do
            log("TEXTBOX "..box.path.." | source="..box.origin)
            log("BOX STATE "..box.state)
            log("BOX STATE "..box.size)
        end
        for _,group in ipairs(result.groups) do
            log("UI ROOT "..group.key.." | class="..group.class.." | direct children="..group.children.." | examined="..group.processed)
            for _,row in ipairs(group.structure) do log("UI STRUCT ["..group.key.."] "..row.line) end
            if group.structureCount>#group.structure then log("STRUCTURE DETAIL LIMIT ["..group.key.."]: "..group.structureCount.." candidates, 18 shown") end
        end
        for _,line in ipairs(result.errors) do log("ERROR "..line) end
        if result.truncated then log("INCOMPLETE: node limit reached; remaining objects were not examined.") end
        if result.boxCount>#result.boxes then log("TEXTBOX DETAIL LIMIT: first 8 inputs shown") end
        if result.channelCount>#result.channels or result.tabCount>#result.tabs or result.windowCount>#result.windows then
            log("DETAIL LIMIT: channel/tab/window counts exceed the displayed detail lines.")
        end
        if result.globalTabs>0 and result.globalChannels==0 then
            log("Global UI label found; no Global-named TextChannel found in the examined range. Send route UNCONFIRMED.")
        else log("UI existence and send-route availability are separate. This report does not prove a Global send route.") end
        log("===== 調査完了 / REPORT END =====")
        last=reason=="complete" and not result.truncated and result.errorCount==0 and "調査完了：Consoleを確認" or "調査終了（一部未取得）：Consoleを確認"
        if storage then
            local details={}
            for _,node in ipairs(result.nodes) do
                table.insert(details,"depth="..node.depth.." "..node.class.." "..node.path
                    ..(node.visible and " | visible="..node.visible or ""))
            end
            local data={schemaVersion=1,version="0.1.5",createdUnix=os.time(),reason=reason,
                coverage={scope="TextChatService and direct AppChat/ExperienceChat roots",nodeLimit=MAX_NODES,
                    secondsLimit=MAX_SECONDS,truncated=result.truncated,scanned=result.processed,scopes=result.scopes,
                    excluded={scripts=result.skippedScripts,voice=result.skippedVoice,bubbles=result.skippedBubbles,messages=result.skippedMessages}},
                api={platformIntegratedChat=result.platform,chatVersion=result.version,createDefaultTextChannels=result.defaults,
                    targets=result.targets,targetChanges=result.targetChanges,textBoxReferences=result.inputBoxes,textBoxChanges=result.boxChanges},
                rootStatus=result.rootStatus,roots=result.groups,nodes=result.nodes,channels=result.channels,
                channelCount=result.channelCount,tabs=result.tabs,tabCount=result.tabCount,windows=result.windows,
                windowCount=result.windowCount,textBoxes=result.boxes,textBoxCount=result.boxCount,
                settings=result.settings,errors=result.errors,errorCount=result.errorCount,consoleLines=lines}
            local text=table.concat(lines,"\n").."\n\n===== FULL EXAMINED UI STRUCTURE =====\n"..table.concat(details,"\n").."\n"
            saving=true
            local called,ok,info=pcall(storage.save,text,data)
            saving=false
            if called and ok then
                last="保存完了："..info.paths[1]
                for _,saved in ipairs(info.paths) do warn(prefix.."保存・読み戻し確認: "..saved) end
            else
                local why=called and info.error or ok
                last="調査完了／保存失敗：Consoleを確認"
                warn(prefix.."保存失敗: "..tostring(why))
                if called and info.paths then for _,saved in ipairs(info.paths) do warn(prefix.."部分保存済み: "..saved) end end
            end
        end
    end
    function controller.investigate()
        if closed or job or saving then return false end
        serial+=1
        local now=os.clock()
        job={stack={},seen={},processed=0,queued=0,truncated=false,started=now,nextSample=now+1,
            scopes={},channels={},tabs={},windows={},settings={},errors={},errorCount=0,
            skippedBubbles=0,skippedOwnUI=0,skippedScripts=0,skippedVoice=0,skippedMessages=0,boxes={},boxesSeen={},boxCount=0,inputBoxes={},boxChanges=0,
            groups={},rootStatus={},structureCount=0,nodes={},
            channelCount=0,globalChannels=0,tabCount=0,globalTabs=0,windowCount=0,targets={},targetChanges=0,
            platform=read(service,"PlatformIntegratedChat"),version=read(service,"ChatVersion"),defaults=read(service,"CreateDefaultTextChannels")}
        last="調査中：0件"
        local function addRoots(container,scope)
            for _,name in ipairs({"AppChat","ExperienceChat"}) do
                local ok,root=pcall(function() return container:FindFirstChild(name) end)
                if not ok then noteError(scope.."."..name,root)
                elseif not root then table.insert(job.rootStatus,scope.."."..name.." = NOT FOUND (direct child)")
                elseif root:IsA("LuaSourceContainer") then table.insert(job.rootStatus,scope.."."..name.." = SCRIPT, not a GUI root")
                else
                    local got,children=pcall(function() return root:GetChildren() end)
                    local group={key=path(root),class=root.ClassName,children=got and tostring(#children) or "UNAVAILABLE",processed=0,structure={},structureCount=0}
                    table.insert(job.groups,group)
                    if not got then noteError(path(root),children) end
                    queue(root,scope,0,nil,group)
                end
            end
        end
        local gui=player and player:FindFirstChildOfClass("PlayerGui")
        if gui then addRoots(gui,"PlayerGui") end
        local ok,core=pcall(function() return game:GetService("CoreGui") end)
        if ok then addRoots(core,"CoreGui") else noteError("CoreGui",core) end
        queue(service,"TextChatService")
        targetSample()
        warn("[AutoChat 調査 v0.1.5 #"..serial.."] 調査開始：完了までお待ちください。診断からは送信しません。")
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
                local ok,why=pcall(visit,item.object,item.scope,item.chatDepth,item.selectorDepth,item.group)
                if not ok then noteError(path(item.object),why) end
                local got,children=pcall(function() return item.skipChildren and {} or item.object:GetChildren() end)
                if got then
                    -- DFS with chat branches last on the stack, so they are examined first.
                    table.sort(children,function(a,b) return priority(a)<priority(b) end)
                    for _,child in ipairs(children) do queue(child,item.scope,item.chatDepth and item.chatDepth+1 or nil,item.selectorDepth,item.group) end
                else noteError(path(item.object),children) end
                if os.clock()-started>=0.003 then break end
            end
            last="調査中："..job.processed.."件"
            if #job.stack==0 and now-job.started>=3 then targetSample();finish("complete") end
        end)
        return true
    end
    function controller.busy() return job~=nil or saving end
    function controller.status() return last end
    function controller.destroy()
        if closed then return end
        closed=true
        if connection then connection:Disconnect();connection=nil end
        if job then warn("[AutoChat 調査 v0.1.5 #"..serial.."] 調査中止：画面が終了しました。") end
        job=nil;table.clear(refIds)
    end
    return controller
end
return module
