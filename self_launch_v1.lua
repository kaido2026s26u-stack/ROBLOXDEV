-- Self-launch v1: run once on the local client. No files or shared globals.
-- Wait until this run finishes before executing it again.
do
    print("[SelfLaunch] Loaded revision 4")
    local BACK_SPEED = 70       -- Added backward speed (studs/second)
    local UP_SPEED = 80         -- Added upward speed (studs/second)
    local SPEED_VARIATION = 0.10 -- +/-10% for horizontal and upward speeds
    local DIRECTION_SPREAD = 20 -- Horizontal angle spread in degrees
    local SPIN_STRENGTH = 6     -- Angular impulse per unit mass; tune gently
    local MAX_SECONDS = 4
    local LAUNCH_DELAY = 3      -- Wait before changing character control

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
        print("[SelfLaunch] Launching in 3 seconds.")
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
        RunService.Heartbeat:Wait()
        if not isCurrent() then return end

        print(string.format("[SelfLaunch] Launch: horizontal %.1f, up %.1f, angle %.1f deg",
            horizontalSpeed, upwardSpeed, math.deg(angle)))
        root:ApplyImpulse((horizontalDirection * horizontalSpeed + Vector3.yAxis * upwardSpeed) * mass)
        root:ApplyAngularImpulse(spinImpulse)

        local started = os.clock()
        local settledFor = 0
        while isCurrent() and os.clock() - started < MAX_SECONDS do
            local dt = RunService.Heartbeat:Wait()
            if not isCurrent() then break end
            local elapsed = os.clock() - started
            local reach = math.max(3.5, humanoid.HipHeight + root.Size.Y / 2 + 0.75)
            local hit = workspace:Raycast(root.Position, -Vector3.yAxis * reach, rayParams)
            local nearGround = hit and hit.Normal.Y > 0.4
            local slowVertical = math.abs(root.AssemblyLinearVelocity.Y) < 8
            if elapsed > 0.35 and nearGround and slowVertical then
                settledFor = settledFor + dt
                if settledFor >= 0.15 then break end
            else
                settledFor = 0
            end
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
