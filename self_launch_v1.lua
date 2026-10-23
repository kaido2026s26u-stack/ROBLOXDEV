-- Self-launch v1: run once on the local client. No files or shared globals.
-- Wait until this run finishes before executing it again.
do
    print("[SelfLaunch] Loaded revision 8")
    local BACK_SPEED = 70       -- Added backward speed (studs/second)
    local UP_SPEED = 80         -- Added upward speed (studs/second)
    local SPEED_VARIATION = 0.10 -- +/-10% for horizontal and upward speeds
    local DIRECTION_SPREAD = 20 -- Horizontal angle spread in degrees
    local SPIN_STRENGTH = 6     -- Angular impulse per unit mass; tune gently
    local MAX_SECONDS = 30      -- Maximum physical flight / bounce phase
    local MAX_BOUNCES = 10
    local BOUNCE_RESTITUTION = 0.97
    local TANGENTIAL_RETENTION = 0.95
    local MAX_WALL_BOUNCES = 12
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
        local floorCount, wallCount = 0, 0
        local floorArmed = true
        local lastFloorTime, lastWallTime = -math.huge, -math.huge
        local lastFloorY = nil
        local fallingVelocity, fallingAt = nil, -math.huge
        local wallVelocity, wallVelocityAt = nil, -math.huge
        local settledFor = 0
        local nextStatusAt = started + 2
        local finishReason = "time-limit"

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

        while isCurrent() and os.clock() - started < MAX_SECONDS do
            local dt = RunService.Heartbeat:Wait()
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
                if impact and floorCount < MAX_BOUNCES then
                    -- Deliberately replenish energy: do not derive the next height
                    -- from the (possibly already lost) collision speed.
                    local rebound = math.max(MIN_BOUNCE_SPEED,
                        upwardSpeed * BOUNCE_RESTITUTION ^ (floorCount + 1))
                    local tangent = fallingVelocity - normal * incomingNormal
                    local target = tangent * TANGENTIAL_RETENTION + normal * rebound
                    if target.Y < rebound then target = target + Vector3.yAxis * (rebound - target.Y) end
                    if not applyVelocity(target, 0.12 * BOUNCE_RESTITUTION ^ floorCount) then
                        finishReason = "invalid-assembly"; break
                    end
                    floorCount = floorCount + 1
                    lastFloorTime, lastFloorY = now, root.Position.Y
                    floorArmed, bounced, settledFor = false, true, 0
                    print(string.format(
                        "[SelfLaunch] Floor %d/%d: incoming %.1f -> target up %.1f, actual up %.1f",
                        floorCount, MAX_BOUNCES, -incomingNormal, rebound, root.AssemblyLinearVelocity.Y))
                    fallingVelocity, fallingAt = nil, -math.huge
                end
            end

            -- Wall reflection is separate from the ten floor bounces.
            if not bounced and wallVelocity and now - wallVelocityAt < 0.3
                and now - lastWallTime > 0.2 and wallCount < MAX_WALL_BOUNCES then
                local wallHit = getWall(wallVelocity, dt)
                if wallHit then
                    local flatNormal = Vector3.new(wallHit.Normal.X, 0, wallHit.Normal.Z).Unit
                    local incoming = Vector3.new(wallVelocity.X, 0, wallVelocity.Z)
                    local towardWall = incoming:Dot(flatNormal)
                    local current = Vector3.new(velocity.X, 0, velocity.Z):Dot(flatNormal)
                    if towardWall < -MIN_IMPACT_SPEED and current > towardWall * 0.6 then
                        local reflected = (incoming - flatNormal * (2 * towardWall)) * WALL_RETENTION
                        local target = reflected + Vector3.yAxis * velocity.Y
                        if not applyVelocity(target, 0.08) then finishReason = "invalid-assembly"; break end
                        wallCount = wallCount + 1
                        lastWallTime, bounced, settledFor = now, true, 0
                        print(string.format(
                            "[SelfLaunch] Wall %d/%d: incoming %.1f -> reflected %.1f",
                            wallCount, MAX_WALL_BOUNCES, incoming.Magnitude, reflected.Magnitude))
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
                    if settledFor >= 0.3 then
                        finishReason = if floorCount >= MAX_BOUNCES then "floor-limit-complete" else "settled-before-limit"
                        break
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
        if not isCurrent() then finishReason = "character-changed-or-dead" end
        print(string.format("[SelfLaunch] End: %s; floor=%d/%d wall=%d",
            finishReason, floorCount, MAX_BOUNCES, wallCount))
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
