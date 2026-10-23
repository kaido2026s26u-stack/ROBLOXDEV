-- Developer Console button v1. Mouse and touch supported.
-- Tap CONSOLE to open Roblox's Developer Console; hold and drag to move.
do
    local Players = game:GetService("Players")
    local UIS = game:GetService("UserInputService")
    local StarterGui = game:GetService("StarterGui")
    local player = Players.LocalPlayer
    if not player then
        warn("[ConsoleButton] Run on the local client.")
        return
    end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local NAME = "ROBLOXDEV_ConsoleButton"
    local previous = playerGui:FindFirstChild(NAME)
    if previous then previous:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = NAME
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 1000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local host = Instance.new("Frame")
    host.Size = UDim2.fromScale(1, 1)
    host.BackgroundTransparency = 1
    host.Parent = gui

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(144, 44)
    panel.Position = UDim2.fromOffset(20, 100)
    panel.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    panel.BorderSizePixel = 0
    panel.Parent = host
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = panel

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -32, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = "CONSOLE"
    button.Font = Enum.Font.GothamBold
    button.TextSize = 14
    button.TextColor3 = Color3.fromRGB(224, 235, 255)
    button.Active = true
    button.Parent = panel

    local close = Instance.new("TextButton")
    close.Size = UDim2.fromOffset(32, 44)
    close.Position = UDim2.new(1, -32, 0, 0)
    close.BackgroundTransparency = 1
    close.Text = "X"
    close.Font = Enum.Font.Gotham
    close.TextSize = 14
    close.TextColor3 = Color3.fromRGB(160, 170, 190)
    close.Parent = panel

    local connections = {}
    local alive = true
    local busy = false
    local pointer, pressPosition, panelPosition
    local dragged = false

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
    end

    local function place(position)
        local bounds = host.AbsoluteSize
        local size = panel.AbsoluteSize
        panel.Position = UDim2.fromOffset(
            math.clamp(position.X, 0, math.max(0, bounds.X - size.X)),
            math.clamp(position.Y, 0, math.max(0, bounds.Y - size.Y))
        )
    end

    local function openConsole()
        if busy or not alive then return end
        busy = true
        task.spawn(function()
            local lastError
            for _ = 1, 10 do
                if not alive then busy = false; return end
                local ok, err = pcall(function()
                    StarterGui:SetCore("DevConsoleVisible", true)
                end)
                if ok then
                    busy = false
                    return
                end
                lastError = err
                task.wait(0.1)
            end
            busy = false
            if alive then
                warn("[ConsoleButton] Could not open console: " .. tostring(lastError))
                button.Text = "RETRY"
            end
        end)
    end

    connect(button.InputBegan, function(input)
        local kind = input.UserInputType
        if pointer or (kind ~= Enum.UserInputType.MouseButton1
            and kind ~= Enum.UserInputType.Touch) then return end
        pointer = input
        pressPosition = Vector2.new(input.Position.X, input.Position.Y)
        panelPosition = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        dragged = false
    end)

    connect(UIS.InputChanged, function(input)
        if not pointer then return end
        local touch = pointer.UserInputType == Enum.UserInputType.Touch
        if (touch and input ~= pointer)
            or (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - pressPosition
        if delta.Magnitude >= 8 then dragged = true end
        if dragged then place(panelPosition + delta) end
    end)

    connect(UIS.InputEnded, function(input)
        if not pointer or input ~= pointer then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - pressPosition
        local shouldOpen = not dragged and delta.Magnitude < 8
        pointer = nil
        if shouldOpen then openConsole() end
    end)

    connect(UIS.WindowFocusReleased, function()
        pointer = nil
    end)

    -- Keyboard/gamepad activation; mouse/touch taps are handled above.
    connect(button.Activated, function(input)
        if input and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then return end
        openConsole()
    end)
    connect(close.Activated, function() gui:Destroy() end)
    connect(host:GetPropertyChangedSignal("AbsoluteSize"), function()
        pointer = nil
        place(Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset))
    end)
    gui.Destroying:Connect(function()
        alive = false
        pointer = nil
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
    end)

    gui.Parent = playerGui
    place(Vector2.new(20, 100))
    print("[ConsoleButton] Ready v1. Tap to open; drag to move; X to remove.")
end
