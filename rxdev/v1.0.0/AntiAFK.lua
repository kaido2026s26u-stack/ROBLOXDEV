-- RXDEV AntiAFK. Loading has no side effects; start owns its connections.
local function startAntiAFK(config)
    local LOG_PREFIX = string.format("[RXDEV %s AntiAFK @%.3f] ", config.version, os.clock())
    warn(LOG_PREFIX .. "Loaded; NO USER-ACTIVITY GUARDS")
    local MIN_INTERVAL, MAX_INTERVAL = 30, 60
    local PRESS_SECONDS = 0.08
    local DEBUG = true
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local KEYS = { Enum.KeyCode.F13, Enum.KeyCode.F14, Enum.KeyCode.F15 }
    local running, enabled = true, true
    local connections = {}
    local statusLabel = {Text = "Starting"}
    local nextDue, nextUI = math.huge, 0
    local sendKey, backend = nil, "unavailable"
    local pressedKey, releaseAt
    local receipt
    local attempts, sent, confirmed = 0, 0, 0
    local state = "Starting"
    local nextDiagnostic = 0
    local disabledReason = "none"
    local function debugLog(message)
        if DEBUG then warn(LOG_PREFIX .. message) end
    end
    local function release()
        if not pressedKey then return true end
        local key = pressedKey
        -- Clear first: the backend can synchronously fire InputEnded.
        pressedKey = nil
        local ok, err = pcall(function() sendKey(false, key) end)
        if not ok then pressedKey = key end
        return ok, err
    end
    local function disable(reason)
        enabled = false
        disabledReason = tostring(reason)
        state = "ERROR - see Console"
        warn(LOG_PREFIX .. "Disabled: " .. tostring(reason))
    end
    local function stop(reason)
        if not running then return end
        running = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        local ok, err = release()
        if not ok then warn(LOG_PREFIX .. "Key release failed: " .. tostring(err)) end
        debugLog("Stopped: " .. tostring(reason or "stop-button"))
    end
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end
    local ok, err = xpcall(function()
        -- Use the public test API when available; Delta may instead expose VIM.
        local created, virtual = pcall(function() return UserInputService:CreateVirtualInput() end)
        if created and virtual then
            backend = "VirtualInput"
            sendKey = function(down, key) virtual:SendKey(down, key, false) end
        else
            local found, manager = pcall(function()
                local service = game:GetService("VirtualInputManager")
                assert(type(service.SendKeyEvent) == "function", "SendKeyEvent unavailable")
                return service
            end)
            if found then
                backend = "VirtualInputManager"
                sendKey = function(down, key) manager:SendKeyEvent(down, key, false, game) end
            else
                disable("No keyboard injection API: " .. tostring(manager))
            end
        end
        local function schedule(now)
            local interval = MIN_INTERVAL + (MAX_INTERVAL - MIN_INTERVAL) * math.random()
            nextDue = now + interval
            debugLog(string.format("NEXT in %.2fs; backend=%s", interval, backend))
        end
        local function observe(input, down, processed)
            local now = os.clock()
            if receipt and now <= receipt.checkAt and input.UserInputType == Enum.UserInputType.Keyboard
                and input.KeyCode == receipt.key then
                if down then receipt.down = true else receipt.up = true end
                debugLog(string.format("OBSERVED %s %s #%d processed=%s",
                    down and "DOWN" or "UP", receipt.key.Name, receipt.id, tostring(processed)))
                return
            end
        end
        connect(UserInputService.InputBegan, function(input, processed) observe(input, true, processed) end)
        connect(UserInputService.InputEnded, function(input, processed) observe(input, false, processed) end)
        connect(player.Idled, function(seconds)
            debugLog(string.format("IDLED %.1fs (observation only)", seconds))
        end)
        if enabled then state = "Waiting"; schedule(os.clock()) end
        connect(RunService.Heartbeat, function()
            if not running then return end
            local now = os.clock()
            if pressedKey and now >= releaseAt then
                local released, releaseErr = release()
                if not released then disable("KeyUp failed: " .. tostring(releaseErr))
                else debugLog("RELEASE sent") end
                -- A failed release is retried only by STOP, not every frame.
                releaseAt = math.huge
            end
            if receipt and now >= receipt.checkAt then
                if receipt.down and receipt.up then confirmed += 1 end
                debugLog(string.format("CHECK #%d %s down=%s up=%s; this does NOT verify idle reset",
                    receipt.id, receipt.key.Name, tostring(receipt.down), tostring(receipt.up)))
                if enabled then state = if receipt.down and receipt.up then "Input observed" else "Input NOT observed" end
                receipt = nil
            end
            if enabled and not pressedKey and now >= nextDue then
                local key = KEYS[math.random(1, #KEYS)]
                attempts += 1
                receipt = {id=attempts,key=key,down=false,up=false,checkAt=now+0.6}
                pressedKey, releaseAt = key, now + PRESS_SECONDS
                debugLog(string.format("SEND #%d %s via %s", attempts, key.Name, backend))
                local pressed, pressErr = pcall(function() sendKey(true, key) end)
                if not pressed then
                    local released, releaseErr = release()
                    disable("KeyDown failed: " .. tostring(pressErr) .. (released and "" or "; KeyUp: " .. tostring(releaseErr)))
                else
                    sent += 1
                    state = "Sent " .. key.Name
                    schedule(now)
                end
            end
            if now >= nextDiagnostic then
                nextDiagnostic = now + 10
                debugLog(string.format("STATE enabled=%s pending=%s next=%.1fs state=%s reason=%s",
                    tostring(enabled), pressedKey and pressedKey.Name or "none",
                    enabled and math.max(0, nextDue-now) or 0, state, disabledReason))
            end
            if now >= nextUI then
                nextUI = now + 0.25
                statusLabel.Text = string.format("%s | %s\nSent %d / Observed %d\nNext %.1fs",
                    backend, state, sent, confirmed, enabled and math.max(0, nextDue-now) or 0)
            end
        end)
        debugLog("Ready. Random 30-60s, F13/F14/F15. Success requires a real idle test.")
    end, function(message) return tostring(message) end)
    if not ok then warn(LOG_PREFIX .. err); stop("error") end
    return {stop = stop, status = function() return statusLabel.Text end,
        active = function() return running and enabled end}

end

return {start = startAntiAFK}
