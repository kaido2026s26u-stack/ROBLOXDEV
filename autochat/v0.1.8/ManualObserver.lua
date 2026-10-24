-- Public event observation only. Never reads Text, Translation, PrefixText or Metadata.
local module={}
function module.new(storage)
    local service=game:GetService("TextChatService")
    local player=game:GetService("Players").LocalPlayer
    local alive,job,status=true,nil,nil
    local controller={}
    local function path(object)
        if not object then return "nil" end
        local ok,value=pcall(function() return object:GetFullName() end)
        return ok and value or "unavailable"
    end
    local function disconnect(j)
        for _,c in ipairs(j.connections) do c:Disconnect() end
        table.clear(j.connections)
        for _,c in pairs(j.channels) do c:Disconnect() end
        table.clear(j.channels)
    end
    function controller.start(phase)
        if not alive or job then return false end
        assert(phase=="Local" or phase=="Global","Unknown observation phase")
        local j={connections={},channels={},started=os.clock(),lines={},data={
            schemaVersion=1,version="0.1.8",kind="manual-observation",phase=phase,
            selectionSource="User selected observation button; native tab selection not verified",
            createdUnix=os.time(),durationLimit=30,eventLimit=200,events={},hooks={},errors={},
            ignoredOtherSources=0,truncated=false,
            limits="Metadata only. Events may overlap across service/channel. No event does not prove no delivery.",
        }}
        job=j
        local d=j.data
        local function log(s) table.insert(j.lines,s);warn("[AutoChat manual "..phase.."] "..s) end
        local function issue(s)
            if #d.errors<20 then table.insert(d.errors,s);log("ERROR "..s) end
        end
        local function record(event,fields)
            if job~=j or not alive then return end
            if #d.events>=200 then d.truncated=true;return end
            fields=fields or {};fields.event=event;fields.elapsed=os.clock()-j.started
            table.insert(d.events,fields)
            log(event.." | channel="..tostring(fields.channel or fields.target or "-").." | status="..tostring(fields.status or "-"))
        end
        local function connect(name,getSignal,fn)
            local ok,c=pcall(function() return getSignal():Connect(function(...)
                if job~=j or not alive then return end
                local good,err=pcall(fn,...)
                if not good then issue(name..": "..tostring(err)) end
            end) end)
            table.insert(d.hooks,{name=name,connected=ok})
            if not ok then issue(name..": "..tostring(c));return nil end
            return c
        end
        local function watch(name,getSignal,fn)
            local c=connect(name,getSignal,fn)
            if c then table.insert(j.connections,c) end
        end
        local function message(event,m)
            -- Only compare source UserId; do not export user identifiers or message content.
            local source=m.TextSource
            if source and player and source.UserId~=player.UserId then
                d.ignoredOtherSources+=1;return
            end
            record(event,{channel=path(m.TextChannel),status=tostring(m.Status),source=source and "self" or "none"})
        end
        local function addChannel(c)
            if not c:IsA("TextChannel") or j.channels[c] then return end
            local conn=connect(path(c)..".MessageReceived",function() return c.MessageReceived end,function(m)
                message("Channel.MessageReceived",m)
            end)
            if conn then j.channels[c]=conn end
        end
        local function snapshot()
            local result={channels={}}
            local ok,err=pcall(function()
                local input=service:FindFirstChildOfClass("ChatInputBarConfiguration")
                result.currentTarget=path(input and input.TargetTextChannel)
                result.platformIntegratedChat=tostring(service.PlatformIntegratedChat)
                for _,c in ipairs(service:GetDescendants()) do
                    if c:IsA("TextChannel") then table.insert(result.channels,path(c)) end
                end
                table.sort(result.channels)
            end)
            if not ok then result.error=tostring(err) end
            return result
        end
        local function finish(reason)
            if job~=j or not alive then return end
            disconnect(j)
            d.reason=reason;d.elapsed=os.clock()-j.started;d.finish=snapshot()
            log("END | events="..#d.events.." | reason="..reason)
            local callOK,ok,result=pcall(storage.save,table.concat(j.lines,"\n"),d)
            if callOK and ok then
                status=phase.."観測保存完了: "..#d.events.." events\n"..table.concat(result.paths,"\n")
            else
                status=phase.."観測保存失敗: "..tostring(callOK and result and result.error or ok)
            end
            log(status);job=nil
        end
        status=phase.."観測中（30秒）: 標準チャットで手動送信してください"
        log("BEGIN | manually select "..phase.." and send within 30 seconds")
        d.start=snapshot()
        watch("Service.SendingMessage",function() return service.SendingMessage end,function(m) message("Service.SendingMessage",m) end)
        watch("Service.MessageReceived",function() return service.MessageReceived end,function(m) message("Service.MessageReceived",m) end)
        watch("Service.DescendantAdded",function() return service.DescendantAdded end,function(c)
            if c:IsA("TextChannel") then record("ChannelAdded",{channel=path(c)});addChannel(c) end
        end)
        watch("Service.DescendantRemoving",function() return service.DescendantRemoving end,function(c)
            if c:IsA("TextChannel") then
                record("ChannelRemoved",{channel=path(c)})
                if j.channels[c] then j.channels[c]:Disconnect();j.channels[c]=nil end
            end
        end)
        local input=service:FindFirstChildOfClass("ChatInputBarConfiguration")
        if input then watch("Input.TargetTextChannel",function() return input:GetPropertyChangedSignal("TargetTextChannel") end,function()
            record("TargetChanged",{target=path(input.TargetTextChannel)})
        end) end
        for _,c in ipairs(service:GetDescendants()) do addChannel(c) end
        watch("ObservationDeadline",function() return game:GetService("RunService").Heartbeat end,function()
            if os.clock()-j.started>=30 then finish("complete") end
        end)
        -- Deadline must work even if Heartbeat cannot be connected.
        if not d.hooks[#d.hooks].connected then finish("deadline-unavailable") end
        return true
    end
    function controller.busy() return job~=nil end
    function controller.status() return status end
    function controller.clearStatus() if not job then status=nil end end
    function controller.destroy()
        alive=false
        if job then disconnect(job);job=nil end
    end
    return controller
end
return module
