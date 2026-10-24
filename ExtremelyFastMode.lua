-- Independent reversible culling experiment. No shared FASTMODE properties.
local RunService=game:GetService('RunService')
local active=false
local records,connections,candidates={}, {}, {}
local queue,seen,head,tail={}, {},1,0
local candidateIndex,candidateConnections={},{}
local worker
local changed,failures=0,0
local scanIndex,scanLimit=0,0
local lastCameraPosition
local passPosition
local nextCheck=0
local module={}
local HIDE_DISTANCE,SHOW_DISTANCE=180,150
local function apply(object,property,target)
    local record=records[object]
    if not record then
        record={values={}}
        records[object]=record
        record.destroying=object.Destroying:Connect(function() records[object]=nil end)
    end
    local value=record.values[property]
    if not value then
        value={original=object[property],target=target}
        record.values[property]=value
    end
    if object[property]~=target then object[property]=target;changed+=1 end
end
local function decoration(part)
    if not part:IsA('BasePart') or part:IsA('Terrain') or not part.Anchored or part.CanCollide or part.CanTouch then return false end
    local node=part
    while node and node~=workspace do
        if node:IsA('Tool') or node:IsA('Accessory') then return false end
        if node:IsA('Model') and node:FindFirstChildOfClass('Humanoid') then return false end
        if node:FindFirstChildOfClass('ProximityPrompt') or node:FindFirstChildOfClass('ClickDetector') then return false end
        node=node.Parent
    end
    return part:IsDescendantOf(workspace)
end
local function updateCandidate(part,position)
    if not part.Parent then return end
    local record=records[part]
    local value=record and record.values.LocalTransparencyModifier
    -- A different value written by another script takes precedence.
    if value and value.hidden and part.LocalTransparencyModifier~=1 then value.external=true end
    if value and value.external then return end
    local distance=(part.Position-position).Magnitude-part.Size.Magnitude/2
    if decoration(part) and distance>HIDE_DISTANCE then
        apply(part,'LocalTransparencyModifier',1)
        records[part].values.LocalTransparencyModifier.hidden=true
    elseif value and value.hidden and (distance<SHOW_DISTANCE or not decoration(part)) then
        if part.LocalTransparencyModifier==1 then part.LocalTransparencyModifier=value.original end
        value.hidden=false
    end
end
local function enqueue(object)
    if not active or seen[object] then return end
    seen[object]=true;tail+=1;queue[tail]=object
end
local function visit(object)
    if not object.Parent then return end
    if object:IsA('BillboardGui') or object:IsA('SurfaceGui') then
        apply(object,'Enabled',false)
    elseif object:IsA('ViewportFrame') then
        apply(object,'Visible',false)
    elseif decoration(object) then
        candidates[#candidates+1]=object
        candidateIndex[object]=#candidates
        candidateConnections[object]=object.Destroying:Connect(function()
            local index=candidateIndex[object]
            if index then
                local last=candidates[#candidates]
                candidates[index]=last;candidates[#candidates]=nil
                if last~=object then candidateIndex[last]=index end
                candidateIndex[object]=nil
                scanLimit=math.min(scanLimit,#candidates)
            end
            candidateConnections[object]=nil
        end)
        local camera=workspace.CurrentCamera
        if camera then updateCandidate(object,camera.CFrame.Position) end
    end
    for _, child in ipairs(object:GetChildren()) do enqueue(child) end
end
function module.stop()
    active=false
    if worker then worker:Disconnect();worker=nil end
    for _, c in ipairs(connections) do c:Disconnect() end
    for _, c in pairs(candidateConnections) do c:Disconnect() end
    table.clear(candidateConnections);table.clear(candidateIndex)
    for object,record in pairs(records) do
        if record.destroying then record.destroying:Disconnect() end
        for property,value in pairs(record.values) do
            local ok,err=pcall(function()
                if object.Parent and not value.external and object[property]==value.target then object[property]=value.original end
            end)
            if not ok then warn('[Extreme r1] Restore failed: '..tostring(err)) end
        end
    end
    table.clear(records);table.clear(connections);table.clear(candidates)
    table.clear(queue);table.clear(seen)
    head,tail,scanIndex,scanLimit=1,0,0,0
    lastCameraPosition=nil
    warn('[Extreme r1] OFF; settings restored and all work disconnected')
end
function module.start()
    if active then return end
    active=true;changed,failures=0,0;nextCheck=0
    seen=setmetatable({}, {__mode='k'})
    local ok,err=pcall(function()
        local function watch(root)
            if not root then return end
            table.insert(connections,root.DescendantAdded:Connect(enqueue));enqueue(root)
        end
        watch(workspace)
        local p=game:GetService('Players').LocalPlayer
        watch(p and p:FindFirstChildOfClass('PlayerGui'))
        worker=RunService.Heartbeat:Connect(function()
            if not active then return end
            local began,count=os.clock(),0
            while head<=tail and count<64 do
                local object=queue[head];queue[head]=nil;head+=1;count+=1
                local worked,why=pcall(function() visit(object) end)
                if not worked then failures+=1;warn('[Extreme r1] Visit failed: '..tostring(why)) end
                if os.clock()-began>=0.002 then break end
            end
            if head>tail then table.clear(queue);head,tail=1,0 end
            local camera=workspace.CurrentCamera
            if camera and scanIndex==0 and os.clock()>=nextCheck then
                nextCheck=os.clock()+0.2
                local position=camera.CFrame.Position
                if not lastCameraPosition or (position-lastCameraPosition).Magnitude>=8 then
                    lastCameraPosition=position;passPosition=position
                    scanIndex,scanLimit=1,#candidates
                end
            end
            local checked=0
            while scanIndex>0 and scanIndex<=scanLimit and checked<32 do
                local part=candidates[scanIndex];scanIndex+=1;checked+=1
                pcall(function() updateCandidate(part,passPosition) end)
                if os.clock()-began>=0.003 then break end
            end
            if scanIndex>scanLimit then scanIndex=0 end
        end)
    end)
    if not ok then module.stop();error(err) end
    warn('[Extreme r1] ON: 3D UI and ViewportFrame hidden; distant anchored, non-colliding, non-touching decoration candidates culled at 180 studs, restored within 150')
end
function module.active() return active end
function module.busy() return head<=tail end
function module.status() return string.format('EXTREME %s | edits %d / errors %d / pending %d',active and 'ON' or 'OFF',changed,failures,math.max(0,tail-head+1)) end
return module
