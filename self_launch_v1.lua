-- Keyboard bounce movement: runs until STOP. No files or shared globals.
-- A new execution requests cleanup of the previous execution first.
do
    print("[BounceMove] Loaded revision 12")
    local MOVE_SPEED = 32       -- Horizontal target speed in studs/second
    local BOUNCE_SPEED = 60     -- About 9.2 studs at default gravity, before variation
    local HEIGHT_VARIATION = 0.08
    local SPIN_STRENGTH = 6     -- Angular impulse per unit mass
    local SPIN_RETENTION = 0.8
    local MAX_SPIN_SPEED = 10   -- Radians/second; cap collision and scripted spin
    local STEER_RESPONSE = 2
    local BRAKE_RESPONSE = 0.65
    local MAX_STEER_ACCEL = 40
    local WALL_RETENTION = 0.75
    local WALL_CONTROL_DELAY = 0.25
    local MIN_IMPACT_SPEED = 5
    local LAUNCH_DELAY = 3

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or not root:IsA("BasePart") then
        warn("[BounceMove] Character is not ready.")
        return
    end
    local assemblyRoot = root.AssemblyRootPart
    local mass = root.AssemblyMass
    if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
        or root.Anchored or (assemblyRoot and assemblyRoot.Anchored)
        or mass <= 0 or mass == math.huge then
        warn("[BounceMove] Cannot launch in the current state.")
        return
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then warn("[BounceMove] PlayerGui is unavailable."); return end
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
            warn("[BounceMove] Previous run has not stopped; refusing duplicate.")
            return
        end
    end

    local running = true
    local cleanupDone = false
    local connections = {}
    local temporaryInstances = {}
    local held = {}
    local windowFocused = true
    local controlGui
    local floorCount, wallCount = 0, 0
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
        table.clear(held)
        for i = #temporaryInstances, 1, -1 do
            local object = temporaryInstances[i]
            pcall(function() object:Destroy() end)
        end
        table.clear(temporaryInstances)
        if changed then
            local restored, restoreErr = pcall(function()
                if humanoid.Parent then humanoid.AutoRotate = oldAutoRotate end
            end)
            if not restored then warn("[BounceMove] Restore failed: " .. tostring(restoreErr)) end
            local recovered, recoveryErr = pcall(function()
                if isCurrent() then
                    -- End the scripted movement, then let ordinary gravity take over.
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
            if not recovered then warn("[BounceMove] Recovery failed: " .. tostring(recoveryErr)) end
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
        handle.Text = "BOUNCE MOVE  -  drag"
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
        button.Text = "STOP BOUNCE MOVE"
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

        print("[BounceMove] Starting in 3 seconds. WASD to steer; STOP to finish.")
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

        oldAutoRotate = humanoid.AutoRotate
        changed = true
        humanoid.AutoRotate = false
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)

        -- No orientation constraint: the whole connected character can tumble.
        -- Motor6D joints remain intact; this is not a joint-based ragdoll.
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { character }
        rayParams.RespectCanCollide = true

        local function applyTarget(target)
            local currentMass = root.AssemblyMass
            assemblyRoot = root.AssemblyRootPart
            if currentMass <= 0 or currentMass == math.huge or root.Anchored
                or (assemblyRoot and assemblyRoot.Anchored) then return false end
            root:ApplyImpulse((target - root.AssemblyLinearVelocity) * currentMass)
            return true
        end
        local function centeredRandom()
            -- Triangular distribution favors small changes over extremes.
            return math.random() + math.random() - 1
        end
        local function bounceSpeed()
            return BOUNCE_SPEED * (1 + HEIGHT_VARIATION * centeredRandom())
        end
        local function capSpin()
            local angular = root.AssemblyAngularVelocity
            if angular.Magnitude > MAX_SPIN_SPEED then
                root.AssemblyAngularVelocity = angular.Unit * MAX_SPIN_SPEED
            end
        end
        local function tumble(scale)
            local angular = root.AssemblyAngularVelocity
            local randomAxis = Vector3.new(centeredRandom(), centeredRandom() * 0.7, centeredRandom())
            if randomAxis.Magnitude < 0.001 then randomAxis = Vector3.xAxis end
            local axis = randomAxis.Unit
            if angular.Magnitude > 1 then
                -- Preserve spin direction rather than abruptly reversing it.
                axis = (angular.Unit * 0.65 + axis * 0.35).Unit
            end
            root.AssemblyAngularVelocity = angular * SPIN_RETENTION
            root:ApplyAngularImpulse(axis * root.AssemblyMass * SPIN_STRENGTH * scale)
            capSpin()
        end
        if not applyTarget(Vector3.yAxis * bounceSpeed()) then finishReason = "invalid-assembly"; return end
        tumble(1)

        local started = os.clock()
        local floorArmed = true
        local lastFloorTime, lastWallTime = -math.huge, -math.huge
        local lastFloorY = nil
        local fallingVelocity, fallingAt = nil, -math.huge
        local wallVelocity, wallVelocityAt = nil, -math.huge
        local settledFor = 0
        local nextStatusAt = started + 3

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

        local function getWall(incoming, dt)
            local horizontal = Vector3.new(incoming.X, 0, incoming.Z)
            if horizontal.Magnitude < MIN_IMPACT_SPEED then return nil end
            local direction = horizontal.Unit
            local best
            local function probe(part)
                if not part.Parent then return end
                local reach = math.max(1, part.Size.Magnitude / 2 + 0.35)
                    + math.min(horizontal.Magnitude * dt, 3)
                local hit = workspace:Raycast(part.Position, direction * reach, rayParams)
                if hit and math.abs(hit.Normal.Y) < 0.5
                    and (not best or hit.Distance < best.Distance) then best = hit end
            end
            probe(root)
            for _, part in ipairs(bodyParts) do
                if part ~= root and part.CanCollide then probe(part) end
            end
            return best
        end


        local function floorHop(incomingHorizontal, normal, recovery)
            local target = incomingHorizontal + Vector3.yAxis * bounceSpeed()
            local outward = target:Dot(normal)
            if outward < 1 then target = target + Vector3.yAxis * ((1 - outward) / normal.Y) end
            if not applyTarget(target) then return false end
            tumble(1)
            floorCount = floorCount + 1
            lastFloorTime, lastFloorY = os.clock(), root.Position.Y
            floorArmed, settledFor = false, 0
            fallingVelocity, fallingAt = nil, -math.huge
            print(string.format("[BounceMove] %s %d: up %.1f",
                recovery and "Recovery hop" or "Floor", floorCount, target.Y))
            return true
        end

        while running and isCurrent() do
            local dt = RunService.Heartbeat:Wait()
            if not running then break end
            if not isCurrent() then finishReason = "character-changed-or-dead"; break end
            if root.Anchored or humanoid.Sit or humanoid.PlatformStand then
                finishReason = "character-state-changed"; break
            end
            local now = os.clock()
            local velocity = root.AssemblyLinearVelocity
            local floorHit = getFloor()
            local nearGround = floorHit ~= nil
            local floorBounced, wallBounced = false, false

            if not floorArmed and lastFloorY and now - lastFloorTime > 0.05
                and root.Position.Y > lastFloorY + 0.2 and velocity.Y > 0 then
                floorArmed = true
            end
            if nearGround and floorArmed and now - lastFloorTime > 0.18
                and fallingVelocity and now - fallingAt < 0.6 then
                local toward = fallingVelocity:Dot(floorHit.Normal)
                if toward < -MIN_IMPACT_SPEED and velocity:Dot(floorHit.Normal) > toward * 0.6 then
                    local horizontal = Vector3.new(fallingVelocity.X, 0, fallingVelocity.Z)
                    if not floorHop(horizontal, floorHit.Normal, false) then finishReason = "invalid-assembly"; break end
                    floorBounced = true
                end
            end

            if not floorBounced and wallVelocity and now - wallVelocityAt < 0.3
                and now - lastWallTime > WALL_CONTROL_DELAY then
                local hit = getWall(wallVelocity, dt)
                if hit then
                    local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
                    local incoming = Vector3.new(wallVelocity.X, 0, wallVelocity.Z)
                    local toward = incoming:Dot(normal)
                    local current = Vector3.new(velocity.X, 0, velocity.Z):Dot(normal)
                    if toward < -MIN_IMPACT_SPEED and current > toward * 0.6 then
                        local reflected = (incoming - normal * (2 * toward)) * WALL_RETENTION
                        if not applyTarget(reflected + Vector3.yAxis * root.AssemblyLinearVelocity.Y) then
                            finishReason = "invalid-assembly"; break
                        end
                        tumble(0.6)
                        wallCount = wallCount + 1
                        lastWallTime, settledFor, wallBounced = now, 0, true
                        print(string.format("[BounceMove] Wall %d: steering paused %.2fs", wallCount, WALL_CONTROL_DELAY))
                    end
                end
            end

            -- Only horizontal impulses steer/brake. Never overwrite the falling or
            -- rising vertical velocity. Exponential response is frame-rate independent.
            local direction = getMoveDirection()
            capSpin()
            if now - lastWallTime >= WALL_CONTROL_DELAY then
                local current = root.AssemblyLinearVelocity
                local horizontal = Vector3.new(current.X, 0, current.Z)
                local response = if direction.Magnitude > 0 then STEER_RESPONSE else BRAKE_RESPONSE
                local step = math.min(dt, 0.1)
                local change = (direction * MOVE_SPEED - horizontal) * (1 - math.exp(-response * step))
                local maxChange = MAX_STEER_ACCEL * step
                if change.Magnitude > maxChange then change = change.Unit * maxChange end
                if change.Magnitude > 0.00001 then
                    if not applyTarget(current + change) then finishReason = "invalid-assembly"; break end
                end
            end

            velocity = root.AssemblyLinearVelocity
            if not floorBounced and velocity.Y < -MIN_IMPACT_SPEED then
                fallingVelocity, fallingAt = velocity, now
            end
            if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > MIN_IMPACT_SPEED then
                wallVelocity, wallVelocityAt = velocity, now
            end

            if not floorBounced and not wallBounced then
                if nearGround and math.abs(velocity.Y) < 6 and now - lastFloorTime > 0.3
                    and now - lastWallTime > WALL_CONTROL_DELAY and now - started > 0.2 then
                    settledFor = settledFor + dt
                    if settledFor >= 0.45 then
                        if not floorHop(Vector3.new(velocity.X, 0, velocity.Z), floorHit.Normal, true) then
                            finishReason = "invalid-assembly"; break
                        end
                    end
                else
                    settledFor = 0
                end
            end
            if now >= nextStatusAt then
                print(string.format("[BounceMove] Status: floor=%d wall=%d horizontal=%.1f vertical=%.1f",
                    floorCount, wallCount, Vector3.new(velocity.X, 0, velocity.Z).Magnitude, velocity.Y))
                nextStatusAt = now + 3
            end
        end
        if running and not isCurrent() then finishReason = "character-changed-or-dead" end
    end, function(message)
        return tostring(message)
    end)

    running = false
    if not ok then finishReason = "error" end
    cleanup()
    print(string.format("[BounceMove] End: %s; floor=%d wall=%d",
        finishReason, floorCount, wallCount))
    if not ok then warn("[BounceMove] " .. err) else print("[BounceMove] Finished.") end
end
