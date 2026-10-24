-- AutoChat scheduler. No GUI, input simulation, shared globals or background work on load.
local module = {}
local function finite(value)
    return type(value)=="number" and value==value and value<math.huge and value>-math.huge
end
function module.validate(config)
    if type(config)~="table" or type(config.phrases)~="table" then return nil,"Enter phrases first." end
    local phrases = {}
    for _, phrase in ipairs(config.phrases) do
        if type(phrase)~="string" then return nil,"Each phrase must be text." end
        phrase=phrase:match("^%s*(.-)%s*$")
        if phrase~="" then
            if phrase:find("[\r\n]") then return nil,"Use one phrase per line." end
            table.insert(phrases,phrase)
        end
    end
    if #phrases<1 or #phrases>20 then return nil,"Enter 1-20 non-empty phrases." end
    if not finite(config.minimum) or not finite(config.maximum) or config.minimum<1 or config.maximum<config.minimum then
        return nil,"Intervals: 1 <= MIN <= MAX seconds."
    end
    if type(config.targets)~="table" or #config.targets<1 then return nil,"Select at least one chat channel." end
    local targets,seen={},{}
    for _,target in ipairs(config.targets) do
        if not seen[target] then seen[target]=true;table.insert(targets,target) end
    end
    return {phrases=phrases, minimum=config.minimum, maximum=config.maximum, targets=targets}
end
function module.parse(text, minimum, maximum, targets)
    local phrases=string.split(text:gsub("\r\n","\n"):gsub("\r","\n"),"\n")
    return module.validate({phrases=phrases, minimum=tonumber(minimum), maximum=tonumber(maximum), targets=targets})
end
function module.new(send)
    assert(type(send)=="function","AutoChat needs a sender")
    local RunService=game:GetService("RunService")
    local enabled,closed,inFlight=false,false,false
    local generation,connection,config=0,nil,nil
    local nextDue=math.huge
    local attempted,accepted,failed=0,0,0
    local state="Stopped"
    local controller={}
    local function schedule()
        local interval=config.minimum+(config.maximum-config.minimum)*math.random()
        nextDue=os.clock()+interval
    end
    local function tick()
        if not enabled or inFlight or os.clock()<nextDue then return end
        local request=generation
        local phrase=config.phrases[math.random(1,#config.phrases)]
        inFlight=true
        state="Sending (API call)..."
        task.spawn(function()
            local function valid() return not closed and enabled and request==generation end
            local targets=config.targets
            for _,target in ipairs(targets) do
                -- Check before every channel: STOP also cancels the rest of a batch.
                if not valid() then break end
                attempted+=1
                local called,ok,info=pcall(send,phrase,target)
                if not valid() then break end
                if called and ok then
                    accepted+=1
                    state=tostring(info or "API accepted; delivery unverified")
                else
                    failed+=1
                    state="Error: "..tostring(called and info or ok)
                end
                warn("[AutoChat] Attempt "..attempted..": "..state)
            end
            inFlight=false
            if not valid() then return end
            -- A failure uses the ordinary interval, never an immediate retry loop.
            schedule()
        end)
    end
    function controller.start(nextConfig)
        if closed then return false,"AutoChat is closed." end
        local valid,why=module.validate(nextConfig)
        if not valid then return false,why end
        generation+=1
        config=valid;enabled=true;state="Waiting"
        schedule()
        if not connection then connection=RunService.Heartbeat:Connect(tick) end
        warn(string.format("[AutoChat] START: %d phrases, %.2f-%.2fs; first send waits too",#config.phrases,config.minimum,config.maximum))
        return true
    end
    function controller.stop()
        generation+=1
        enabled=false;nextDue=math.huge;state="Stopped"
        if connection then connection:Disconnect();connection=nil end
    end
    function controller.destroy()
        if closed then return end
        controller.stop();closed=true
    end
    function controller.active() return enabled end
    function controller.snapshot()
        return {active=enabled, sending=inFlight, remaining=enabled and math.max(0,nextDue-os.clock()) or 0,
            state=state, attempted=attempted, accepted=accepted, failed=failed,
            count=config and #config.phrases or 0}
    end
    return controller
end
return module
