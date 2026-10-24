-- ROBLOXDEV Utilities r1. Self-contained; no nested loaders or shared globals.
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
    local controlGui
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
        if controlGui then
            local gui = controlGui
            controlGui = nil
            gui:Destroy()
        end
        debugLog("Stopped: " .. tostring(reason or "stop-button"))
    end
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end
    local function makeControl() end
    local ok, err = xpcall(function()
        makeControl()
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

-- Continuous TextEditable=false enforcement until STOP. No focus or text changes.
local function startInputLock()
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local running = true
    local connections = {}
    local originals = {}
    local originalClear = {}
    local boxConnections = {}
    local applying = {}
    local failureReported = setmetatable({}, {__mode = "k"})
    local controlGui
    local statusLabel = {Text = "Starting"}
    local applied, failed, reasserted = 0, 0, 0
    local function refresh()
        if statusLabel then
            statusLabel.Text = string.format("PROGRAM ONLY: user editing OFF\nTextBoxes %d / Failed %d\nReasserted %d", applied, failed, reasserted)
        end
    end
    local function stop(reason)
        if not running then return end
        running = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        for _, items in pairs(boxConnections) do
            for _, connection in ipairs(items) do connection:Disconnect() end
        end
        table.clear(boxConnections)
        table.clear(applying)
        local restored = 0
        for box, original in pairs(originals) do
            pcall(function()
                if box.Parent and box.TextEditable == false then
                    box.TextEditable = original
                    restored += 1
                end
            end)
        end
        for box, value in pairs(originalClear) do pcall(function() if box.Parent then box.ClearTextOnFocus = value end end) end
        table.clear(originalClear)
        table.clear(originals)
        if controlGui then
            local gui = controlGui
            controlGui = nil
            gui:Destroy()
        end
        warn(string.format("[ProgramOnlyInput r1] Stopped: %s; restored=%d", tostring(reason), restored))
    end
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end
    local function makeControl() end
    local ok, err = xpcall(function()
        makeControl()
        local apply
        local function forget(box)
            originalClear[box] = nil
            local items = boxConnections[box]
            if items then for _, connection in ipairs(items) do connection:Disconnect() end end
            boxConnections[box], originals[box], applying[box], failureReported[box] = nil, nil, nil, nil
        end
        apply = function(box)
            if not running or applying[box] or not box:IsA("TextBox") then return end
            applying[box] = true
            local worked, applyErr = pcall(function()
                if originals[box] == nil then
                    originals[box] = box.TextEditable
                    originalClear[box] = box.ClearTextOnFocus
                    applied += 1
                    boxConnections[box] = {
                        box:GetPropertyChangedSignal("TextEditable"):Connect(function() apply(box) end),
                        box:GetPropertyChangedSignal("ClearTextOnFocus"):Connect(function() apply(box) end),
                        box.Destroying:Connect(function() forget(box) end),
                    }
                end
                if box.ClearTextOnFocus then box.ClearTextOnFocus = false end
                if box.TextEditable ~= false then
                    box.TextEditable = false
                    reasserted += 1
                end
            end)
            applying[box] = nil
            if not worked and not failureReported[box] then
                failureReported[box] = true
                failed += 1
                warn("[ProgramOnlyInput r1] Cannot enforce: " .. tostring(applyErr))
            end
            return worked
        end
        local roots = {}
        local function scan(root)
            return pcall(function()
                for _, object in ipairs(root:GetDescendants()) do apply(object) end
            end)
        end
        local function watch(root, label)
            local watched, watchErr = pcall(function()
                connect(root.DescendantAdded, apply)
                roots[#roots + 1] = root
            end)
            if watched then watched, watchErr = scan(root) end
            warn(string.format("[ProgramOnlyInput r1] %s: %s", label, watched and "watched" or tostring(watchErr)))
        end
        watch(playerGui, "PlayerGui")
        watch(workspace, "Workspace/SurfaceGui")
        local accessible, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if accessible and coreGui then watch(coreGui, "CoreGui/chat")
        else warn("[ProgramOnlyInput r1] CoreGui unavailable: " .. tostring(coreGui)) end
        connect(UserInputService.TextBoxFocused, function(box)
            apply(box)
        end)
        local nextScan, nextUI = os.clock() + 0.5, 0
        connect(RunService.RenderStepped, function()
            if not running then return end
            -- Property events handle normal writes immediately. Each frame also
            -- rechecks tracked fields and the focused field without dropping focus.
            for box in pairs(originals) do apply(box) end
            pcall(function()
                local box = UserInputService:GetFocusedTextBox()
                if box then apply(box) end
            end)
            local now = os.clock()
            if now >= nextScan then
                nextScan = now + 0.5
                for _, root in ipairs(roots) do scan(root) end
            end
            if now >= nextUI then nextUI = now + 0.25; refresh() end
        end)
        refresh()
        warn("[ProgramOnlyInput r1] Continuous enforcement ON: property change + focus + every frame + 0.5s scan. STOP restores settings.")
    end, function(message) return tostring(message) end)
    if not ok then warn("[ProgramOnlyInput r1] " .. err); stop("error") end
    return {stop = stop, status = function() return statusLabel.Text end,
        active = function() return running end}

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
    local anti, inputLock
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
    panel.Size = UDim2.fromOffset(300, 338)
    panel.Position = UDim2.fromOffset(20, 160)
    panel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    panel.BorderSizePixel = 0
    panel.Parent = host
    local title = Instance.new("TextLabel")
    title.Name = "DragHandle"
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "ROBLOXDEV UTILITIES r1  -  drag"
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
    local inputButton = button("InputLockButton", "DisableNativeInput: ON", 78)
    local consoleButton = button("ConsoleButton", "Console: OPEN", 122)
    local allButton = button("StopAllButton", "STOP ALL / CLOSE", 292)
    allButton.BackgroundColor3 = Color3.fromRGB(192, 53, 66)
    local status = Instance.new("TextLabel")
    status.Name = "DebugStatus"
    status.Size = UDim2.new(1, -16, 0, 118)
    status.Position = UDim2.fromOffset(8, 168)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(210, 220, 235)
    status.TextSize = 12
    status.Font = Enum.Font.Code
    status.TextWrapped = true
    status.Parent = panel
    local function connect(signal, fn)
        local connection = signal:Connect(fn)
        table.insert(connections, connection)
    end
    local function endFeature(controller)
        if controller then controller.stop("utilities-toggle") end
    end
    local function refresh()
        antiButton.Text = "AntiAFK: " .. (anti and (anti.active() and "ON" or "ERROR") or "OFF")
        inputButton.Text = "DisableNativeInput: " .. (inputLock and (inputLock.active() and "ON" or "ERROR") or "OFF")
        consoleButton.Text = consoleOpen and "Console: CLOSE" or "Console: OPEN"
        status.Text = (anti and anti.status() or "AntiAFK stopped") .. "\n---\n"
            .. (inputLock and inputLock.status() or "User editing restored")
    end
    local function cleanup()
        if not alive then return end
        alive = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        endFeature(anti);anti = nil
        endFeature(inputLock);inputLock = nil
        if consoleOpen ~= initialConsole then
            pcall(function() StarterGui:SetCore("DevConsoleVisible", initialConsole) end)
        end
        warn("[Utilities r1] All features stopped; input settings restored.")
    end
    gui.Destroying:Connect(cleanup)
    connect(antiButton.Activated, function()
        if anti then endFeature(anti);anti = nil else anti = startAntiAFK() end
        refresh()
    end)
    connect(inputButton.Activated, function()
        if inputLock then endFeature(inputLock);inputLock = nil else inputLock = startInputLock() end
        refresh()
    end)
    connect(consoleButton.Activated, function()
        local target = not consoleOpen
        local ok, err = pcall(function() StarterGui:SetCore("DevConsoleVisible", target) end)
        if ok then consoleOpen = target else warn("[Utilities r1] Console: " .. tostring(err)) end
        refresh()
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
    local nextRefresh = 0
    connect(RunService.Heartbeat, function()
        if os.clock() >= nextRefresh then nextRefresh = os.clock() + 0.25;refresh() end
    end)
    gui.Parent = playerGui
    place(Vector2.new(20, 160))
    local ok, err = pcall(function()
        anti = startAntiAFK()
        inputLock = startInputLock()
    end)
    if not ok then warn("[Utilities r1] Startup: " .. tostring(err));gui:Destroy();return end
    refresh()
    warn("[Utilities r1] Ready. Independent toggles; STOP ALL restores and closes.")
end
