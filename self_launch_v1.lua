-- Self-launch v1: run once on the local client. No files or shared globals.
-- Wait until this run finishes before executing it again.
do
    print("[SelfLaunch] Loaded revision 6")
    local BACK_SPEED = 70       -- Added backward speed (studs/second)
    local UP_SPEED = 80         -- Added upward speed (studs/second)
    local SPEED_VARIATION = 0.10 -- +/-10% for horizontal and upward speeds
    local DIRECTION_SPREAD = 20 -- Horizontal angle spread in degrees
    local SPIN_STRENGTH = 6     -- Angular impulse per unit mass; tune gently
    local MAX_SECONDS = 12      -- Maximum physical flight / bounce phase
    local MAX_BOUNCES = 4
    local BOUNCE_RESTITUTION = 0.75
    local TANGENTIAL_RETENTION = 0.85
    local MIN_BOUNCE_SPEED = 12
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

    local oldAutoRotate = humanoid.AutoRotate
    local changed = false
    local function isCurrent()
        return player.Character == character
            and character.Parent ~= nil
            and humanoid.Parent ~= nil
            and root:IsDescendantOf(character)
            and humanoid.Health > 0
    end

    local ok, err = xpcall(function()
        print("[SelfLaunch] Starting approach in 3 seconds.")
        task.wait(LAUNCH_DELAY)
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
                if not isCurrent() or root.Anchored or humanoid.Sit or humanoid.PlatformStand then
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
        if not isCurrent() then return end

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
        local previousVelocity = root.AssemblyLinearVelocity
        local bounceCount = 0
        local previousRebound = upwardSpeed
        local armed = true
        local lastBounceTime = -math.huge
        local lastBounceY = nil
        local settledFor = 0

        while isCurrent() and os.clock() - started < MAX_SECONDS do
            local dt = RunService.Heartbeat:Wait()
            if not isCurrent() then break end
            if root.Anchored or humanoid.Sit or humanoid.PlatformStand then break end
            local now = os.clock()
            local velocity = root.AssemblyLinearVelocity
            local supportHeight = humanoid.HipHeight + root.Size.Y / 2
            local reach = math.max(4, supportHeight + 2)
            local hit = workspace:Raycast(root.Position, -Vector3.yAxis * reach, rayParams)
            local nearGround = hit and hit.Normal.Y > 0.6

            -- Require an actual upward departure before another impact can bounce.
            -- A short ray can still see the ground during the smaller bounces.
            if not armed and lastBounceY and now - lastBounceTime > 0.05
                and root.Position.Y > lastBounceY + 0.2 and velocity.Y > 0 then
                armed = true
            end

            local bounced = false
            if nearGround and armed and now - lastBounceTime > 0.12 then
                local normal = hit.Normal
                local incomingNormal = previousVelocity:Dot(normal)
                local currentNormal = velocity:Dot(normal)
                -- A nearby floor alone is not an impact: look for the collision
                -- interrupting downward motion (including a native upward rebound).
                local impact = incomingNormal < -MIN_IMPACT_SPEED
                    and currentNormal > incomingNormal * 0.55
                if impact and bounceCount < MAX_BOUNCES then
                    local rebound = math.min(
                        -incomingNormal * BOUNCE_RESTITUTION,
                        previousRebound * BOUNCE_RESTITUTION
                    )
                    if rebound >= MIN_BOUNCE_SPEED then
                        local tangent = previousVelocity - normal * incomingNormal
                        local targetVelocity = tangent * TANGENTIAL_RETENTION + normal * rebound
                        local bounceMass = root.AssemblyMass
                        assemblyRoot = root.AssemblyRootPart
                        if bounceMass <= 0 or bounceMass == math.huge
                            or (assemblyRoot and assemblyRoot.Anchored) then break end
                        root:ApplyImpulse((targetVelocity - velocity) * bounceMass)
                        bounceCount = bounceCount + 1
                        previousRebound = rebound
                        lastBounceTime = now
                        lastBounceY = root.Position.Y
                        armed = false
                        settledFor = 0
                        bounced = true

                        local tumble = (
                            right * randomBetween(-0.5, 0.5)
                            + forward * randomBetween(-0.5, 0.5)
                            + Vector3.yAxis * randomBetween(-0.25, 0.25)
                        ) * (bounceMass * SPIN_STRENGTH * 0.25 * BOUNCE_RESTITUTION ^ bounceCount)
                        root:ApplyAngularImpulse(tumble)
                        print(string.format("[SelfLaunch] Bounce %d/%d: rebound %.1f",
                            bounceCount, MAX_BOUNCES, rebound))
                    end
                end
            end

            if not bounced then
                if nearGround and math.abs(velocity.Y) < 8 and now - lastBounceTime > 0.15
                    and now - started > 0.35 then
                    settledFor = settledFor + dt
                    if settledFor >= 0.2 then break end
                else
                    settledFor = 0
                end
            end
            previousVelocity = root.AssemblyLinearVelocity
        end
    end, function(message)
        return tostring(message)
    end)

    -- Restore the original object only, even after an error or a respawn.
    if changed then
        local restored, restoreErr = pcall(function()
            if humanoid.Parent then
                humanoid.AutoRotate = oldAutoRotate
            end
        end)
        if not restored then warn("[SelfLaunch] Restore failed: " .. tostring(restoreErr)) end
        local recovered, recoveryErr = pcall(function()
            if isCurrent() then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
        if not recovered then warn("[SelfLaunch] Recovery failed: " .. tostring(recoveryErr)) end
    end
    if not ok then
        warn("[SelfLaunch] " .. err)
    else
        print("[SelfLaunch] Finished.")
    end
end
