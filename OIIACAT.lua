-- Deterministic OIIACAT dance: 2s spin, 1.5s stare. STOP restores control.
do
    print("[OIIACAT] Loaded revision 1")
    local LAUNCH_DELAY = 3
    local SPIN_RPS = 5
    local SPIN_SECONDS = 2
    local STARE_SECONDS = 1.5
    local HOVER_HEIGHT = 3
    local HOVER_AMPLITUDE = 0.75
    local HOVER_PERIOD = 2
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or not root:IsA("BasePart") then
        warn("[OIIACAT] Character is not ready.")
        return
    end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then warn("[OIIACAT] PlayerGui is unavailable."); return end
    local GUI_NAME = "ROBLOXDEV_SelfLaunchControl"
    local previousControl = playerGui:FindFirstChild(GUI_NAME)
    if previousControl then
        local previousStop = previousControl:FindFirstChild("StopRequested")
        if previousStop and previousStop:IsA("BindableEvent") then
            previousStop:Fire("replaced-by-new-run")
            for _ = 1, 20 do
                if not previousControl.Parent then break end
                task.wait(0.05)
            end
        end
        if previousControl.Parent then
            warn("[OIIACAT] Previous run has not stopped; refusing duplicate.")
            return
        end
    end

    local assemblyRoot = root.AssemblyRootPart
    local mass = root.AssemblyMass
    if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
        or root.Anchored or (assemblyRoot and assemblyRoot.Anchored)
        or mass <= 0 or mass == math.huge then
        warn("[OIIACAT] Cannot launch in the current state.")
        return
    end

    local running = true
    local cleanupDone = false
    local connections = {}
    local temporaryInstances = {}
    local controlGui
    local finishReason = "stopped"
    local oldAutoRotate = humanoid.AutoRotate
    local oldAnchored = root.Anchored
    local changed = false
    local cameraSnapshot
    local function isCurrent()
        return player.Character == character
            and character.Parent ~= nil
            and humanoid.Parent ~= nil
            and root:IsDescendantOf(character)
            and humanoid.Health > 0
    end

    local function cleanup()
        if cleanupDone then return end
        cleanupDone = true
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        if cameraSnapshot then
            local saved = cameraSnapshot
            cameraSnapshot = nil
            local restored, restoreErr = pcall(function()
                local camera = saved.camera
                if not camera.Parent then return end
                camera.CFrame, camera.Focus = saved.cframe, saved.focus
                local subject = saved.subject
                if subject == humanoid and player.Character ~= character then
                    subject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                end
                if subject and subject.Parent then camera.CameraSubject = subject end
                camera.CameraType = saved.kind
            end)
            if not restored then warn("[OIIACAT] Camera restore failed: " .. tostring(restoreErr)) end
        end
        for i = #temporaryInstances, 1, -1 do
            local object = temporaryInstances[i]
            pcall(function() object:Destroy() end)
        end
        table.clear(temporaryInstances)
        if changed then
            local restored, restoreErr = pcall(function()
                if humanoid.Parent then humanoid.AutoRotate = oldAutoRotate end
                if root.Parent then root.Anchored = oldAnchored end
            end)
            if not restored then warn("[OIIACAT] Restore failed: " .. tostring(restoreErr)) end
            local recovered, recoveryErr = pcall(function()
                if isCurrent() then
                    -- End the scripted movement, then let ordinary gravity take over.
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
            if not recovered then warn("[OIIACAT] Recovery failed: " .. tostring(recoveryErr)) end
        end
        if controlGui then
            local gui = controlGui
            controlGui = nil
            gui:Destroy()
        end
    end

    local function stop(reason)
        if not running then return end
        running = false
        finishReason = reason or "stop-button"
        cleanup()
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
        panel.Position = UDim2.fromOffset(20, 160)
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
        handle.Text = "OIIACAT  -  drag"
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
        button.Text = "STOP OIIACAT"
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
        connect(humanoid.Died, function() stop("character-died") end)
        connect(player.CharacterRemoving, function(oldCharacter)
            if oldCharacter == character then stop("character-removed") end
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
        place(Vector2.new(20, 160))
    end

    local ok, err = xpcall(function()
        makeControl()

        print("[OIIACAT] Starting in 3 seconds. STOP to finish.")
        local remaining = LAUNCH_DELAY
        while running and remaining > 0.000001 do
            local interval = math.min(0.05, remaining)
            task.wait(interval)
            remaining = remaining - interval
            if not isCurrent() then stop("character-changed-or-dead"); return end
        end
        if not running then return end
        if not isCurrent() then finishReason = "character-changed-or-dead"; return end
        assemblyRoot = root.AssemblyRootPart
        mass = root.AssemblyMass
        if humanoid.Sit or humanoid.PlatformStand or root.Anchored
            or (assemblyRoot and assemblyRoot.Anchored)
            or mass <= 0 or mass == math.huge then
            finishReason = "character-state-changed"; return
        end

        local camera = workspace.CurrentCamera
        if not camera then finishReason = "camera-unavailable"; return end
        local origin = root.Position
        cameraSnapshot = {
            camera = camera, kind = camera.CameraType, subject = camera.CameraSubject,
            cframe = camera.CFrame, focus = camera.Focus,
        }
        -- Only the camera subject is fixed. Roblox's normal camera controller
        -- owns orbit, zoom, CFrame and Focus throughout the dance.
        local cameraTarget = Instance.new("Part")
        table.insert(temporaryInstances, cameraTarget)
        cameraTarget.Name = "ROBLOXDEV_OIIACameraTarget"
        cameraTarget.Size = Vector3.new(0.2, 0.2, 0.2)
        cameraTarget.Anchored = true
        cameraTarget.Transparency = 1
        cameraTarget.CanCollide = false
        cameraTarget.CanTouch = false
        cameraTarget.CanQuery = false
        cameraTarget.CastShadow = false
        cameraTarget.CFrame = CFrame.new(origin + Vector3.yAxis * HOVER_HEIGHT)
        cameraTarget.Parent = workspace
        camera.CameraSubject = cameraTarget
        camera.CameraType = Enum.CameraType.Custom
        connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
            if workspace.CurrentCamera ~= camera then stop("camera-replaced") end
        end)
        connect(cameraTarget.Destroying, function() stop("camera-target-removed") end)
        oldAutoRotate = humanoid.AutoRotate
        changed = true
        humanoid.AutoRotate = false
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        -- Exact pose animation rather than ballistic simulation. Only this root
        -- is temporarily anchored; all existing joints remain intact.
        oldAnchored = root.Anchored
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        local look = root.CFrame.LookVector
        local forward = Vector3.new(look.X, 0, look.Z)
        if forward.Magnitude < 0.001 then forward = Vector3.new(0, 0, -1) end
        local spinRotation = CFrame.lookAt(Vector3.zero, forward.Unit)
        local stareRotation = spinRotation
        local cycleSeconds = SPIN_SECONDS + STARE_SECONDS
        local started = os.clock()
        local lastCycle, wasStaring = 0, false
        local function updatePose()
            local elapsed = math.max(0, os.clock() - started)
            local cycle = math.floor(elapsed / cycleSeconds)
            local phase = elapsed - cycle * cycleSeconds
            local staring = phase >= SPIN_SECONDS
            if cycle ~= lastCycle then
                spinRotation = stareRotation
                lastCycle = cycle
                wasStaring = false
            end
            local position = origin + Vector3.yAxis * HOVER_HEIGHT
            local rotation
            if staring then
                if not wasStaring then
                    -- Snapshot once. Moving the camera during this pause does not
                    -- turn the body into a tracking turret.
                    local toward = camera.CFrame.Position - position
                    toward = Vector3.new(toward.X, 0, toward.Z)
                    if toward.Magnitude > 0.001 then
                        stareRotation = CFrame.lookAt(Vector3.zero, toward.Unit)
                    else
                        stareRotation = spinRotation
                    end
                end
                rotation = stareRotation
            else
                position += Vector3.yAxis * (HOVER_AMPLITUDE * math.sin(2 * math.pi * phase / HOVER_PERIOD))
                rotation = spinRotation * CFrame.Angles(0, 2 * math.pi * SPIN_RPS * phase, 0)
            end
            wasStaring = staring
            root.CFrame = CFrame.new(position) * rotation
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        updatePose()
        while running and isCurrent() do
            RunService.Heartbeat:Wait()
            if not running then break end
            if not isCurrent() then finishReason = "character-changed-or-dead"; break end
            if humanoid.Sit or humanoid.PlatformStand then finishReason = "character-state-changed"; break end
            updatePose()
        end
        if running and not isCurrent() then finishReason = "character-changed-or-dead" end
    end, function(message) return tostring(message) end)
    running = false
    if not ok then finishReason = "error" end
    cleanup()
    print("[OIIACAT] End: " .. finishReason)
    if not ok then warn("[OIIACAT] " .. err) end
end
