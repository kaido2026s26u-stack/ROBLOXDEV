-- RXDEV graphics state machine. A generation token guards every asynchronous apply.
local module = {}
function module.new(get, changed)
    local controller = {}
    local alive, generation = true, 0
    local fast, extreme
    local loading, target, fastReady = nil, 0, false
    local fastError, extremeError
    local names = {"Fast", "Advanced", "Super", "Ultra"}
    function controller.stop()
        generation += 1
        loading, target, fastReady = nil, 0, false
        local okFast, whyFast = pcall(function() if fast then fast.stop() end end)
        local okExtreme, whyExtreme = pcall(function() if extreme then extreme.stop() end end)
        fastError = not okFast and tostring(whyFast) or nil
        extremeError = not okExtreme and tostring(whyExtreme) or nil
        if fastError then warn("[RXDEV Graphics] FAST restore: " .. fastError) end
        if extremeError then warn("[RXDEV Graphics] EXTREME restore: " .. extremeError) end
    end
    local function applyLevel(level)
        fast.start()
        if level >= 2 then fast.advance() end
        if level >= 3 then fast.super() end
        if level >= 4 then fast.ultra() end
    end
    local function begin(mode, level)
        generation += 1
        local request = generation
        loading, target, fastReady = mode, level, false
        fastError, extremeError = nil, nil
        changed()
        task.spawn(function()
            local function valid() return alive and generation == request end
            local ok, why = pcall(function()
                local loaded = get("FastMode")
                if not valid() then return end
                fast = loaded
                applyLevel(target)
                fastReady = true
                changed()
                if mode == "extreme" then
                    loaded = get("ExtremelyFastMode")
                    if not valid() then return end
                    extreme = loaded
                    extreme.start()
                end
            end)
            if not valid() then return end
            loading = nil
            if not ok then
                controller.stop()
                if mode == "extreme" then extremeError=tostring(why)
                else fastError=tostring(why) end
                warn("[RXDEV Graphics] " .. mode .. " failed: " .. tostring(why))
            end
            changed()
        end)
    end
    function controller.next()
        if not alive then return end
        if loading then
            if loading == "extreme" then controller.stop()
            else
                target = (target + 1) % 5
                if target == 0 then controller.stop() end
            end
        elseif fast and fast.active() then
            if fast.level() == 4 then controller.stop()
            else
                local ok, why = pcall(applyLevel, fast.level() + 1)
                if not ok then controller.stop();fastError=tostring(why);warn("[RXDEV Graphics] " .. fastError) end
            end
        else begin("fast", 1);return end
        changed()
    end
    function controller.toggleExtreme()
        if not alive then return end
        if loading == "extreme" or (extreme and extreme.active()) then
            controller.stop();changed()
        else begin("extreme", 4) end
    end
    function controller.describe()
        local level = fast and fast.level() or 0
        local fastText
        if loading and not fastReady then fastText="LOADING: " .. names[target] .. " / NEXT"
        elseif fastError then fastText="FASTMODE: ERROR / RETRY"
        elseif level==1 then fastText="AdvancedFastMode: ENABLE"
        elseif level==2 then fastText="SuperFastMode: ENABLE"
        elseif level==3 then fastText="UltraFastMode: ENABLE"
        elseif level==4 then fastText="UltraFastMode: ON / ALL OFF"
        else fastText="FASTMODE: OFF" end
        local extremeText = "ExtremelyFastMode: " .. (loading=="extreme" and "LOADING/CANCEL"
            or extremeError and "ERROR/RETRY" or extreme and extreme.active() and "ON / ALL OFF" or "OFF")
        local fastStatus = loading and not fastReady and "Fetching child module..."
            or fastError and ("FAST ERROR: " .. fastError) or fast and fast.status() or "FAST OFF (not loaded)"
        local extremeStatus = loading=="extreme" and "Extreme loading..."
            or extremeError and ("EXTREME ERROR: " .. extremeError) or extreme and extreme.status() or "EXTREME OFF"
        return fastText, extremeText, fastStatus .. "\n" .. extremeStatus
    end
    function controller.stage()
        return (fast and fast.level() or 0) + (extreme and extreme.active() and 10 or 0) + (loading and 100 or 0)
    end
    function controller.busy()
        return loading ~= nil or (fast and fast.busy()) or (extreme and extreme.busy())
    end
    function controller.close()
        if not alive then return end
        alive = false
        controller.stop()
    end
    return controller
end
return module
