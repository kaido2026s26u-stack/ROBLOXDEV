-- ROBLOXDEV Utilities r13. Self-contained; no nested loaders or shared globals.
-- F13/F14/F15 timer test. Debug receipt does not prove AFK timer reset.
local function startAntiAFK()
    local LOG_PREFIX = string.format("[AntiAFK r4 @%.3f] ", os.clock())
    warn(LOG_PREFIX .. "Loaded revision 4; NO USER-ACTIVITY GUARDS")
    local MIN_INTERVAL, MAX_INTERVAL = 30, 60
    local PRESS_SECONDS = 0.08
    local DEBUG = true
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local KEYS = { Enum.KeyCode.F13, Enum.KeyCode.F14, Enum.KeyCode.F15 }
    local running, enabled = true, true
    local connections = {}
    local statusLabel = {Text = "Starting"}
    local nextDue, nextUI = math.huge, 0
    local sendKey, backend = nil, "unavailable"
    local pressedKey, releaseAt
    local receipt
    local attempts, sent, confirmed = 0, 0, 0
    local state = "Starting"
    local nextDiagnostic = 0
    local disabledReason = "none"
    local function debugLog(message)
        if DEBUG then warn(LOG_PREFIX .. message) end
    end
    local function release()
        if not pressedKey then return true end
        local key = pressedKey
        -- Clear first: the backend can synchronously fire InputEnded.
        pressedKey = nil
        local ok, err = pcall(function() sendKey(false, key) end)
        if not ok then pressedKey = key end
        return ok, err
    end
    local function disable(reason)
        enabled = false
        disabledReason = tostring(reason)
        state = "ERROR - see Console"
        warn(LOG_PREFIX .. "Disabled: " .. tostring(reason))
    end
    local function stop(reason)
        if not running then return end
        running = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        local ok, err = release()
        if not ok then warn(LOG_PREFIX .. "Key release failed: " .. tostring(err)) end
        debugLog("Stopped: " .. tostring(reason or "stop-button"))
    end
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end
    local ok, err = xpcall(function()
        -- Use the public test API when available; Delta may instead expose VIM.
        local created, virtual = pcall(function() return UserInputService:CreateVirtualInput() end)
        if created and virtual then
            backend = "VirtualInput"
            sendKey = function(down, key) virtual:SendKey(down, key, false) end
        else
            local found, manager = pcall(function()
                local service = game:GetService("VirtualInputManager")
                assert(type(service.SendKeyEvent) == "function", "SendKeyEvent unavailable")
                return service
            end)
            if found then
                backend = "VirtualInputManager"
                sendKey = function(down, key) manager:SendKeyEvent(down, key, false, game) end
            else
                disable("No keyboard injection API: " .. tostring(manager))
            end
        end
        local function schedule(now)
            local interval = MIN_INTERVAL + (MAX_INTERVAL - MIN_INTERVAL) * math.random()
            nextDue = now + interval
            debugLog(string.format("NEXT in %.2fs; backend=%s", interval, backend))
        end
        local function observe(input, down, processed)
            local now = os.clock()
            if receipt and now <= receipt.checkAt and input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode == receipt.key then
                if down then receipt.down = true else receipt.up = true end
                debugLog(string.format("OBSERVED %s %s #%d processed=%s",
                    down and "DOWN" or "UP", receipt.key.Name, receipt.id, tostring(processed)))
                return
            end
        end
        connect(UserInputService.InputBegan, function(input, processed) observe(input, true, processed) end)
        connect(UserInputService.InputEnded, function(input, processed) observe(input, false, processed) end)
        connect(player.Idled, function(seconds)
            debugLog(string.format("IDLED %.1fs (observation only)", seconds))
        end)
        if enabled then state = "Waiting"; schedule(os.clock()) end
        connect(RunService.Heartbeat, function()
            if not running then return end
            local now = os.clock()
            if pressedKey and now >= releaseAt then
                local released, releaseErr = release()
                if not released then disable("KeyUp failed: " .. tostring(releaseErr))
                else debugLog("RELEASE sent") end
                -- A failed release is retried only by STOP, not every frame.
                releaseAt = math.huge
            end
            if receipt and now >= receipt.checkAt then
                if receipt.down and receipt.up then confirmed += 1 end
                debugLog(string.format("CHECK #%d %s down=%s up=%s; this does NOT verify idle reset",
                    receipt.id, receipt.key.Name, tostring(receipt.down), tostring(receipt.up)))
                if enabled then state = if receipt.down and receipt.up then "Input observed" else "Input NOT observed" end
                receipt = nil
            end
            if enabled and not pressedKey and now >= nextDue then
                local key = KEYS[math.random(1, #KEYS)]
                attempts += 1
                receipt = {id=attempts,key=key,down=false,up=false,checkAt=now+0.6}
                pressedKey, releaseAt = key, now + PRESS_SECONDS
                debugLog(string.format("SEND #%d %s via %s", attempts, key.Name, backend))
                local pressed, pressErr = pcall(function() sendKey(true, key) end)
                if not pressed then
                    local released, releaseErr = release()
                    disable("KeyDown failed: " .. tostring(pressErr) .. (released and "" or "; KeyUp: " .. tostring(releaseErr)))
                else
                    sent += 1
                    state = "Sent " .. key.Name
                    schedule(now)
                end
            end
            if now >= nextDiagnostic then
                nextDiagnostic = now + 10
                debugLog(string.format("STATE enabled=%s pending=%s next=%.1fs state=%s reason=%s",
                    tostring(enabled), pressedKey and pressedKey.Name or "none",
                    enabled and math.max(0, nextDue-now) or 0, state, disabledReason))
            end
            if now >= nextUI then
                nextUI = now + 0.25
                statusLabel.Text = string.format("%s | %s\nSent %d / Observed %d\nNext %.1fs",
                    backend, state, sent, confirmed, enabled and math.max(0, nextDue-now) or 0)
            end
        end)
        debugLog("Ready. Random 30-60s, F13/F14/F15. Success requires a real idle test.")
    end, function(message) return tostring(message) end)
    if not ok then warn(LOG_PREFIX .. err); stop("error") end
    return {stop = stop, status = function() return statusLabel.Text end,
        active = function() return running and enabled end}

end


do
    local Players = game:GetService("Players")
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local StarterGui = game:GetService("StarterGui")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    -- Replace the old standalone controls and any previous utilities panel.
    for _, name in ipairs({"ROBLOXDEV_Utilities", "ROBLOXDEV_AntiAFK", "ROBLOXDEV_NativeInputTest", "ROBLOXDEV_ConsoleButton"}) do
        local previous = playerGui:FindFirstChild(name)
        if previous then previous:Destroy() end
    end
    local connections = {}
    local alive = true
    local anti
    local fast
    local extreme
    local extremeLoading, extremeError, extremeToken = false, nil, 0
    local EXTREME_URL = "https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/496e47175f85cb86da2e82b87735c983e5fa8f06/ExtremelyFastMode.lua"
    local fastLoading, fastError, fastLoadToken = false, nil, 0
    local FAST_URL = "https://raw.githubusercontent.com/kaido2026s26u-stack/ROBLOXDEV/88b30f82b3ece1c5c8445ee5b9dc306a43a57399/FastMode.lua"
    local consoleOpen = false
    local initialConsole = false
    pcall(function() initialConsole = StarterGui:GetCore("DevConsoleVisible") == true end)
    consoleOpen = initialConsole
    local gui = Instance.new("ScreenGui")
    gui.Name = "ROBLOXDEV_Utilities"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1002
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local host = Instance.new("Frame")
    host.Size = UDim2.fromScale(1, 1)
    host.BackgroundTransparency = 1
    host.Parent = gui
    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.fromOffset(300, 448)
    panel.Position = UDim2.fromOffset(20, 160)
    panel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    panel.BorderSizePixel = 0
    panel.Parent = host
    local title = Instance.new("TextLabel")
    title.Name = "DragHandle"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "ROBLOXDEV UTILITIES r13  -  drag"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.Active = true
    title.Parent = panel
    local function button(name, text, y)
        local object = Instance.new("TextButton")
        object.Name = name
        object.Text = text
        object.Size = UDim2.new(1, -16, 0, 38)
        object.Position = UDim2.fromOffset(8, y)
        object.BackgroundColor3 = Color3.fromRGB(48, 98, 158)
        object.TextColor3 = Color3.new(1, 1, 1)
        object.Font = Enum.Font.GothamBold
        object.TextSize = 13
        object.Parent = panel
        return object
    end
    local antiButton = button("AntiAFKButton", "AntiAFK: ON", 34)
    local consoleButton = button("ConsoleButton", "CONSOLE OPEN", 78)
    local fastButton = button("FastModeButton", "FASTMODE: OFF", 122)
    local extremeButton = button("ExtremeButton", "ExtremelyFastMode: OFF", 166)
    extremeButton.BackgroundColor3 = Color3.fromRGB(235, 190, 45)
    extremeButton.TextColor3 = Color3.fromRGB(25, 25, 25)
    local allButton = button("StopAllButton", "STOP ALL / CLOSE", 402)
    allButton.BackgroundColor3 = Color3.fromRGB(192, 53, 66)
    local status = Instance.new("TextLabel")
    status.Name = "DebugStatus"
    status.Size = UDim2.new(1, -16, 0, 114)
    status.Position = UDim2.fromOffset(8, 210)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(210, 220, 235)
    status.TextSize = 12
    status.Font = Enum.Font.Code
    status.TextWrapped = true
    status.Parent = panel
    local performance = Instance.new("TextLabel")
    performance.Name = "PerformanceLabel"
    performance.Size = UDim2.new(1, -16, 0, 56)
    performance.Position = UDim2.fromOffset(8, 326)
    performance.BackgroundTransparency = 1
    performance.TextColor3 = Color3.fromRGB(210, 220, 235)
    performance.Font = Enum.Font.Code
    performance.TextSize = 12
    performance.Text = "FPS -- | Render (ms)\nCPU N/A | GPU N/A\nDraw N/A | Tri N/A"
    performance.Parent = panel
    local gauge = Instance.new("Frame")
    gauge.Name = "PerformanceGauge"
    gauge.Size = UDim2.new(1, -16, 0, 5)
    gauge.Position = UDim2.fromOffset(8, 388)
    gauge.BackgroundColor3 = Color3.fromRGB(55, 60, 72)
    gauge.BorderSizePixel = 0
    gauge.Parent = panel
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(80, 200, 130)
    fill.BorderSizePixel = 0
    fill.Parent = gauge
    local function connect(signal, fn)
        local connection = signal:Connect(fn)
        table.insert(connections, connection)
    end
    local function endFeature(controller)
        if controller then controller.stop("utilities-toggle") end
    end
    local function refresh()
        antiButton.Text = "AntiAFK: " .. (anti and (anti.active() and "ON" or "ERROR") or "OFF")
        if fastLoading then fastButton.Text = "FASTMODE: LOADING / CANCEL"
        elseif fastError then fastButton.Text = "FASTMODE: ERROR / RETRY"
        elseif fast and fast.level() == 1 then fastButton.Text = "AdvancedFastMode: ENABLE"
        elseif fast and fast.level() == 2 then fastButton.Text = "SuperFastMode: ENABLE"
        elseif fast and fast.level() == 3 then fastButton.Text = "UltraFastMode: ENABLE"
        elseif fast and fast.level() == 4 then fastButton.Text = "UltraFastMode: ON / ALL OFF"
        else fastButton.Text = "FASTMODE: OFF" end
        local fastStatus = fastLoading and "Fetching child module..." or fastError and ("FAST ERROR: " .. fastError) or fast and fast.status() or "FAST OFF (not loaded)"
        extremeButton.Text = "ExtremelyFastMode: " .. (extremeLoading and "LOADING/CANCEL" or extremeError and "ERROR/RETRY" or extreme and extreme.active() and "ON" or "OFF")
        local extremeStatus = extremeLoading and "Extreme loading..." or extremeError and ("EXTREME ERROR: " .. extremeError) or extreme and extreme.status() or "EXTREME OFF"
        local text = (anti and anti.status() or "AntiAFK stopped") .. "\n" .. fastStatus .. "\n" .. extremeStatus
        if status.Text ~= text then status.Text = text end
    end
    local function cleanup()
        if not alive then return end
        alive = false
        extremeToken += 1;extremeLoading = false
        if extreme then pcall(extreme.stop);extreme = nil end
        fastLoadToken += 1
        fastLoading = false
        if fast then pcall(fast.stop);fast = nil end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        endFeature(anti);anti = nil
        if consoleOpen ~= initialConsole then
            pcall(function() StarterGui:SetCore("DevConsoleVisible", initialConsole) end)
        end
        warn("[Utilities r13] Stopped. AntiAFK key released.")
    end
    gui.Destroying:Connect(cleanup)
    connect(antiButton.Activated, function()
        if anti then endFeature(anti);anti = nil else anti = startAntiAFK() end
        refresh()
    end)
    connect(consoleButton.Activated, function()
        local opened, err = pcall(function() StarterGui:SetCore("DevConsoleVisible", true) end)
        if opened then consoleOpen = true else warn("[Utilities r13] Console OPEN failed: " .. tostring(err)) end
    end)
    connect(fastButton.Activated, function()
        if fastLoading then
            fastLoadToken += 1;fastLoading = false;fastError = nil
            refresh();return
        end
        if fast and fast.active() then
            local changed, err = pcall(function()
                if fast.level() == 1 then fast.advance()
                elseif fast.level() == 2 then fast.super()
                elseif fast.level() == 3 then fast.ultra() else fast.stop() end
            end)
            if changed then fastError = nil else fastError = tostring(err) end
            refresh();return
        end
        fastLoadToken += 1
        local request = fastLoadToken
        fastLoading, fastError = true, nil
        refresh()
        task.spawn(function()
            local loaded, err = pcall(function()
                if not fast then
                    warn("[Utilities r13] Loading child FastMode module...")
                    local code = game:HttpGet(FAST_URL)
                    if not alive or request ~= fastLoadToken then return end
                    local chunk, compileErr = loadstring(code, "ROBLOXDEV_FastMode")
                    assert(chunk, compileErr)
                    local controller = chunk()
                    assert(type(controller) == "table", "Invalid FastMode module")
                    for _, method in ipairs({"start", "stop", "active", "status", "advance", "level", "super", "ultra", "busy"}) do
                        assert(type(controller[method]) == "function", "Missing FastMode." .. method)
                    end
                    if not alive or request ~= fastLoadToken then return end
                    fast = controller
                end
                if alive and request == fastLoadToken then fast.start() end
            end)
            if not alive or request ~= fastLoadToken then return end
            fastLoading = false
            if not loaded then
                if fast then pcall(fast.stop) end
                fastError = tostring(err)
                warn("[Utilities r13] FASTMODE failed: " .. fastError)
            end
            refresh()
        end)
    end)
    connect(extremeButton.Activated, function()
        if extremeLoading then
            extremeToken+=1;extremeLoading=false;extremeError=nil;refresh();return
        end
        if extreme and extreme.active() then
            local ok,err=pcall(extreme.stop)
            if ok then extremeError=nil else extremeError=tostring(err) end
            refresh();return
        end
        extremeToken+=1
        local request=extremeToken
        extremeLoading,extremeError=true,nil
        refresh()
        task.spawn(function()
            local ok,err=pcall(function()
                if not extreme then
                    local code=game:HttpGet(EXTREME_URL)
                    if not alive or request~=extremeToken then return end
                    local chunk,why=loadstring(code,"ROBLOXDEV_Extreme")
                    assert(chunk,why)
                    local controller=chunk()
                    assert(type(controller)=="table","Invalid Extreme module")
                    for _,method in ipairs({"start","stop","active","busy","status"}) do
                        assert(type(controller[method])=="function","Missing Extreme."..method)
                    end
                    if not alive or request~=extremeToken then return end
                    extreme=controller
                end
                if alive and request==extremeToken then extreme.start() end
            end)
            if not alive or request~=extremeToken then return end
            extremeLoading=false
            if not ok then
                if extreme then pcall(extreme.stop) end
                extremeError=tostring(err);warn("[Utilities r13] EXTREME failed: "..extremeError)
            end
            refresh()
        end)
    end)
    connect(allButton.Activated, function() gui:Destroy() end)
    local pointer, origin, panelOrigin
    local function place(point)
        local bounds, size = host.AbsoluteSize, panel.AbsoluteSize
        panel.Position = UDim2.fromOffset(math.clamp(point.X, 0, math.max(0, bounds.X-size.X)),
            math.clamp(point.Y, 0, math.max(0, bounds.Y-size.Y)))
    end
    connect(title.InputBegan, function(input)
        if pointer or (input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch) then return end
        pointer = input
        origin = Vector2.new(input.Position.X, input.Position.Y)
        panelOrigin = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
    end)
    connect(UIS.InputChanged, function(input)
        if not pointer then return end
        local touch = pointer.UserInputType == Enum.UserInputType.Touch
        if (touch and input ~= pointer) or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
        place(panelOrigin + Vector2.new(input.Position.X, input.Position.Y) - origin)
    end)
    connect(UIS.InputEnded, function(input) if input == pointer then pointer = nil end end)
    connect(UIS.WindowFocusReleased, function() pointer = nil end)
    connect(host:GetPropertyChangedSignal("AbsoluteSize"), function()
        pointer = nil
        place(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset))
    end)
    local sampleCount, sampleSeconds = 0, 0
    local meterStage, readyAt, nextMeterUI, nextStatsRead = nil, 0, 0, 0
    local stats
    pcall(function() stats = game:GetService("Stats") end)
    local properties = {"RenderCPUFrameTime", "RenderGPUFrameTime", "SceneDrawcallCount", "SceneTriangleCount"}
    local sums, counts, reported = {}, {}, {}
    local function clearSamples()
        sampleCount, sampleSeconds = 0, 0
        table.clear(sums);table.clear(counts)
    end
    local function readStats()
        for index, property in ipairs(properties) do
            local ok, value = pcall(function() return stats[property] end)
            local valid = ok and type(value)=="number" and value==value and value<math.huge
                and (index<=2 and value>0 or index>2 and value>=0)
            if valid then
                sums[index]=(sums[index] or 0)+value
                counts[index]=(counts[index] or 0)+1
            end
            if not reported[index] then
                reported[index]=true
                warn(string.format("[Utilities r13] Metric %s: %s",property,
                    valid and tostring(value) or "N/A (not available/invalid)"))
            end
        end
    end
    local function average(index)
        return counts[index] and sums[index]/counts[index] or nil
    end
    local function msText(value)
        return value and string.format("%.2f",value*1000) or "N/A"
    end
    connect(RunService.RenderStepped, function(dt)
        if not alive then return end
        local now = os.clock()
        local stage = (fastLoading and -1 or fast and fast.level() or 0) + (extremeLoading and 100 or extreme and extreme.active() and 10 or 0)
        local applying = fastLoading or (fast and fast.busy()) or extremeLoading or (extreme and extreme.busy())
        if stage ~= meterStage or applying then
            meterStage = stage
            clearSamples()
            readyAt = now + 1
        end
        if now >= readyAt then
            if dt > 0 and dt < math.huge then sampleCount+=1;sampleSeconds+=dt end
            -- Four scalar reads at most five times per second, not per rendered frame.
            if now >= nextStatsRead then nextStatsRead=now+0.2;readStats() end
        end
        if now < nextMeterUI then return end
        nextMeterUI=now+0.5
        local text
        if applying or now < readyAt then
            text="FPS -- | Render (ms)\nCPU -- | GPU -- (settling)\nDraw -- | Tri --"
            fill.Size=UDim2.fromScale(0,1)
            fill.BackgroundColor3=Color3.fromRGB(110,115,125)
        elseif sampleSeconds>=0.5 and sampleCount>0 then
            local fps=sampleCount/sampleSeconds
            local cpu,gpu,draw,tri=average(1),average(2),average(3),average(4)
            text=string.format("FPS %.1f | Render (ms)\nCPU %s | GPU %s\nDraw %s | Tri %s",fps,msText(cpu),msText(gpu),
                draw and string.format("%.0f",draw) or "N/A",tri and string.format("%.1fk",tri/1000) or "N/A")
            -- CPU/GPU overlap: never add them or label this as device utilization.
            -- Scale is a fixed 60-FPS rendering budget; missing metrics stay neutral.
            if cpu and gpu then
                local renderMs=math.max(cpu,gpu)*1000
                fill.Size=UDim2.fromScale(math.clamp(renderMs/(1000/60),0,1),1)
                fill.BackgroundColor3=if renderMs<=8.33 then Color3.fromRGB(80,200,130)
                    elseif renderMs<=16.67 then Color3.fromRGB(240,185,70) else Color3.fromRGB(230,90,90)
            else
                fill.Size=UDim2.fromScale(0,1)
                fill.BackgroundColor3=Color3.fromRGB(110,115,125)
            end
            clearSamples()
        else return end
        if performance.Text~=text then performance.Text=text end
    end)
    local nextRefresh = 0
    connect(RunService.Heartbeat, function()
        if os.clock() >= nextRefresh then nextRefresh = os.clock() + 0.25;refresh() end
    end)
    gui.Parent = playerGui
    place(Vector2.new(20, 160))
    local ok, err = pcall(function()
        anti = startAntiAFK()
    end)
    if not ok then warn("[Utilities r13] Startup: " .. tostring(err));gui:Destroy();return end
    refresh()
    warn("[Utilities r13] Ready. AntiAFK + Console OPEN + optional FASTMODE (nested loadstring).")
end
