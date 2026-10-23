-- Idle-event AntiAFK. No movement, camera control, shared globals or permanent loops.
do
    print("[AntiAFK] Loaded revision 1")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local GUI_NAME = "ROBLOXDEV_AntiAFK"
    local previous = playerGui:FindFirstChild(GUI_NAME)
    if previous then previous:Destroy() end
    local running, enabled, injecting = true, true, false
    local connections = {}
    local controlGui
    local lastActivity = os.clock()
    local lastPulse = -math.huge
    local virtualUser
    local pendingRelease, pulsePosition, pulseCamera = false, nil, nil
    local function release()
        if not pendingRelease then return true end
        local ok, err = pcall(function() virtualUser:Button2Up(pulsePosition, pulseCamera) end)
        if ok then pendingRelease = false end
        return ok, err
    end
    local function stop(reason)
        if not running then return end
        running = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        local released, err = release()
        if not released then warn("[AntiAFK] Could not release virtual button: " .. tostring(err)) end
        if controlGui then
            local gui = controlGui
            controlGui = nil
            gui:Destroy()
        end
        print("[AntiAFK] Stopped: " .. tostring(reason or "stop-button"))
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
        panel.Size = UDim2.fromOffset(184, 78)
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
        handle.Text = "ANTI AFK  -  drag"
        handle.TextColor3 = Color3.fromRGB(210, 220, 235)
        handle.Font = Enum.Font.GothamBold
        handle.TextSize = 12
        handle.Active = true
        handle.Parent = panel

        local button = Instance.new("TextButton")
        button.Name = "StopButton"
        button.Size = UDim2.new(1, -16, 0, 40)
        button.Position = UDim2.fromOffset(8, 30)
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
        virtualUser = game:GetService("VirtualUser")
        local function activity()
            if not injecting then lastActivity = os.clock() end
        end
        connect(UserInputService.InputBegan, activity)
        connect(UserInputService.InputChanged, activity)
        connect(UserInputService.InputEnded, activity)
        connect(UserInputService.TextBoxFocused, activity)
        connect(UserInputService.TextBoxFocusReleased, activity)
        connect(UserInputService.WindowFocused, activity)
        connect(player.Idled, function()
            if not running or not enabled or injecting then return end
            local now = os.clock()
            if now - lastActivity < 3 or now - lastPulse < 30 then return end
            local checked, busy = pcall(function()
                return UserInputService:GetFocusedTextBox() ~= nil
                    or #UserInputService:GetKeysPressed() > 0
                    or #UserInputService:GetMouseButtonsPressed() > 0
                    or #UserInputService:GetTouches() > 0
            end)
            if not checked then
                enabled = false
                warn("[AntiAFK] Input check unavailable; disabled: " .. tostring(busy))
                return
            end
            if busy then return end
            local camera = workspace.CurrentCamera
            if not camera then return end
            local prepared, prepareErr = pcall(function()
                pulsePosition = UserInputService:GetMouseLocation()
                pulseCamera = camera.CFrame
            end)
            if not prepared then
                enabled = false
                warn("[AntiAFK] Input preparation unavailable; disabled: " .. tostring(prepareErr))
                return
            end
            injecting = true
            pendingRelease = true
            -- No CaptureController, mouse movement, keyboard input or yield between
            -- down and up. Real input events are never blocked or consumed.
            local pressed, pressErr = pcall(function()
                virtualUser:Button2Down(pulsePosition, pulseCamera)
            end)
            local released, releaseErr = release()
            injecting = false
            lastPulse = now
            if not pressed or not released then
                enabled = false
                warn("[AntiAFK] Virtual input unavailable; disabled: " .. tostring(pressErr or releaseErr))
            else
                print("[AntiAFK] Idle pulse sent.")
            end
        end)
        print("[AntiAFK] Ready. Runs only on Idled; STOP removes it. Survives respawn.")
    end, function(message) return tostring(message) end)
    if not ok then
        warn("[AntiAFK] " .. err)
        stop("error")
    end
end
