-- Experimental native text-input switch. No keyboard injection or focus changes.
do
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local GUI_NAME = "ROBLOXDEV_NativeInputTest"
    local previous = playerGui:FindFirstChild(GUI_NAME)
    if previous then previous:Destroy() end
    local running = true
    local connections = {}
    local originals = {}
    local controlGui, statusLabel
    local applied, failed = 0, 0
    local function refresh()
        if statusLabel then
            statusLabel.Text = string.format("ShowNativeInput = false\nTextBoxes %d / Failed %d\nRefocus a text box to test", applied, failed)
        end
    end
    local function stop(reason)
        if not running then return end
        running = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        local restored = 0
        for box, original in pairs(originals) do
            pcall(function()
                if box.Parent and box.ShowNativeInput == false then
                    box.ShowNativeInput = original
                    restored += 1
                end
            end)
        end
        table.clear(originals)
        if controlGui then
            local gui = controlGui
            controlGui = nil
            gui:Destroy()
        end
        warn(string.format("[NativeInputTest r1] Stopped: %s; restored=%d", tostring(reason), restored))
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
        handle.Text = "TEXT INPUT TEST  -  drag"
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
        button.Text = "STOP / RESTORE"
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
        local function apply(box)
            if not running or not box:IsA("TextBox") then return end
            local worked, applyErr = pcall(function()
                if originals[box] == nil then
                    originals[box] = box.ShowNativeInput
                    applied += 1
                end
                box.ShowNativeInput = false
            end)
            if not worked then
                failed += 1
                warn("[NativeInputTest r1] Cannot apply: " .. tostring(applyErr))
            end
            refresh()
            return worked
        end
        local function watch(root, label)
            local watched, watchErr = pcall(function()
                connect(root.DescendantAdded, apply)
                for _, object in ipairs(root:GetDescendants()) do apply(object) end
            end)
            warn(string.format("[NativeInputTest r1] %s: %s", label, watched and "scanned" or tostring(watchErr)))
        end
        watch(playerGui, "PlayerGui")
        local accessible, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if accessible and coreGui then watch(coreGui, "CoreGui/chat")
        else warn("[NativeInputTest r1] CoreGui unavailable: " .. tostring(coreGui)) end
        connect(UserInputService.TextBoxFocused, function(box)
            local worked = apply(box)
            warn("[NativeInputTest r1] Focused TextBox: " .. tostring(box.Name) .. "; applied=" .. tostring(worked))
        end)
        refresh()
        warn("[NativeInputTest r1] Ready. Close and refocus an input field; STOP restores previous settings.")
    end, function(message) return tostring(message) end)
    if not ok then warn("[NativeInputTest r1] " .. err); stop("error") end
end
