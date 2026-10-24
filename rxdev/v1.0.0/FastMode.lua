-- Reversible aggressive visual reduction. Loading this module changes nothing.
local Lighting = game:GetService('Lighting')
local RunService = game:GetService('RunService')
local active = false
local advanced = false
local superMode = false
local ultraMode = false
local ULTRA_GUI_DISTANCE = 60
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
    if not ok then failures += 1;warn('[RXDEV FastMode] Cannot apply '..property..': '..tostring(err)) end
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
    elseif object:IsA('Light') then
        apply(object,'Shadows',false)
        if superMode then apply(object,'Enabled',false) end
    elseif object:IsA('Clouds') then
        if ultraMode then apply(object,'Enabled',false) end
    elseif object:IsA('FileMesh') then
        if ultraMode then apply(object,'TextureId','') end
    elseif object:IsA('BillboardGui') or object:IsA('SurfaceGui') then
        if ultraMode then
            local distance = object.MaxDistance
            if distance <= 0 or distance > ULTRA_GUI_DISTANCE then
                apply(object,'MaxDistance',ULTRA_GUI_DISTANCE)
            end
        end
    elseif object:IsA('Highlight') then
        if superMode then apply(object,'Enabled',false) end
    elseif object:IsA('BasePart') then
        apply(object,'CastShadow',false)
        apply(object,'Reflectance',0)
        if advanced and object:IsA('MeshPart') then
            apply(object,'RenderFidelity',Enum.RenderFidelity.Performance)
            apply(object,'TextureID','')
            if ultraMode then apply(object,'DoubleSided',false) end
        end
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
            if not ok then failures+=1;warn('[RXDEV FastMode] Visit failed: '..tostring(err)) end
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
    active = false;advanced = false;superMode = false;ultraMode = false
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
            if not ok then failed+=1;warn('[RXDEV FastMode] Restore failed: '..tostring(err)) end
        end
    end
    table.clear(records);table.clear(seen)
    warn(string.format('[RXDEV FastMode] OFF restored=%d preserved=%d failed=%d; all work cleared',restored,preserved,failed))
end
function module.start()
    if active then return end
    active=true;advanced=false;superMode=false;ultraMode=false;changed,failures,visited=0,0,0
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
    warn('[RXDEV FastMode] ON: shadows, particles/trails/beams, post-effects, decals/textures, reflections and terrain visuals')
end
function module.advance()
    assert(active, 'Enable FASTMODE before AdvancedFastMode')
    if advanced then return end
    advanced=true
    -- Restart bounded discovery, including any work still pending from normal mode.
    -- Existing property snapshots are retained, so one OFF restores both levels.
    finishWorker()
    seen=setmetatable({}, {__mode='k'})
    enqueue(Lighting);enqueue(workspace)
    if workspace.CurrentCamera then enqueue(workspace.CurrentCamera) end
    warn('[RXDEV FastMode] ADVANCED ON: mesh detail Performance + mesh textures off')
end
function module.super()
    assert(active and advanced, 'Enable AdvancedFastMode before SuperFastMode')
    if superMode then return end
    superMode=true
    finishWorker()
    seen=setmetatable({}, {__mode='k'})
    enqueue(Lighting);enqueue(workspace)
    if workspace.CurrentCamera then enqueue(workspace.CurrentCamera) end
    warn('[RXDEV FastMode] SUPER ON: local lights and Highlight disabled')
end
function module.ultra()
    assert(active and superMode, 'Enable SuperFastMode before UltraFastMode')
    if ultraMode then return end
    ultraMode=true
    finishWorker()
    seen=setmetatable({}, {__mode='k'})
    enqueue(Lighting);enqueue(workspace)
    if workspace.CurrentCamera then enqueue(workspace.CurrentCamera) end
    -- World-space UI can also live in PlayerGui via Adornee. ScreenGui itself is untouched.
    local player = game:GetService('Players').LocalPlayer
    local gui = player and player:FindFirstChildOfClass('PlayerGui')
    if gui then watch(gui,connections) end
    warn('[RXDEV FastMode] ULTRA ON: clouds OFF, one-sided meshes, FileMesh textures OFF, 3D UI capped at 60 studs')
end
function module.level() return active and (ultraMode and 4 or superMode and 3 or advanced and 2 or 1) or 0 end
function module.active() return active end
function module.busy() return worker ~= nil end
function module.status()
    return string.format('%s | changed %d / errors %d / pending %d',active and (ultraMode and 'ULTRA ON' or superMode and 'SUPER ON' or advanced and 'ADVANCED ON' or 'FAST ON') or 'FAST OFF',changed,failures,math.max(0,tail-head+1))
end
return module
