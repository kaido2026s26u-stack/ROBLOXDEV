-- RXDEV view and drag handling. All connections belong to the app scope.
local module = {}
function module.create(connect, config)
    local UIS = game:GetService("UserInputService")
    local gui = Instance.new("ScreenGui")
    gui.Name = config.guiName
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
    title.Text = "RXDEV v" .. config.version .. "  -  drag"
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
    place(Vector2.new(20, 160))
    return {gui=gui, antiButton=antiButton, consoleButton=consoleButton,
        fastButton=fastButton, extremeButton=extremeButton, allButton=allButton,
        status=status, performance=performance, fill=fill}
end
return module
