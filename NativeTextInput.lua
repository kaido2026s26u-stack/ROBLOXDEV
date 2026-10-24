-- Continuous ShowNativeInput=false enforcement until STOP. No focus or text changes.
do
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
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
    local boxConnections = {}
    local applying = {}
    local failureReported = setmetatable({}, {__mode = "k"})
    local lastCursor = {}
    local missingBox, missingSince
    local caretRepairs = 0
    local controlGui, statusLabel
    local applied, failed, reasserted = 0, 0, 0
    local function refresh()
        if statusLabel then
            statusLabel.Text = string.format("CONTINUOUS: native input OFF\nTextBoxes %d / Failed %d\nReasserted %d / Caret %d", applied, failed, reasserted, caretRepairs)
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
        table.clear(lastCursor)
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
        warn(string.format("[NativeInputTest r3] Stopped: %s; restored=%d", tostring(reason), restored))
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
        handle.Text = "TEXT INPUT r3: CARET"
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
        local apply
        local function forget(box)
            local items = boxConnections[box]
            if items then for _, connection in ipairs(items) do connection:Disconnect() end end
            boxConnections[box], originals[box], applying[box], failureReported[box], lastCursor[box] = nil, nil, nil, nil, nil
        end
        apply = function(box)
            if not running or applying[box] or not box:IsA("TextBox") then return end
            applying[box] = true
            local worked, applyErr = pcall(function()
                if originals[box] == nil then
                    originals[box] = box.ShowNativeInput
                    applied += 1
                    boxConnections[box] = {
                        box:GetPropertyChangedSignal("ShowNativeInput"):Connect(function() apply(box) end),
                        box.Destroying:Connect(function() forget(box) end),
                    }
                end
                if box.ShowNativeInput ~= false then
                    box.ShowNativeInput = false
                    reasserted += 1
                end
            end)
            applying[box] = nil
            if not worked and not failureReported[box] then
                failureReported[box] = true
                failed += 1
                warn("[NativeInputTest r3] Cannot enforce: " .. tostring(applyErr))
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
            warn(string.format("[NativeInputTest r3] %s: %s", label, watched and "watched" or tostring(watchErr)))
        end
        watch(playerGui, "PlayerGui")
        watch(workspace, "Workspace/SurfaceGui")
        local accessible, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if accessible and coreGui then watch(coreGui, "CoreGui/chat")
        else warn("[NativeInputTest r3] CoreGui unavailable: " .. tostring(coreGui)) end
        connect(UserInputService.TextBoxFocused, function(box)
            apply(box)
        end)
        local function maintainCaret(box)
            if not box then missingBox, missingSince = nil, nil; return end
            local cursor = box.CursorPosition
            if cursor >= 1 then
                lastCursor[box] = cursor
                missingBox, missingSince = nil, nil
                return
            end
            if not box.TextEditable then return end
            local now = os.clock()
            if missingBox ~= box then missingBox, missingSince = box, now; return end
            if now - missingSince < 0.05 then return end
            local text = box.Text
            local position = math.clamp(lastCursor[box] or (#text + 1), 1, #text + 1)
            -- CursorPosition uses UTF-8 byte offsets; avoid the middle of a code point.
            while position > 1 do
                local byte = string.byte(text, position)
                if not byte or byte < 128 or byte >= 192 then break end
                position -= 1
            end
            if UserInputService:GetFocusedTextBox() ~= box then return end
            box.CursorPosition = position
            lastCursor[box] = position
            caretRepairs += 1
            missingBox, missingSince = nil, nil
            warn(string.format("[NativeInputTest r3] Standard caret repaired: %s cursor=%d", box.Name, position))
        end
        local nextScan, nextUI = os.clock() + 0.5, 0
        connect(RunService.RenderStepped, function()
            if not running then return end
            -- Property events handle normal writes immediately. Each frame also
            -- rechecks tracked fields and the focused field without dropping focus.
            for box in pairs(originals) do apply(box) end
            pcall(function()
                local box = UserInputService:GetFocusedTextBox()
                if box then apply(box) end
                maintainCaret(box)
            end)
            local now = os.clock()
            if now >= nextScan then
                nextScan = now + 0.5
                for _, root in ipairs(roots) do scan(root) end
            end
            if now >= nextUI then nextUI = now + 0.25; refresh() end
        end)
        refresh()
        warn("[NativeInputTest r3] Native input OFF + standard caret repair ON. Rendering is handled by Roblox; STOP restores settings.")
    end, function(message) return tostring(message) end)
    if not ok then warn("[NativeInputTest r3] " .. err); stop("error") end
end
