-- F13/F14/F15 timer test. Debug receipt does not prove AFK timer reset.
do
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
    local GUI_NAME = "ROBLOXDEV_AntiAFK"
    local previous = playerGui:FindFirstChild(GUI_NAME)
    if previous then previous:Destroy() end
    local KEYS = { Enum.KeyCode.F13, Enum.KeyCode.F14, Enum.KeyCode.F15 }
    local running, enabled = true, true
    local connections = {}
    local controlGui, statusLabel
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
    local function makeControl()
        local inputService = game:GetService("UserInputService")
        local gui = Instance.new("ScreenGui")
        controlGui = gui
        gui.Name = GUI_NAME
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 1001
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local host = Instance.new("Frame")
        host.Size = UDim2.fromScale(1, 1)
        host.BackgroundTransparency = 1
        host.Parent = gui

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.Size = UDim2.fromOffset(260, 142)
        panel.Position = UDim2.fromOffset(20, 300)
        panel.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
        panel.BorderSizePixel = 0
        panel.Parent = host
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = panel

        local handle = Instance.new("TextLabel")
        handle.Name = "DragHandle"
        handle.Size = UDim2.new(1, 0, 0, 28)
        handle.BackgroundTransparency = 1
        handle.Text = "ANTI AFK r4  -  drag"
        handle.TextColor3 = Color3.fromRGB(210, 220, 235)
        handle.Font = Enum.Font.GothamBold
        handle.TextSize = 12
        handle.Active = true
        handle.Parent = panel

        local button = Instance.new("TextButton")
        button.Name = "StopButton"
        button.Size = UDim2.new(1, -16, 0, 40)
        button.Position = UDim2.fromOffset(8, 94)
        button.BackgroundColor3 = Color3.fromRGB(192, 53, 66)
        button.BorderSizePixel = 0
        button.Text = "STOP ANTI AFK"
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.GothamBold
        button.TextSize = 14
        button.Parent = panel
        local buttonCorner = Instance.new("UICorner")
        buttonCorner.CornerRadius = UDim.new(0, 7)
        buttonCorner.Parent = button

        statusLabel = Instance.new("TextLabel")
        statusLabel.Name = "DebugStatus"
        statusLabel.Size = UDim2.new(1, -16, 0, 60)
        statusLabel.Position = UDim2.fromOffset(8, 28)
        statusLabel.BackgroundTransparency = 1
        statusLabel.TextColor3 = Color3.fromRGB(210, 220, 235)
        statusLabel.Font = Enum.Font.Code
        statusLabel.TextSize = 12
        statusLabel.TextWrapped = true
        statusLabel.Text = "Starting..."
        statusLabel.Parent = panel

        local stopEvent = Instance.new("BindableEvent")
        stopEvent.Name = "StopRequested"
        stopEvent.Parent = gui
        connect(stopEvent.Event, function(reason) stop(reason or "replaced-by-new-run") end)
        connect(button.Activated, function() stop("stop-button") end)
        connect(gui.Destroying, function()
            if controlGui == gui then controlGui = nil end
            stop("control-removed")
        end)
        local pointer, pressedAt, panelAt
        local function place(position)
            local bounds, size = host.AbsoluteSize, panel.AbsoluteSize
            panel.Position = UDim2.fromOffset(
                math.clamp(position.X, 0, math.max(0, bounds.X - size.X)),
                math.clamp(position.Y, 0, math.max(0, bounds.Y - size.Y))
            )
        end
        connect(handle.InputBegan, function(input)
            if pointer or (input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch) then return end
            pointer = input
            pressedAt = Vector2.new(input.Position.X, input.Position.Y)
            panelAt = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        end)
        connect(inputService.InputChanged, function(input)
            if not pointer or not running then return end
            local touch = pointer.UserInputType == Enum.UserInputType.Touch
            if (touch and input ~= pointer)
                or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
            place(panelAt + Vector2.new(input.Position.X, input.Position.Y) - pressedAt)
        end)
        connect(inputService.InputEnded, function(input) if input == pointer then pointer = nil end end)
        connect(inputService.WindowFocusReleased, function() pointer = nil end)
        connect(host:GetPropertyChangedSignal("AbsoluteSize"), function()
            pointer = nil
            place(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset))
        end)
        gui.Parent = playerGui
        place(Vector2.new(20, 300))
    end

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
end
