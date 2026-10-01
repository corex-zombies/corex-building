BuildingClient = { records = {}, reservations = {}, objects = {}, entityIds = {}, ready = false, sequence = 0 }
local B,C,D = BuildingClient,BuildingCatalog,BuildingDoors
local resource=GetCurrentResourceName()
local generation=0

function B.InvalidatePlacement()
    B.placementVersion=(B.placementVersion or 0)+1
    B.placementCache=nil; B.spatial=nil; B.renderDirty=true
end

local function despawn(id)
    local entry=B.objects[id]
    if entry then
        entry.cancelled=true; D.Remove(entry)
        if entry.entity then B.entityIds[entry.entity]=nil; DeleteEntity(entry.entity) end
        B.objects[id]=nil
    end
end

function B.Remove(id)
    B.InvalidatePlacement(); despawn(id)
    B.records[id]=nil; B.reservations[id]=nil
end

function B.Upsert(record)
    local def=C.Get(record)
    if not def or not BuildingGeometry.Position(record) then return end
    local previous=B.records[record.id]
    if previous and previous.revision>record.revision then return end
    if previous and previous.revision==record.revision and previous.definition==record.definition then return end
    local entry=B.objects[record.id]
    if entry and previous and previous.definition~=record.definition then B.Remove(record.id); entry=nil end
    B.records[record.id]=record
    B.InvalidatePlacement()
    if entry and entry.entity then D.Update(entry,record,false) end
end

local function spawn(record)
    if B.objects[record.id] then return end
    local entry={generation=generation}; B.objects[record.id]=entry
    CreateThread(function()
        local def=C.Get(record); local hash=GetHashKey(def.model)
        local ok=pcall(lib.requestModel,hash,Config.Streaming.modelTimeout)
        local current=B.records[record.id]
        if not ok or entry.cancelled or entry.generation~=generation or not current or current.definition~=record.definition then
            if B.objects[record.id]==entry then B.objects[record.id]=nil end
            B.renderDirty=true
            SetModelAsNoLongerNeeded(hash)
            return
        end
        local entity=CreateObjectNoOffset(hash,current.x,current.y,current.z,false,false,false)
        if entity==0 then B.objects[record.id]=nil; B.renderDirty=true; SetModelAsNoLongerNeeded(hash); return end
        entry.entity=entity; B.entityIds[entity]=record.id
        SetEntityAsMissionEntity(entity,true,true)
        SetEntityCoordsNoOffset(entity,current.x,current.y,current.z,false,false,false)
        SetEntityHeading(entity,current.yaw+0.0); FreezeEntityPosition(entity,true)
        -- Use the model's exported native collision; no scripted collision shapes.
        SetEntityCollision(entity,true,true)
        SetEntityInvincible(entity,true); SetEntityLodDist(entity,Config.Streaming.unloadDistance)
        SetModelAsNoLongerNeeded(hash)
        if def.moving then D.Bind(entry,current) end
    end)
end

