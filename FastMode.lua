-- Side-effect-free module load. Call start()/stop(); no shared globals.
local Lighting = game:GetService('Lighting')
local RunService = game:GetService('RunService')
local active = false
local records, connections, cameraConnections = {}, {}, {}
local queue, queued = {}, {}
local head = 1
local worker
local changed, failures = 0, 0
local module = {}
local function disconnect(items)
    for _, c in ipairs(items) do c:Disconnect() end
    table.clear(items)
end
local function apply(object, property)
    if records[object] then return end
    local ok, err = pcall(function()
        if not object.Parent then return end
        local original = object[property]
        -- Save only actual changes; do not later restore an already-disabled effect.
        if original == false then return end
        local record = {property=property,original=original}
        records[object] = record
        object[property] = false
        changed += 1
        record.destroying = object.Destroying:Connect(function() records[object] = nil end)
    end)
    if not ok then failures += 1;warn('[FastMode r1] Cannot apply: '..tostring(err)) end
end
local function finishWorker()
    if worker then worker:Disconnect();worker = nil end
    table.clear(queue);table.clear(queued);head = 1
end
local function enqueue(object)
    if not active or queued[object] or records[object] or not object:IsA('PostEffect') then return end
    queued[object] = true
    queue[#queue+1] = object
    if worker then return end
    worker = RunService.Heartbeat:Connect(function()
        if not active then finishWorker();return end
        local began, count = os.clock(), 0
        while head <= #queue and count < 24 do
            local item = queue[head]
            -- Retain array slots until completion so length stays well-defined.
            queue[head] = false;head += 1;count += 1
            queued[item] = nil
            apply(item, 'Enabled')
            if os.clock()-began >= 0.002 then break end
        end
        if head > #queue then finishWorker() end
    end)
end
local function watch(root, items)
    if not root then return end
    table.insert(items, root.DescendantAdded:Connect(enqueue))
    for _, object in ipairs(root:GetDescendants()) do enqueue(object) end
end
function module.stop()
    active = false
    disconnect(connections);disconnect(cameraConnections);finishWorker()
    local restored, preserved = 0, 0
    for object, record in pairs(records) do
        if record.destroying then record.destroying:Disconnect() end
        pcall(function()
            if not object.Parent then return end
            -- Preserve a differing value written by another script during FASTMODE.
            if object[record.property] == false then
                object[record.property] = record.original;restored += 1
            else preserved += 1 end
        end)
    end
    table.clear(records)
    warn(string.format('[FastMode r1] OFF restored=%d preserved=%d; queue and watchers cleared',restored,preserved))
end
function module.start()
    if active then return end
    active = true;changed, failures = 0, 0
    local ok, err = pcall(function()
        apply(Lighting,'GlobalShadows')
        watch(Lighting,connections)
        local function cameraChanged()
            disconnect(cameraConnections)
            watch(workspace.CurrentCamera,cameraConnections)
        end
        table.insert(connections,workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(cameraChanged))
        cameraChanged()
    end)
    if not ok then module.stop();error(err) end
    warn('[FastMode r1] ON shadows/post-effects only; no Workspace scan or steady frame polling')
end
function module.active() return active end
function module.status()
    return string.format('FAST %s | changed %d / errors %d / pending %d',active and 'ON' or 'OFF',changed,failures,math.max(0,#queue-head+1))
end
return module
