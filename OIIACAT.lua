-- Physics OIIACAT: fixed 2s spin / 1.5s back-facing pause, WASD hover movement.
do
    print("[OIIACAT] Loaded revision 2")
    local LAUNCH_DELAY = 3
    local SPIN_RPS = 5
    local SPIN_SECONDS = 2
    local STARE_SECONDS = 1.5
    local HOVER_HEIGHT = 3
    local HOVER_AMPLITUDE = 0.75
    local HOVER_PERIOD = 2
    local MOVE_SPEED = 16
    local MAX_HORIZONTAL_ACCEL = 120
    local MAX_VERTICAL_ACCEL = 600
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
    local held = {}
    local windowFocused = true
    local finishReason = "stopped"
    local oldAutoRotate = humanoid.AutoRotate
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
        table.clear(held)
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
        local movementKeys = {
            [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
            [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
        }
        connect(UserInputService.InputBegan, function(input, processed)
            if input.UserInputType ~= Enum.UserInputType.Keyboard or not movementKeys[input.KeyCode] then return end
            if processed or not windowFocused or UserInputService:GetFocusedTextBox() then return end
            held[input.KeyCode] = true
        end)
        connect(UserInputService.InputEnded, function(input)
            if movementKeys[input.KeyCode] then held[input.KeyCode] = nil end
        end)
        connect(UserInputService.TextBoxFocused, function() table.clear(held) end)
        connect(UserInputService.WindowFocusReleased, function()
            windowFocused = false
            table.clear(held)
        end)
        connect(UserInputService.WindowFocused, function() windowFocused = true end)


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
        local look = root.CFrame.LookVector
        local lastForward = Vector3.new(look.X, 0, look.Z)
        if lastForward.Magnitude < 0.001 then lastForward = Vector3.new(0, 0, -1)
        else lastForward = lastForward.Unit end
        local function getMoveDirection()
            if not windowFocused or UserInputService:GetFocusedTextBox() then
                table.clear(held)
                return Vector3.zero
            end
            local x = (held[Enum.KeyCode.D] and 1 or 0) - (held[Enum.KeyCode.A] and 1 or 0)
            local z = (held[Enum.KeyCode.W] and 1 or 0) - (held[Enum.KeyCode.S] and 1 or 0)
            if x == 0 and z == 0 then return Vector3.zero end
            local camera = workspace.CurrentCamera
            local cf = if camera then camera.CFrame else root.CFrame
            local forward = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
            if forward.Magnitude < 0.001 then
                local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
                forward = if right.Magnitude > 0.001 then Vector3.yAxis:Cross(right.Unit) else lastForward
            end
            forward = forward.Unit
            lastForward = forward
            local right = forward:Cross(Vector3.yAxis).Unit
            local direction = forward * z + right * x
            return if direction.Magnitude > 1 then direction.Unit else direction
        end

        local attachment = Instance.new("Attachment")
        table.insert(temporaryInstances, attachment)
        attachment.Name = "ROBLOXDEV_OIIAAttachment"
        -- Align the attachment's primary X axis with the body's vertical Y axis.
        attachment.CFrame = CFrame.Angles(0, 0, math.pi / 2)
        attachment.Parent = root
        local spin = Instance.new("AngularVelocity")
        table.insert(temporaryInstances, spin)
        spin.Name = "ROBLOXDEV_OIIASpin"
        spin.Attachment0 = attachment
        spin.RelativeTo = Enum.ActuatorRelativeTo.World
        spin.ReactionTorqueEnabled = false
        spin.MaxTorque = mass * 20000
        spin.AngularVelocity = Vector3.yAxis * (2 * math.pi * SPIN_RPS)
        spin.Parent = root
        local upright = Instance.new("AlignOrientation")
        table.insert(temporaryInstances, upright)
        upright.Name = "ROBLOXDEV_OIIAOrientation"
        upright.Mode = Enum.OrientationAlignmentMode.OneAttachment
        upright.Attachment0 = attachment
        upright.AlignType = Enum.AlignType.PrimaryAxisParallel
        upright.CFrame = attachment.CFrame
        upright.RigidityEnabled = false
        upright.MaxTorque = mass * 12000
        upright.MaxAngularVelocity = 50
        upright.Responsiveness = 80
        upright.Parent = root
        local center = origin
        local stareRotation = CFrame.lookAt(Vector3.zero, lastForward)
        local cycleSeconds = SPIN_SECONDS + STARE_SECONDS
        local started = os.clock()
        local lastCycle, wasStaring = 0, false
        local function updateControl(dt)
            local step = math.clamp(dt, 0, 0.1)
            local elapsed = math.max(0, os.clock() - started)
            local cycle = math.floor(elapsed / cycleSeconds)
            local phase = elapsed - cycle * cycleSeconds
            local staring = phase >= SPIN_SECONDS
            if cycle ~= lastCycle then lastCycle, wasStaring = cycle, false end
            local direction = getMoveDirection()
            center += direction * MOVE_SPEED * step
            local position = center + Vector3.yAxis * HOVER_HEIGHT
            local verticalFeed = 0
            if staring then
                if not wasStaring then
                    local away = root.Position - camera.CFrame.Position
                    away = Vector3.new(away.X, 0, away.Z)
                    if away.Magnitude < 0.001 then away = lastForward end
                    stareRotation = CFrame.lookAt(Vector3.zero, away.Unit)
                end
                spin.Enabled = false
                upright.AlignType = Enum.AlignType.AllAxes
                upright.CFrame = stareRotation * attachment.CFrame
            else
                upright.AlignType = Enum.AlignType.PrimaryAxisParallel
                upright.CFrame = attachment.CFrame
                spin.Enabled = true
                position += Vector3.yAxis * (HOVER_AMPLITUDE * math.sin(2 * math.pi * phase / HOVER_PERIOD))
                verticalFeed = HOVER_AMPLITUDE * (2 * math.pi / HOVER_PERIOD)
                    * math.cos(2 * math.pi * phase / HOVER_PERIOD)
            end
            wasStaring = staring
            local currentMass = root.AssemblyMass
            spin.MaxTorque, upright.MaxTorque = currentMass * 20000, currentMass * 12000
            local velocity = root.AssemblyLinearVelocity
            local error = position - root.Position
            local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
            local targetHorizontal = direction * MOVE_SPEED + Vector3.new(error.X, 0, error.Z) * 6
            if targetHorizontal.Magnitude > 32 then targetHorizontal = targetHorizontal.Unit * 32 end
            local change = (targetHorizontal - horizontal) * (1 - math.exp(-12 * step))
            local limit = MAX_HORIZONTAL_ACCEL * step
            if change.Magnitude > limit then change = change.Unit * limit end
            local targetY = math.clamp(verticalFeed + error.Y * 12, -30, 30)
            local changeY = (targetY - velocity.Y) * (1 - math.exp(-18 * step)) + workspace.Gravity * step
            changeY = math.clamp(changeY, -MAX_VERTICAL_ACCEL * step, MAX_VERTICAL_ACCEL * step)
            if step > 0 then root:ApplyImpulse((change + Vector3.yAxis * changeY) * currentMass) end
            -- The observation point follows horizontal travel, never body rotation or bobbing.
            cameraTarget.CFrame = CFrame.new(root.Position.X, origin.Y + HOVER_HEIGHT, root.Position.Z)
        end
        updateControl(0)
        while running and isCurrent() do
            local dt = RunService.PreSimulation:Wait()
            if not running then break end
            if not isCurrent() then finishReason = "character-changed-or-dead"; break end
            local currentMass = root.AssemblyMass
            local ar = root.AssemblyRootPart
            if humanoid.Sit or humanoid.PlatformStand or root.Anchored or (ar and ar.Anchored)
                or currentMass <= 0 or currentMass == math.huge then
                finishReason = "character-state-changed"; break
            end
            updateControl(dt)
        end
        if running and not isCurrent() then finishReason = "character-changed-or-dead" end
    end, function(message) return tostring(message) end)
    running = false
    if not ok then finishReason = "error" end
    cleanup()
    print("[OIIACAT] End: " .. finishReason)
    if not ok then warn("[OIIACAT] " .. err) end
end