function B.ApplySnapshot(state)
    if not state.ok or (state.epoch==B.epoch and state.sequence<B.sequence) then return false end
    if state.unchanged then B.sequence,B.capacity,B.ready=state.sequence,state.capacity,true; return true end
    local records={}
    for _,record in ipairs(state.records) do records[record.id]=record end
    if state.epoch~=B.epoch or state.bucket~=B.bucket then
        generation=generation+1
        local ids={}; for id in pairs(B.records) do ids[#ids+1]=id end
        for _,id in ipairs(ids) do B.Remove(id) end
        if BuildingPlacement and BuildingPlacement.active then BuildingPlacement.Stop() end
    end
    local removed={}; for id in pairs(B.records) do if not records[id] then removed[#removed+1]=id end end
    for _,id in ipairs(removed) do B.Remove(id) end
    for _,record in pairs(records) do B.Upsert(record) end
    local reservations,changed={},false
    for _,record in ipairs(state.reservations or {}) do
        reservations[record.id]=record
        local old=B.reservations[record.id]
        if not old or old.revision~=record.revision or old.definition~=record.definition
            or old.x~=record.x or old.y~=record.y or old.z~=record.z or old.yaw~=record.yaw then changed=true end
    end
    for id in pairs(B.reservations) do if not reservations[id] then changed=true; break end end
    B.reservations=reservations
    if changed then B.InvalidatePlacement() end
    B.epoch,B.bucket,B.sequence,B.zones,B.capacity,B.ready=state.epoch,state.bucket,state.sequence,state.zones or {},state.capacity,true
    B.cacheTag=state.cacheTag
    return true
end

function B.PlacementRecords(point)
    if not point then
        if not B.placementCache then
            local records={}; for id,r in pairs(B.records) do records[id]=r end
            for id,r in pairs(B.reservations) do records[id]=r end
            B.placementCache=records
        end
        return B.placementCache
    end
    local all=B.PlacementRecords()
    local step=8
    local function cell(x,y,z) return math.floor(x/step)..':'..math.floor(y/step)..':'..math.floor(z/step) end
    if not B.spatial then
        B.spatial={}
        for id,r in pairs(all) do
            local key=cell(r.x,r.y,r.z); local bucket=B.spatial[key]
            if not bucket then bucket={}; B.spatial[key]=bucket end
            bucket[id]=r
        end
    end
    local key=cell(point.x,point.y,point.z)
    if B.nearbyKey==key and B.nearbyVersion==B.placementVersion then return B.nearbyPlacement end
    local records={}; local reach=math.ceil((Config.Placement.distance+7)/step)
    local x,y,z=math.floor(point.x/step),math.floor(point.y/step),math.floor(point.z/step)
    for dx=-reach,reach do for dy=-reach,reach do for dz=-reach,reach do
        local bucket=B.spatial[(x+dx)..':'..(y+dy)..':'..(z+dz)]
        if bucket then for id,r in pairs(bucket) do records[id]=r end end
    end end end
    -- Include support ancestry even when an ancestor is outside the local cells.
    for _,r in pairs(records) do
        local parent,depth=r.parent,0
        while parent and all[parent] and depth<64 do
            depth=depth+1; records[parent]=all[parent]; parent=all[parent].parent
        end
    end
    B.nearbyKey,B.nearbyVersion,B.nearbyPlacement=key,B.placementVersion,records
    return records
end

function B.Sync()
    local state=BuildingFeedback.Call('state',B.cacheTag)
    if type(state)=='table' then
        if state.ok then return B.ApplySnapshot(state) end
        if state.reason=='rate_limited' then return B.ready end
        B.ready=false
    end
    return false
end

RegisterNetEvent('corex-building:client:delta',function(epoch,sequence,record)
    if source~=65535 or epoch~=B.epoch or sequence<=B.sequence then return end
    B.sequence=sequence
    if record.deleted then B.Remove(record.id) else B.Upsert(record) end
end)
CreateThread(function()
    while true do B.Sync(); Wait(Config.Streaming.interval) end
end)
CreateThread(function()
    local lastPoint,lastVersion
    while true do
        local ped=PlayerPedId(); local p=GetEntityCoords(ped)
        local version=B.placementVersion or 0
        if not B.renderDirty and lastVersion==version and lastPoint
            and (p.x-lastPoint.x)^2+(p.y-lastPoint.y)^2+(p.z-lastPoint.z)^2<1 then
            Wait(500)
            goto continueStreaming
        end
        lastPoint={x=p.x,y=p.y,z=p.z}; lastVersion=version; B.renderDirty=false
        local list={}
        for _,r in pairs(B.records) do
            local distance=(p.x-r.x)^2+(p.y-r.y)^2+(p.z-r.z)^2
            if distance<=Config.Streaming.unloadDistance^2 then list[#list+1]={record=r,distance=distance} end
        end
        table.sort(list,function(a,b) return a.distance<b.distance end)
        local wanted={}
        for i=1,math.min(#list,Config.Streaming.objectLimit) do
            local r=list[i].record; wanted[r.id]=true
            if B.objects[r.id] or list[i].distance<=Config.Streaming.distance^2 then spawn(r) end
        end
        local evict={}
        for id in pairs(B.objects) do
            local r=B.records[id]
            if not wanted[id] or not r or BuildingGeometry.Distance(p,r)>Config.Streaming.unloadDistance then evict[#evict+1]=id end
        end
        for _,id in ipairs(evict) do
            despawn(id)
        end
        Wait(500)
        ::continueStreaming::
    end
end)
if Config.Management.enabled then
    RegisterCommand(Config.Management.command,function()
        if BuildingPlacement and BuildingPlacement.active then
            if BuildingPlacement.active.pending then BuildingFeedback.Notify('busy'); return end
            BuildingPlacement.Stop()
        end
        local cam=GetGameplayCamCoord(); local direction=BuildingGeometry.CameraDirection(GetGameplayCamRot(2))
        local length=Config.Doors.distance+5
        local handle=StartShapeTestLosProbe(cam.x,cam.y,cam.z,cam.x+direction.x*length,cam.y+direction.y*length,
            cam.z+direction.z*length,19,PlayerPedId(),7)
        for _=1,20 do
            local status,hit,_,_,entity=GetShapeTestResult(handle)
            if status==2 then
                local id=(hit==true or hit==1) and B.entityIds[entity]
                if id then D.Manage(id) else BuildingFeedback.Notify('aim_structure') end
                return
            elseif status==0 then BuildingFeedback.Notify('aim_structure'); return end
            Wait(0)
        end
        BuildingFeedback.Notify('aim_structure')
    end,false)
    RegisterKeyMapping(Config.Management.command,Config.Text.manage,'keyboard',Config.Management.key)
end
AddEventHandler('onClientResourceStop',function(name)
    if name~=resource then return end
    generation=generation+1
    if BuildingPlacement then BuildingPlacement.Stop() end
    local ids={}; for id in pairs(B.objects) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do B.Remove(id) end
end)
