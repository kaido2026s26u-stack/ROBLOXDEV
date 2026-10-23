-- Self-launch: runs until STOP is pressed. No files or shared globals.
-- A new execution requests cleanup of the previous execution first.
do
    print("[SelfLaunch] Loaded revision 10")
    local BACK_SPEED = 70       -- Added backward speed (studs/second)
    local UP_SPEED = 80         -- Added upward speed (studs/second)
    local SPEED_VARIATION = 0.10 -- +/-10% for horizontal and upward speeds
    local DIRECTION_SPREAD = 20 -- Initial launch angle spread in degrees
    local BOUNCE_DIRECTION_SPREAD = 24 -- Per-impact yaw, relative to incoming/reflected direction
    local SPIN_STRENGTH = 6     -- Angular impulse per unit mass; tune gently
    local BOUNCE_RESTITUTION = 0.97
    local TANGENTIAL_RETENTION = 0.95
    local WALL_RETENTION = 0.95
    local MIN_BOUNCE_SPEED = 35
    local MIN_IMPACT_SPEED = 8
    local LAUNCH_DELAY = 3      -- Wait before changing character control
    local FORWARD_DISTANCE = 12 -- Scripted approach distance in studs
    local FORWARD_SECONDS = 0.8
    local LIFT_HEIGHT = 4       -- Scripted lift before the physical launch
    local LIFT_SECONDS = 0.4

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or not root:IsA("BasePart") then
        warn("[SelfLaunch] Character is not ready.")
        return
    end
    local assemblyRoot = root.AssemblyRootPart
    local mass = root.AssemblyMass
    if humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
        or root.Anchored or (assemblyRoot and assemblyRoot.Anchored)
        or mass <= 0 or mass == math.huge then
        warn("[SelfLaunch] Cannot launch in the current state.")
        return
    end

    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then warn("[SelfLaunch] PlayerGui is unavailable."); return end
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
            warn("[SelfLaunch] Previous run has not stopped; refusing duplicate.")
            return
        end
    end

    local running = true
    local cleanupDone = false
    local connections = {}
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
        if changed then
            local restored, restoreErr = pcall(function()
                if humanoid.Parent then humanoid.AutoRotate = oldAutoRotate end
            end)
            if not restored then warn("[SelfLaunch] Restore failed: " .. tostring(restoreErr)) end
            local recovered, recoveryErr = pcall(function()
                if isCurrent() then
                    -- End the scripted movement, then let ordinary gravity take over.
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
            if not recovered then warn("[SelfLaunch] Recovery failed: " .. tostring(recoveryErr)) end
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
        handle.Text = "SELF LAUNCH  -  drag"
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
        button.Text = "STOP SELF LAUNCH"
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
        print("[SelfLaunch] Starting approach in 3 seconds.")
        local remaining = LAUNCH_DELAY
        while running and remaining > 0.000001 do
            local interval = math.min(0.05, remaining)
            task.wait(interval)
            remaining = remaining - interval
            if not isCurrent() then stop("character-changed-or-dead"); return end
        end
        if not running then return end
        if not isCurrent() then
            print("[SelfLaunch] Cancelled: character changed or died.")
            return
        end
        assemblyRoot = root.AssemblyRootPart
        mass = root.AssemblyMass
        if humanoid.Sit or humanoid.PlatformStand or root.Anchored
            or (assemblyRoot and assemblyRoot.Anchored)
            or mass <= 0 or mass == math.huge then
            print("[SelfLaunch] Cancelled: current state does not allow launch.")
            return
        end

        local look = root.CFrame.LookVector
        local forward = Vector3.new(look.X, 0, look.Z)
        if forward.Magnitude < 0.001 then
            forward = Vector3.new(0, 0, -1)
        else
            forward = forward.Unit
        end
        local right = forward:Cross(Vector3.yAxis).Unit
        local function randomBetween(minimum, maximum)
            return minimum + (maximum - minimum) * math.random()
        end
        local angle = math.rad(randomBetween(-DIRECTION_SPREAD, DIRECTION_SPREAD))
        local horizontalDirection = -forward * math.cos(angle) + right * math.sin(angle)
        local horizontalSpeed = BACK_SPEED * randomBetween(1 - SPEED_VARIATION, 1 + SPEED_VARIATION)
        local upwardSpeed = UP_SPEED * randomBetween(1 - SPEED_VARIATION, 1 + SPEED_VARIATION)
        local spinImpulse = (
            -right * randomBetween(0.75, 1.25)
            + forward * randomBetween(-0.45, 0.45)
            + Vector3.yAxis * randomBetween(-0.30, 0.30)
        ) * (mass * SPIN_STRENGTH)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = { character }
        rayParams.RespectCanCollide = true

        oldAutoRotate = humanoid.AutoRotate
        changed = true
        humanoid.AutoRotate = false
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        -- Tween-like smoothstep interpolation. No anchors, constraints or Tween objects.
        -- Each phase eases to zero speed before the next phase / physical impulse.
        local function movePhase(offset, duration)
            local startCFrame = root.CFrame
            local elapsed = 0
            while elapsed < duration do
                local dt = RunService.Heartbeat:Wait()
                if not running or not isCurrent() or root.Anchored or humanoid.Sit or humanoid.PlatformStand then
                    return false
                end
                elapsed = math.min(elapsed + dt, duration)
                local alpha = elapsed / duration
                local eased = alpha * alpha * (3 - 2 * alpha)
                local rate = 6 * alpha * (1 - alpha) / duration
                root.CFrame = startCFrame + offset * eased
                root.AssemblyLinearVelocity = offset * rate
                root.AssemblyAngularVelocity = Vector3.zero
            end
            return true
        end

        print("[SelfLaunch] Approach: forward 12 studs, then up 4 studs.")
        if not movePhase(forward * FORWARD_DISTANCE, FORWARD_SECONDS) then return end
        if not movePhase(Vector3.yAxis * LIFT_HEIGHT, LIFT_SECONDS) then return end
        if not running or not isCurrent() then return end

        -- Recheck the physical assembly after the scripted movement.
        assemblyRoot = root.AssemblyRootPart
        local launchMass = root.AssemblyMass
        if root.Anchored or (assemblyRoot and assemblyRoot.Anchored)
            or launchMass <= 0 or launchMass == math.huge then return end
        spinImpulse = spinImpulse * (launchMass / mass)
        mass = launchMass

        print(string.format("[SelfLaunch] Launch: horizontal %.1f, up %.1f, angle %.1f deg",
            horizontalSpeed, upwardSpeed, math.deg(angle)))
        root:ApplyImpulse((horizontalDirection * horizontalSpeed + Vector3.yAxis * upwardSpeed) * mass)
        root:ApplyAngularImpulse(spinImpulse)

        local started = os.clock()
        local floorArmed = true
        local lastFloorTime, lastWallTime = -math.huge, -math.huge
        local lastFloorY = nil
        local fallingVelocity, fallingAt = nil, -math.huge
        local wallVelocity, wallVelocityAt = nil, -math.huge
        local settledFor = 0
        local nextStatusAt = started + 2

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

        local function varyBounceDirection(targetVelocity, surfaceNormal)
            local horizontal = Vector3.new(targetVelocity.X, 0, targetVelocity.Z)
            if horizontal.Magnitude < 0.5 then return targetVelocity, 0 end
            local yaw = math.rad(randomBetween(-BOUNCE_DIRECTION_SPREAD, BOUNCE_DIRECTION_SPREAD))
            -- Preserve vertical speed and horizontal magnitude. Reduce the angle
            -- near grazing contacts rather than redirecting into the surface.
            for _ = 1, 8 do
                local c, s = math.cos(yaw), math.sin(yaw)
                local turned = Vector3.new(horizontal.X * c - horizontal.Z * s, 0,
                    horizontal.X * s + horizontal.Z * c)
                local candidate = turned + Vector3.yAxis * targetVelocity.Y
                if candidate:Dot(surfaceNormal) > 0.001 and turned:Dot(horizontal) > 0 then
                    return candidate, math.deg(yaw)
                end
                yaw = yaw * 0.5
            end
            return targetVelocity, 0
        end

        local function applyVelocity(targetVelocity, tumbleScale)
            local currentMass = root.AssemblyMass
            assemblyRoot = root.AssemblyRootPart
            if currentMass <= 0 or currentMass == math.huge or root.Anchored
                or (assemblyRoot and assemblyRoot.Anchored) then return false end
            root:ApplyImpulse((targetVelocity - root.AssemblyLinearVelocity) * currentMass)
            local tumble = (right * randomBetween(-0.5, 0.5)
                + forward * randomBetween(-0.5, 0.5)
                + Vector3.yAxis * randomBetween(-0.25, 0.25)
            ) * (currentMass * SPIN_STRENGTH * tumbleScale)
            root:ApplyAngularImpulse(tumble)
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
            local bounced = false

            if not floorArmed and lastFloorY and now - lastFloorTime > 0.05
                and root.Position.Y > lastFloorY + 0.2 and velocity.Y > 0 then
                floorArmed = true
            end

            if nearGround and floorArmed and now - lastFloorTime > 0.18
                and fallingVelocity and now - fallingAt < 0.6 then
                local normal = floorHit.Normal
                local incomingNormal = fallingVelocity:Dot(normal)
                local currentNormal = velocity:Dot(normal)
                local impact = incomingNormal < -MIN_IMPACT_SPEED
                    and currentNormal > incomingNormal * 0.6
                if impact then
                    -- Deliberately replenish energy: do not derive the next height
                    -- from the (possibly already lost) collision speed.
                    local rebound = math.max(MIN_BOUNCE_SPEED,
                        upwardSpeed * BOUNCE_RESTITUTION ^ (floorCount + 1))
                    local tangent = fallingVelocity - normal * incomingNormal
                    local target = tangent * TANGENTIAL_RETENTION + normal * rebound
                    if target.Y < rebound then target = target + Vector3.yAxis * (rebound - target.Y) end
                    local directionChange
                    target, directionChange = varyBounceDirection(target, normal)
                    if not applyVelocity(target, 0.12 * BOUNCE_RESTITUTION ^ floorCount) then
                        finishReason = "invalid-assembly"; break
                    end
                    floorCount = floorCount + 1
                    lastFloorTime, lastFloorY = now, root.Position.Y
                    floorArmed, bounced, settledFor = false, true, 0
                    print(string.format(
                        "[SelfLaunch] Floor %d: incoming %.1f -> target up %.1f, actual up %.1f, yaw %.1f deg",
                        floorCount, -incomingNormal, rebound, root.AssemblyLinearVelocity.Y, directionChange))
                    fallingVelocity, fallingAt = nil, -math.huge
                end
            end

            -- Wall reflection continues until STOP, independently of floor bounces.
            if not bounced and wallVelocity and now - wallVelocityAt < 0.3
                and now - lastWallTime > 0.2 then
                local wallHit = getWall(wallVelocity, dt)
                if wallHit then
                    local flatNormal = Vector3.new(wallHit.Normal.X, 0, wallHit.Normal.Z).Unit
                    local incoming = Vector3.new(wallVelocity.X, 0, wallVelocity.Z)
                    local towardWall = incoming:Dot(flatNormal)
                    local current = Vector3.new(velocity.X, 0, velocity.Z):Dot(flatNormal)
                    if towardWall < -MIN_IMPACT_SPEED and current > towardWall * 0.6 then
                        local reflected = (incoming - flatNormal * (2 * towardWall)) * WALL_RETENTION
                        local target = reflected + Vector3.yAxis * velocity.Y
                        local directionChange
                        target, directionChange = varyBounceDirection(target, flatNormal)
                        if not applyVelocity(target, 0.08) then finishReason = "invalid-assembly"; break end
                        wallCount = wallCount + 1
                        lastWallTime, bounced, settledFor = now, true, 0
                        print(string.format(
                            "[SelfLaunch] Wall %d: incoming %.1f -> reflected %.1f, yaw %.1f deg",
                            wallCount, incoming.Magnitude, reflected.Magnitude, directionChange))
                    end
                end
            end

            velocity = root.AssemblyLinearVelocity
            if not bounced and velocity.Y < -MIN_IMPACT_SPEED then
                fallingVelocity, fallingAt = velocity, now
            end
            if Vector3.new(velocity.X, 0, velocity.Z).Magnitude > MIN_IMPACT_SPEED then
                wallVelocity, wallVelocityAt = velocity, now
            end

            if not bounced then
                if nearGround and math.abs(velocity.Y) < 8 and now - lastFloorTime > 0.25
                    and now - lastWallTime > 0.25 and now - started > 0.35 then
                    settledFor = settledFor + dt
                    if settledFor >= 0.6 then
                        -- If native collision/friction leaves the body resting, restart
                        -- one hop after a delay instead of ending the continuous mode.
                        local rebound = math.max(MIN_BOUNCE_SPEED,
                            upwardSpeed * BOUNCE_RESTITUTION ^ (floorCount + 1))
                        local horizontal = Vector3.new(velocity.X, 0, velocity.Z) * TANGENTIAL_RETENTION
                        local target = horizontal + Vector3.yAxis * rebound
                        target = varyBounceDirection(target, floorHit.Normal)
                        if not applyVelocity(target, 0.06) then finishReason = "invalid-assembly"; break end
                        floorCount = floorCount + 1
                        lastFloorTime, lastFloorY = now, root.Position.Y
                        floorArmed, bounced, settledFor = false, true, 0
                        fallingVelocity, fallingAt = nil, -math.huge
                        print(string.format("[SelfLaunch] Recovery hop %d: target up %.1f",
                            floorCount, rebound))
                    end
                else
                    settledFor = 0
                end
            end
            if now >= nextStatusAt then
                print(string.format("[SelfLaunch] Status: floor=%d wall=%d nearGround=%s armed=%s vertical=%.1f",
                    floorCount, wallCount, tostring(nearGround), tostring(floorArmed), velocity.Y))
                nextStatusAt = now + 2
            end
        end
        if running and not isCurrent() then finishReason = "character-changed-or-dead" end
    end, function(message)
        return tostring(message)
    end)

    running = false
    if not ok then finishReason = "error" end
    cleanup()
    print(string.format("[SelfLaunch] End: %s; floor=%d wall=%d",
        finishReason, floorCount, wallCount))
    if not ok then
        warn("[SelfLaunch] " .. err)
    else
        print("[SelfLaunch] Finished.")
    end
end
