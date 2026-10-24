-- Reversible aggressive visual reduction. Loading this module changes nothing.
local Lighting = game:GetService('Lighting')
local RunService = game:GetService('RunService')
local active = false
local records, connections, cameraConnections = {}, {}, {}
local queue, seen, head, tail = {}, {}, 1, 0
local worker
local changed, failures, visited = 0, 0, 0
local module = {}
local function disconnect(items)
    for _, c in ipairs(items) do c:Disconnect() end
    table.clear(items)
end
local function apply(object, property, target)
    local record = records[object]
    if record and record.values[property] then return end
    local ok, err = pcall(function()
        if not object.Parent then return end
        local original = object[property]
        if original == target then return end
        if not record then
            record = {values={}}
            records[object] = record
            record.destroying = object.Destroying:Connect(function() records[object] = nil end)
        end
        local value = {original=original,target=target}
        record.values[property] = value
        object[property] = target
        changed += 1
    end)
    if not ok then failures += 1;warn('[FastMode r2] Cannot apply '..property..': '..tostring(err)) end
end
local function reduce(object)
    if object:IsA('Lighting') then apply(object,'GlobalShadows',false)
    elseif object:IsA('Terrain') then
        apply(object,'WaterWaveSize',0)
        apply(object,'WaterWaveSpeed',0)
        apply(object,'WaterReflectance',0)
        -- Decoration can be permission-restricted; a failure is reported, not bypassed.
        apply(object,'Decoration',false)
    elseif object:IsA('PostEffect') or object:IsA('ParticleEmitter') or object:IsA('Trail')
        or object:IsA('Beam') or object:IsA('Smoke') or object:IsA('Fire') or object:IsA('Sparkles') then
        apply(object,'Enabled',false)
    elseif object:IsA('Decal') or object:IsA('Texture') then
        apply(object,'Transparency',1)
    elseif object:IsA('Light') then apply(object,'Shadows',false)
    elseif object:IsA('BasePart') then
        apply(object,'CastShadow',false)
        apply(object,'Reflectance',0)
    end
end
local function finishWorker()
    if worker then worker:Disconnect();worker = nil end
    table.clear(queue);head,tail=1,0
end
local enqueue
local function ensureWorker()
    if worker then return end
    worker = RunService.Heartbeat:Connect(function()
        if not active then finishWorker();return end
        local began, count = os.clock(), 0
        while head <= tail and count < 64 do
            local object = queue[head];queue[head]=nil;head+=1;count+=1;visited+=1
            local ok, err = pcall(function()
                if not object.Parent then return end
                reduce(object)
                -- Incremental discovery: no GetDescendants of the entire map.
                for _, child in ipairs(object:GetChildren()) do enqueue(child) end
            end)
            if not ok then failures+=1;warn('[FastMode r2] Visit failed: '..tostring(err)) end
            if os.clock()-began >= 0.002 then break end
        end
        if head > tail then finishWorker() end
    end)
end
enqueue = function(object)
    if not active or seen[object] then return end
    seen[object] = true;tail+=1;queue[tail]=object
    ensureWorker()
end
local function watch(root, items)
    if not root then return end
    table.insert(items,root.DescendantAdded:Connect(enqueue))
    enqueue(root)
end
function module.stop()
    active = false
    disconnect(connections);disconnect(cameraConnections);finishWorker()
    local restored,preserved,failed = 0,0,0
    for object,record in pairs(records) do
        if record.destroying then record.destroying:Disconnect() end
        for property,value in pairs(record.values) do
            local ok, err = pcall(function()
                if not object.Parent then return end
                if object[property] == value.target then
                    object[property]=value.original;restored+=1
                else preserved+=1 end
            end)
            if not ok then failed+=1;warn('[FastMode r2] Restore failed: '..tostring(err)) end
        end
    end
    table.clear(records);table.clear(seen)
    warn(string.format('[FastMode r2] OFF restored=%d preserved=%d failed=%d; all work cleared',restored,preserved,failed))
end
function module.start()
    if active then return end
    active=true;changed,failures,visited=0,0,0
    seen=setmetatable({}, {__mode='k'})
    local ok,err=pcall(function()
        apply(Lighting,'GlobalShadows',false)
        watch(Lighting,connections)
        watch(workspace,connections)
        local function cameraChanged()
            disconnect(cameraConnections)
            watch(workspace.CurrentCamera,cameraConnections)
        end
        table.insert(connections,workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(cameraChanged))
        cameraChanged()
    end)
    if not ok then module.stop();error(err) end
    warn('[FastMode r2] ON: shadows, particles/trails/beams, post-effects, decals/textures, reflections and terrain visuals')
end
function module.active() return active end
function module.status()
    return string.format('FAST %s | changed %d / errors %d / pending %d',active and 'ON' or 'OFF',changed,failures,math.max(0,tail-head+1))
end
return module
