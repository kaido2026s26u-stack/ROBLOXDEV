-- Explicit one-shot sends. Never changes the native chat selection or retries.
local module={}
function module.new(Chat,storage)
    local service=game:GetService("TextChatService")
    local alive,inFlight,serial=true,false,0
    local status
    local controller={}
    local function path(object)
        if not object then return "nil" end
        local ok,value=pcall(function() return object:GetFullName() end)
        return ok and value or tostring(object)
    end
    function controller.run(route)
        if not alive or inFlight then return false end
        assert(route=="current" or route=="general","Unknown test route")
        serial+=1
        local id=tostring(os.time()).."_"..serial
        local data={schemaVersion=1,version="0.1.9",kind="route-test",createdUnix=os.time(),id=id,route=route,
            delivery="unverified",selection="Native Here/Global selection is not exposed by this probe"}
        local lines={}
        local function log(value)
            table.insert(lines,value);warn("[AutoChat route test] "..value)
        end
        local channel
        local setupOK,why=pcall(function()
            local input=service:FindFirstChildOfClass("ChatInputBarConfiguration")
            local current=input and input.TargetTextChannel
            local folder=service:FindFirstChild("TextChannels")
            local general=folder and folder:FindFirstChild("RBXGeneral")
            data.currentTarget=path(current);data.generalTarget=path(general)
            data.sameTarget=current~=nil and current==general
            data.platformIntegratedChat=tostring(service.PlatformIntegratedChat)
            channel=route=="current" and current or nil
            if route=="general" then channel=general end
            data.destination=path(channel)
            assert(channel,"No destination for this route; no fallback send")
            local allowed,reason=Chat.availability(channel)
            data.permission=tostring(allowed);data.permissionReason=reason
            assert(allowed~=false,reason)
        end)
        inFlight=true
        local start=os.clock()
        local finished=false
        local function finish(outcome,detail)
            if finished or not alive then return end
            finished=true
            data.outcome=outcome;data.detail=tostring(detail);data.elapsed=os.clock()-start
            log("RESULT "..outcome.." | "..data.detail.." | delivery unverified")
            local callOK,saveOK,saved=pcall(storage.save,table.concat(lines,"\n"),data)
            local paths=callOK and saved and saved.paths or {}
            if callOK and saveOK then
                status="送信テスト: "..outcome.."\n"..table.concat(paths,"\n")
            else
                status="送信テスト: "..outcome.." / 保存失敗: "..tostring(callOK and saved and saved.error or saveOK).."\n"..table.concat(paths,"\n")
            end
            log(status)
            inFlight=outcome=="timeout"
        end
        log("BEGIN "..id.." | route="..route.." | destination="..tostring(data.destination))
        log("Current="..tostring(data.currentTarget).." | RBXGeneral="..tostring(data.generalTarget).." | sameTarget="..tostring(data.sameTarget))
        if not setupOK then finish("not-sent",why);return true end
        data.message="ImCooked "..(route=="current" and "A" or "B")
        log("SEND ONCE "..data.message)
        status="送信テスト実行中: "..route
        task.delay(15,function() finish("timeout","Send call has not returned; it may still complete. No retry.") end)
        task.spawn(function()
            if not alive then return end
            local ok,accepted,detail,rawStatus=pcall(Chat.send,data.message,channel)
            if not alive then return end
            if finished then
                inFlight=false
                log("LATE RETURN "..id.." | callOK="..tostring(ok).." | "..tostring(accepted).." | "..tostring(detail))
                return
            end
            if ok and rawStatus then data.apiStatus=tostring(rawStatus) end
            local pending=ok and rawStatus==Enum.TextChatMessageStatus.Sending
            finish(not ok and "error" or accepted and "api-success" or pending and "api-pending" or "api-rejected",ok and detail or accepted)
        end)
        return true
    end
    function controller.clearStatus() status=nil end
    function controller.busy() return inFlight end
    function controller.status() return status end
    function controller.destroy() alive=false end
    return controller
end
return module
