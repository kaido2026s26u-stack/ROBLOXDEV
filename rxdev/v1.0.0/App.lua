-- RXDEV app scope: compose modules, own connections, replace previous panels, clean up.
local module = {}
function module.start(get, config)
    local UI, AntiAFK = get("UI"), get("AntiAFK")
    local Graphics, Meter = get("Graphics"), get("PerformanceMeter")
    local Players = game:GetService("Players")
    local StarterGui = game:GetService("StarterGui")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    -- Load all required boot modules before replacing a working panel.
    for _, name in ipairs(config.legacyGuiNames) do
        local old = playerGui:FindFirstChild(name)
        if old then old:Destroy() end
    end
    local old = playerGui:FindFirstChild(config.guiName)
    if old then old:Destroy() end
    local alive, connections = true, {}
    local anti, graphics, ui
    local initialConsole, consoleOpen = false, false
    pcall(function() initialConsole = StarterGui:GetCore("DevConsoleVisible") == true end)
    consoleOpen = initialConsole
    local function connect(signal, fn)
        local connection = signal:Connect(fn)
        table.insert(connections, connection)
        return connection
    end
    local function refresh()
        if not alive or not ui or not graphics then return end
        ui.antiButton.Text = "AntiAFK: " .. (anti and (anti.active() and "ON" or "ERROR") or "OFF")
        local fastText, extremeText, status = graphics.describe()
        if ui.fastButton.Text ~= fastText then ui.fastButton.Text = fastText end
        if ui.extremeButton.Text ~= extremeText then ui.extremeButton.Text = extremeText end
        status = (anti and anti.status() or "AntiAFK stopped") .. "\n" .. status
        if ui.status.Text ~= status then ui.status.Text = status end
    end
    local function cleanup()
        if not alive then return end
        alive = false
        if graphics then graphics.close() end
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        if anti then anti.stop("RXDEV-close");anti=nil end
        if consoleOpen ~= initialConsole then
            pcall(function() StarterGui:SetCore("DevConsoleVisible", initialConsole) end)
        end
        warn("[RXDEV v" .. config.version .. "] Stopped; connections cleared and key released.")
    end
    local ok, why = pcall(function()
        ui = UI.create(connect, config)
        connect(ui.gui.Destroying, cleanup)
        graphics = Graphics.new(get, refresh)
        connect(ui.antiButton.Activated, function()
            if anti then anti.stop("RXDEV-toggle");anti=nil else anti=AntiAFK.start(config) end
            refresh()
        end)
        connect(ui.consoleButton.Activated, function()
            local opened, err = pcall(function() StarterGui:SetCore("DevConsoleVisible", true) end)
            if opened then consoleOpen=true else warn("[RXDEV Console] " .. tostring(err)) end
        end)
        connect(ui.fastButton.Activated, graphics.next)
        connect(ui.extremeButton.Activated, graphics.toggleExtreme)
        connect(ui.allButton.Activated, function() ui.gui:Destroy() end)
        Meter.start(ui, graphics, connect)
        local nextRefresh = 0
        connect(RunService.Heartbeat, function()
            if os.clock() >= nextRefresh then nextRefresh=os.clock()+0.25;refresh() end
        end)
        ui.gui.Parent = playerGui
        anti = AntiAFK.start(config)
        refresh()
    end)
    if not ok then
        cleanup()
        if ui then ui.gui:Destroy() end
        error("RXDEV startup: " .. tostring(why), 0)
    end
    warn("[RXDEV v" .. config.version .. "] Ready.")
    return {stop=function() ui.gui:Destroy() end, version=config.version}
end
return module
