-- Stationary chaotic spinning dance. STOP restores normal character control.
-- Shares the character-control slot with BounceMove to avoid competing forces.
do
    print("[EverydayShufflling] Loaded revision 1")
    local LAUNCH_DELAY = 3
    local MIN_SPIN = 5 * 2 * math.pi -- Target radians/second
    local MAX_SPIN = 9 * 2 * math.pi
    local MIN_INTERVAL, MAX_INTERVAL = 0.125, 0.5
    local SPIN_RESPONSE = 24
    local HOLD_RESPONSE = 14
    local MAX_HOLD_ACCEL = 180
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or not root:IsA("BasePart") then
        warn("[EverydayShufflling] Character is not ready.")
        return
    end
    local assemblyRoot = root.AssemblyRootPart
    local mass = root.AssemblyMass
    if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
        or root.Anchored or (assemblyRoot and assemblyRoot.Anchored)
        or mass <= 0 or mass == math.huge then
        warn("[EverydayShufflling] Cannot launch in the current state.")
        return
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then warn("[EverydayShufflling] PlayerGui is unavailable."); return end
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
            warn("[EverydayShufflling] Previous run has not stopped; refusing duplicate.")
            return
        end
    end

    local running = true
    local cleanupDone = false
    local connections = {}
    local temporaryInstances = {}
    local controlGui
    local floorCount = 0
    local finishReason = "stopped"
    local oldAutoRotate = humanoid.AutoRotate
    local changed = false
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
        for i = #temporaryInstances, 1, -1 do
            local object = temporaryInstances[i]
            pcall(function() object:Destroy() end)
        end
        table.clear(temporaryInstances)
        if changed then
            local restored, restoreErr = pcall(function()
                if humanoid.Parent then humanoid.AutoRotate = oldAutoRotate end
            end)
            if not restored then warn("[EverydayShufflling] Restore failed: " .. tostring(restoreErr)) end
            local recovered, recoveryErr = pcall(function()
                if isCurrent() then
                    -- End the scripted movement, then let ordinary gravity take over.
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
            if not recovered then warn("[EverydayShufflling] Recovery failed: " .. tostring(recoveryErr)) end
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
        handle.Text = "SHUFFLLING  -  drag"
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
        button.Text = "STOP SHUFFLLING"
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

        print("[EverydayShufflling] Starting in 3 seconds. STOP to finish.")
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

        oldAutoRotate = humanoid.AutoRotate
        changed = true
        humanoid.AutoRotate = false
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        local origin = root.Position
        local attachment = Instance.new("Attachment")
        table.insert(temporaryInstances, attachment)
        attachment.Name = "ROBLOXDEV_ShuffleAttachment"
        attachment.Parent = root
        local spin = Instance.new("AngularVelocity")
        table.insert(temporaryInstances, spin)
        spin.Name = "ROBLOXDEV_ShuffleSpin"
        spin.Attachment0 = attachment
        spin.RelativeTo = Enum.ActuatorRelativeTo.World
        spin.ReactionTorqueEnabled = false
        spin.MaxTorque = root.AssemblyMass * 20000
        spin.Parent = root
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { character }
        rayParams.RespectCanCollide = true
        local function between(low, high) return low + (high - low) * math.random() end
        local function validAssembly()
            local m = root.AssemblyMass
            local ar = root.AssemblyRootPart
            return m > 0 and m < math.huge and not root.Anchored and not (ar and ar.Anchored)
        end
        local function setVelocity(target)
            root:ApplyImpulse((target - root.AssemblyLinearVelocity) * root.AssemblyMass)
        end
        local function randomSpin()
            -- Uniform sphere sampling gives every world-space axis equal probability.
            local y, angle = between(-1, 1), between(0, 2 * math.pi)
            local radius = math.sqrt(math.max(0, 1 - y * y))
            return Vector3.new(radius * math.cos(angle), y, radius * math.sin(angle))
                * between(MIN_SPIN, MAX_SPIN)
        end
        local desiredSpin = randomSpin()
        local nextSpinAt = os.clock() + between(MIN_INTERVAL, MAX_INTERVAL)
        spin.AngularVelocity = desiredSpin
        print(string.format("[EverydayShufflling] Spin target: %.2f rps", desiredSpin.Magnitude / (2 * math.pi)))
        local function hop()
            local velocity = root.AssemblyLinearVelocity
            -- Broad height variation, approximately 2 to 4 studs at default gravity.
            local gravity = math.max(workspace.Gravity, 1)
            local speed = math.sqrt(2 * gravity * between(2, 4))
            setVelocity(Vector3.new(velocity.X, speed, velocity.Z))
        end
        hop()
        local started = os.clock()
        local lastHopAt, lastHopY = started, root.Position.Y
        local armed, falling, fallingAt, settled = false, nil, -math.huge, 0
        -- Refresh once at launch, keeping only physical body parts, not accessories.
        local bodyParts = {}
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide
                and not part:FindFirstAncestorOfClass("Accessory") then
                table.insert(bodyParts, part)
            end
        end

        local function getFloor()
            local support = humanoid.HipHeight + root.Size.Y / 2
            local best = workspace:Raycast(root.Position,
                -Vector3.yAxis * math.max(4, support + 2), rayParams)
            if best and best.Normal.Y <= 0.6 then best = nil end
            -- Limb/torso probes help when the character is tilted or tumbling.
            for _, part in ipairs(bodyParts) do
                if part.Parent and part.CanCollide then
                    local cf, size = part.CFrame, part.Size
                    local halfHeight = (math.abs(cf.RightVector.Y) * size.X
                        + math.abs(cf.UpVector.Y) * size.Y
                        + math.abs(cf.LookVector.Y) * size.Z) / 2
                    local hit = workspace:Raycast(part.Position,
                        -Vector3.yAxis * (halfHeight + 0.6), rayParams)
                    if hit and hit.Normal.Y > 0.6 and (not best or hit.Distance < best.Distance) then
                        best = hit
                    end
                end
            end
            return best
        end

        while running and isCurrent() do
            local dt = RunService.Heartbeat:Wait()
            if not running then break end
            if not isCurrent() then finishReason = "character-changed-or-dead"; break end
            if not validAssembly() or humanoid.Sit or humanoid.PlatformStand then
                finishReason = "character-state-changed"; break
            end
            local now = os.clock()
            local step = math.clamp(dt, 0, 0.1)
            if now >= nextSpinAt then
                desiredSpin = randomSpin()
                nextSpinAt = now + between(MIN_INTERVAL, MAX_INTERVAL)
                print(string.format("[EverydayShufflling] Spin target: %.2f rps", desiredSpin.Magnitude / (2 * math.pi)))
            end
            spin.MaxTorque = root.AssemblyMass * 20000
            spin.AngularVelocity = spin.AngularVelocity:Lerp(desiredSpin, 1 - math.exp(-SPIN_RESPONSE * step))
            -- A clamp handles unexpectedly strong collision spin, not the normal drive.
            local angular = root.AssemblyAngularVelocity
            if angular.Magnitude > MAX_SPIN * 1.25 then
                root.AssemblyAngularVelocity = angular.Unit * MAX_SPIN * 1.25
            end
            local velocity = root.AssemblyLinearVelocity
            local floor = getFloor()
            if not armed and now - lastHopAt > 0.05 and root.Position.Y > lastHopY + 0.2
                and velocity.Y > 0 then armed = true end
            local impact = floor and armed and falling and now - fallingAt < 0.6
                and falling:Dot(floor.Normal) < -5
                and velocity:Dot(floor.Normal) > falling:Dot(floor.Normal) * 0.6
            if floor and math.abs(velocity.Y) < 6 then settled += dt else settled = 0 end
            if now - lastHopAt > 0.18 and (impact or settled >= 0.45) then
                hop()
                floorCount += 1
                lastHopAt, lastHopY = now, root.Position.Y
                armed, falling, settled = false, nil, 0
                velocity = root.AssemblyLinearVelocity
            elseif velocity.Y < -5 then
                falling, fallingAt = velocity, now
            end
            -- Hold only X/Z. Height and gravity remain independent of the hold.
            local offset = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
            local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
            local target = -offset * 8
            if target.Magnitude > 20 then target = target.Unit * 20 end
            local change = (target - horizontal) * (1 - math.exp(-HOLD_RESPONSE * step))
            local limit = MAX_HOLD_ACCEL * step
            if change.Magnitude > limit then change = change.Unit * limit end
            if change.Magnitude > 0.00001 then setVelocity(velocity + change) end
        end
        if running and not isCurrent() then finishReason = "character-changed-or-dead" end
    end, function(message) return tostring(message) end)
    running = false
    if not ok then finishReason = "error" end
    cleanup()
    print(string.format("[EverydayShufflling] End: %s; bounces=%d", finishReason, floorCount))
    if not ok then warn("[EverydayShufflling] " .. err) end
end
