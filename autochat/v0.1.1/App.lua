-- Standalone view for AutoChat. mount() is explicit so RXDEV can host it later.
local module={}
function module.mount(get)
    local Engine,Chat,Diagnostics=get("Engine"),get("RobloxChat"),get("Diagnostics")
    local Players=game:GetService("Players")
    local RunService=game:GetService("RunService")
    local UIS=game:GetService("UserInputService")
    local player=Players.LocalPlayer
    assert(player,"LocalPlayer unavailable")
    local playerGui=player:WaitForChild("PlayerGui",10)
    assert(playerGui,"PlayerGui unavailable")
    local old=playerGui:FindFirstChild("RXDEV_AutoChat")
    if old then old:Destroy() end
    local connections,alive={},true
    local rowConnections={}
    local engine=Engine.new(Chat.send)
    local diagnostics=Diagnostics.new()
    local gui=Instance.new("ScreenGui")
    gui.Name="RXDEV_AutoChat";gui.ResetOnSpawn=false;gui.DisplayOrder=1003
    gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    local function connect(signal,fn)
        local c=signal:Connect(fn);table.insert(connections,c);return c
    end
    local function cleanup()
        if not alive then return end
        alive=false;engine.destroy();diagnostics.destroy()
        for _,c in ipairs(rowConnections) do c:Disconnect() end
        table.clear(rowConnections)
        for _,c in ipairs(connections) do c:Disconnect() end
        table.clear(connections)
        warn("[AutoChat] Closed; scheduler and UI connections removed.")
    end
    connect(gui.Destroying,cleanup)
    local function make(kind,name,parent,size,position)
        local obj=Instance.new(kind);obj.Name=name;obj.Size=size;obj.Position=position;obj.Parent=parent
        return obj
    end
    local function label(name,text,parent,size,position)
        local obj=make("TextLabel",name,parent,size,position)
        obj.Text=text;obj.TextSize=13;obj.Font=Enum.Font.Gotham
        obj.TextColor3=Color3.fromRGB(220,225,235);obj.BackgroundTransparency=1
        return obj
    end
    local function button(name,text,parent,size,position)
        local obj=make("TextButton",name,parent,size,position)
        obj.Text=text;obj.TextSize=14;obj.Font=Enum.Font.GothamBold
        obj.TextColor3=Color3.new(1,1,1);obj.BackgroundColor3=Color3.fromRGB(48,98,158)
        obj.BorderSizePixel=0
        return obj
    end
    local function input(name,text,parent,size,position)
        local obj=make("TextBox",name,parent,size,position)
        obj.Text=text;obj.TextSize=14;obj.Font=Enum.Font.Code
        obj.TextColor3=Color3.new(1,1,1);obj.BackgroundColor3=Color3.fromRGB(40,45,58)
        obj.ClearTextOnFocus=false;obj.BorderSizePixel=0
        return obj
    end
    local ok,why=pcall(function()
        local host=make("Frame","Host",gui,UDim2.fromScale(1,1),UDim2.fromScale(0,0))
        host.BackgroundTransparency=1
        local panel=make("Frame","Panel",host,UDim2.fromOffset(360,636),UDim2.fromOffset(24,100))
        panel.BackgroundColor3=Color3.fromRGB(28,32,42);panel.BorderSizePixel=0
        local title=label("DragHandle","AutoChat v0.1.1  -  drag",panel,UDim2.new(1,-48,0,30),UDim2.fromOffset(8,0))
        title.Active=true;title.Font=Enum.Font.GothamBold
        local close=button("CloseButton","X",panel,UDim2.fromOffset(28,26),UDim2.new(1,-34,0,2))
        close.BackgroundColor3=Color3.fromRGB(170,55,65)
        label("Instructions","1 phrase / line | up to 20",panel,UDim2.new(1,-16,0,28),UDim2.fromOffset(8,30))
        local scroll=make("ScrollingFrame","PhrasesScroll",panel,UDim2.new(1,-16,0,140),UDim2.fromOffset(8,60))
        scroll.BackgroundColor3=Color3.fromRGB(40,45,58);scroll.BorderSizePixel=0
        scroll.ScrollBarThickness=6;scroll.CanvasSize=UDim2.fromOffset(0,140)
        local phrases=input("PhrasesBox","",scroll,UDim2.new(1,-14,0,140),UDim2.fromOffset(4,0))
        phrases.PlaceholderText="Enter your phrases here...";phrases.MultiLine=true
        phrases.TextWrapped=true;phrases.TextXAlignment=Enum.TextXAlignment.Left;phrases.TextYAlignment=Enum.TextYAlignment.Top
        local count=label("PhraseCount","0 / 20 phrases",panel,UDim2.new(1,-16,0,24),UDim2.fromOffset(8,202))
        label("MinLabel","MIN seconds",panel,UDim2.fromOffset(164,20),UDim2.fromOffset(8,228))
        label("MaxLabel","MAX seconds",panel,UDim2.fromOffset(164,20),UDim2.fromOffset(188,228))
        local minimum=input("MinInterval","120",panel,UDim2.fromOffset(164,32),UDim2.fromOffset(8,250))
        local maximum=input("MaxInterval","240",panel,UDim2.fromOffset(164,32),UDim2.fromOffset(188,250))
        local toggle=button("ToggleButton","START",panel,UDim2.fromOffset(164,36),UDim2.fromOffset(8,484))
        local apply=button("ApplyButton","APPLY / RESTART",panel,UDim2.fromOffset(164,36),UDim2.fromOffset(188,484))
        local status=label("Status","Stopped",panel,UDim2.new(1,-16,0,104),UDim2.fromOffset(8,524))
        status.Font=Enum.Font.Code;status.TextSize=12;status.TextWrapped=true
        label("ChannelLabel","Channels (multi-select)",panel,UDim2.fromOffset(226,24),UDim2.fromOffset(8,290))
        local rescan=button("RefreshChannels","REFRESH",panel,UDim2.fromOffset(100,24),UDim2.fromOffset(252,290))
        local channelScroll=make("ScrollingFrame","ChannelsScroll",panel,UDim2.new(1,-16,0,128),UDim2.fromOffset(8,318))
        channelScroll.BackgroundColor3=Color3.fromRGB(40,45,58);channelScroll.BorderSizePixel=0
        channelScroll.ScrollBarThickness=6
        local selected,listed={},{}
        local dirty=true
        local function selectedTargets()
            local result={}
            for _,channel in ipairs(listed) do
                if selected[channel] then table.insert(result,channel) end
            end
            return result
        end
        local function rebuildChannels()
            dirty=false
            for _,c in ipairs(rowConnections) do c:Disconnect() end
            table.clear(rowConnections)
            for _,child in ipairs(channelScroll:GetChildren()) do child:Destroy() end
            listed=Chat.discover()
            local retained={}
            for index,channel in ipairs(listed) do
                local allowed,reason=Chat.availability(channel)
                if allowed~=false then retained[channel]=selected[channel] end
                local row=button("Channel_"..index,"",channelScroll,UDim2.new(1,-10,0,28),UDim2.fromOffset(2,(index-1)*30))
                row.TextSize=11
                local function render()
                    row.Text=(retained[channel] and "[x] " or "[ ] ")..channel.Name.." | "..reason
                    row.BackgroundColor3=allowed==false and Color3.fromRGB(65,65,65)
                        or retained[channel] and Color3.fromRGB(45,135,95) or Color3.fromRGB(48,70,100)
                end
                render()
                table.insert(rowConnections,row.Activated:Connect(function()
                    if allowed==false then return end
                    retained[channel]=not retained[channel]
                    render()
                end))
                for _,source in ipairs(channel:GetChildren()) do
                    if source:IsA("TextSource") then
                        table.insert(rowConnections,source:GetPropertyChangedSignal("CanSend"):Connect(function() dirty=true end))
                    end
                end
                table.insert(rowConnections,channel:GetPropertyChangedSignal("Name"):Connect(function() dirty=true end))
            end
            selected=retained
            if #listed==0 then
                local hint=label("NoChannels","No exposed TextChannels. Open chat, then REFRESH.",channelScroll,UDim2.new(1,-10,0,54),UDim2.fromOffset(2,0))
                hint.TextWrapped=true
            end
            channelScroll.CanvasSize=UDim2.fromOffset(0,math.max(128,#listed*30))
        end
        connect(rescan.Activated,function() dirty=true;rebuildChannels() end)
        local service=game:GetService("TextChatService")
        connect(service.DescendantAdded,function() dirty=true end)
        connect(service.DescendantRemoving,function() dirty=true end)
        local snap=button("DiagnosticSnapshot","SNAP / DIFF",panel,UDim2.fromOffset(164,28),UDim2.fromOffset(8,452))
        local watch=button("DiagnosticWatch","WATCH 60s",panel,UDim2.fromOffset(164,28),UDim2.fromOffset(188,452))
        snap.BackgroundColor3=Color3.fromRGB(130,100,35)
        watch.BackgroundColor3=Color3.fromRGB(130,100,35)
        connect(snap.Activated,function() diagnostics.capture() end)
        connect(watch.Activated,diagnostics.watch)
        local errorText
        local function refresh()
            if not alive then return end
            local s=engine.snapshot()
            toggle.Text=s.active and "STOP" or "START"
            toggle.BackgroundColor3=s.active and Color3.fromRGB(185,60,65) or Color3.fromRGB(48,98,158)
            watch.Text=diagnostics.watching() and "STOP WATCH" or "WATCH 60s"
            status.Text=string.format("%s | Next %.1fs\nAPI success %d / Failed %d / Attempts %d\n%s",
                s.active and (s.sending and "SENDING" or "RUNNING") or "STOPPED",s.remaining,
                s.accepted,s.failed,s.attempted,(errorText or s.state).."\n"..diagnostics.status())
        end
        local function readPhrases()
            local n,lines=0,1
            for line in (phrases.Text:gsub("\r\n","\n"):gsub("\r","\n").."\n"):gmatch("(.-)\n") do
                if line:find("%S") then n+=1 end
                lines+=math.max(1,math.ceil(utf8.len(line)/38))
            end
            count.Text=n.." / 20 phrases";count.TextColor3=n>20 and Color3.fromRGB(255,120,120) or Color3.fromRGB(220,225,235)
            local height=math.max(140,lines*20)
            phrases.Size=UDim2.new(1,-14,0,height);scroll.CanvasSize=UDim2.fromOffset(0,height)
        end
        local function start()
            local config,err=Engine.parse(phrases.Text,minimum.Text,maximum.Text,selectedTargets())
            if not config then errorText=err;refresh();return end
            local started,startErr=engine.start(config)
            errorText=not started and startErr or nil
            refresh()
        end
        connect(phrases:GetPropertyChangedSignal("Text"),readPhrases)
        connect(toggle.Activated,function()
            if engine.active() then engine.stop();errorText=nil;refresh() else start() end
        end)
        connect(apply.Activated,start)
        connect(close.Activated,function() gui:Destroy() end)
        local pointer,origin,panelOrigin
        local function place(point)
            local bounds,size=host.AbsoluteSize,panel.AbsoluteSize
            panel.Position=UDim2.fromOffset(math.clamp(point.X,0,math.max(0,bounds.X-size.X)),math.clamp(point.Y,0,math.max(0,bounds.Y-size.Y)))
        end
        connect(title.InputBegan,function(event)
            if pointer or (event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch) then return end
            pointer=event;origin=Vector2.new(event.Position.X,event.Position.Y)
            panelOrigin=Vector2.new(panel.Position.X.Offset,panel.Position.Y.Offset)
        end)
        connect(UIS.InputChanged,function(event)
            if not pointer then return end
            local touch=pointer.UserInputType==Enum.UserInputType.Touch
            if (touch and event~=pointer) or (not touch and event.UserInputType~=Enum.UserInputType.MouseMovement) then return end
            place(panelOrigin+Vector2.new(event.Position.X,event.Position.Y)-origin)
        end)
        connect(UIS.InputEnded,function(event) if event==pointer then pointer=nil end end)
        connect(UIS.WindowFocusReleased,function() pointer=nil end)
        connect(host:GetPropertyChangedSignal("AbsoluteSize"),function()
            pointer=nil;place(Vector2.new(panel.Position.X.Offset,panel.Position.Y.Offset))
        end)
        local nextUI=0
        connect(RunService.Heartbeat,function()
            if os.clock()>=nextUI then
                nextUI=os.clock()+0.25
                if dirty then rebuildChannels() end
                refresh()
            end
        end)
        gui.Parent=playerGui;place(Vector2.new(24,100));readPhrases();rebuildChannels();refresh()
    end)
    if not ok then cleanup();gui:Destroy();error(why,0) end
    warn("[AutoChat v0.1.1] Ready; stopped until START. Set 1-20 phrases and MIN/MAX seconds.")
    return {stop=engine.stop,close=function() gui:Destroy() end,active=engine.active,version="0.1.1"}
end
return module

