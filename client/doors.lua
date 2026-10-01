BuildingDoors = { entries = {} }
local D,G,C,F = BuildingDoors,BuildingGeometry,BuildingCatalog,BuildingFeedback
local interacting = false
local lastInteraction=-1000

function D.HidePrompt()
    if not D.prompt then return end
    local open,text=lib.isTextUIOpen()
    if open and text==D.prompt then lib.hideTextUI() end
    D.prompt=nil
end

function D.Nearest()
    if not next(D.entries) then return end
    local ped=PlayerPedId()
    if IsEntityDead(ped) or IsPedInAnyVehicle(ped,false) then return end
    local p=GetEntityCoords(ped); local best,distance
    for id,entry in pairs(D.entries) do
        local record=BuildingClient and BuildingClient.records[id]
        if record and not entry.cancelled and entry.entity and DoesEntityExist(entry.entity) then
            local current=G.Distance(p,G.Handle(record))
            if current<=Config.Doors.distance and (not distance or current<distance) then best,distance=id,current end
        end
    end
    return best,distance
end

function D.ShowPrompt(id)
    local record=BuildingClient.records[id]; local entry=D.entries[id]
    if not record or not entry or entry.animating or interacting or (BuildingPlacement and BuildingPlacement.active)
        or (IsNuiFocused and IsNuiFocused()) then D.HidePrompt(); return end
    local action=record.open and Config.Text.close or Config.Text.open
    local text=('['..Config.Doors.interactionKey..'] '..action..' '..C.Get(record).label)
    if D.prompt==text then return end
    D.prompt=text
    lib.showTextUI(text,{position='right-center',icon=record.locked and 'key' or (record.open and 'door-open' or 'door-closed')})
end

local function password(optional)
    local input=lib.inputDialog(Config.Text.password,{{type='input',label=Config.Text.password,
        description=optional and Config.Text.passwordHint or nil,password=true,required=not optional,
        min=Config.Doors.minLength,max=Config.Doors.maxLength}})
    return input and input[1] or nil
end
D.Password=password

local function request(name,...)
    return F.Call(name,...)
end

function D.Interact(id)
    if interacting or GetGameTimer()-lastInteraction<250 then return end
    if BuildingPlacement and BuildingPlacement.active then
        if BuildingPlacement.active.pending then F.Notify('busy'); return end
        BuildingPlacement.Stop()
    end
    local record=BuildingClient.records[id]
    if not record then return end
    if BuildingClient.objects[id] and BuildingClient.objects[id].animating then F.Notify('busy'); return end
    interacting=true
    D.HidePrompt()
    local code
    if record.locked and not (record.mine and Config.Doors.ownerBypass) then
        code=password(false)
        if not code then interacting=false; return end
    end
    local desired=not record.open
    lastInteraction=GetGameTimer()
    local value=request('toggle',id,record.revision,desired,code)
    if value.reason=='locked' and not code then
        -- Ask explicitly even if an outdated owner-bypass setting skipped the
        -- first dialog. Recursing would keep making the same uncredentialed call.
        code=password(false)
        if code then
            local remaining=Config.Doors.requestDelay-(GetGameTimer()-lastInteraction)
            if remaining>0 then Wait(remaining) end
            local latest=BuildingClient.records[id]
            if latest then
                lastInteraction=GetGameTimer(); value=request('toggle',id,latest.revision,desired,code)
            end
        end
    end
    interacting=false
    if value.ok and value.record then BuildingClient.Upsert(value.record)
    elseif not value.ok then F.Notify(value.reason) end
end

local function angles(record)
    local def=C.Get(record)
    local angle=record.open and -Config.Doors.openAngle or 0
    return {x=0,y=def.axis=='Y' and angle or 0,z=record.yaw+(def.axis=='Z' and angle or 0)}
end

function D.Remove(entry)
    entry.doorGeneration=(entry.doorGeneration or 0)+1
    if entry.id and D.entries[entry.id]==entry then D.entries[entry.id]=nil end
    if entry.targetName and entry.entity and GetResourceState('ox_target')=='started' then
        pcall(function() exports['ox_target']:removeLocalEntity(entry.entity,entry.targetName) end)
    end
    entry.targetName=nil; entry.targetSignature=nil
    if not next(D.entries) then D.HidePrompt() end
    if entry.anchor then
        pcall(function() exports['corex-core']:RemoveTarget(entry.anchor) end)
        DeleteEntity(entry.anchor); entry.anchor=nil
    end
end

function D.RegisterTarget(entry,record)
    if Config.Doors.target=='none' or GetResourceState('ox_target')~='started' then return end
    local name='corex_building_door_'..record.id
    local signature=record.definition..':'..tostring(record.open)..':'..tostring(record.locked)
    if entry.targetSignature==signature then return end
    local ok=pcall(function()
        exports['ox_target']:addLocalEntity(entry.entity,{{name=name,
            label=(record.open and Config.Text.close or Config.Text.open)..' '..C.Get(record).label,
            icon=record.open and 'fa-solid fa-door-open' or 'fa-solid fa-door-closed',distance=Config.Doors.distance,
            canInteract=function()
                local latest=BuildingClient.records[record.id]
                local p=GetEntityCoords(PlayerPedId())
                return latest~=nil and not interacting and not entry.animating and G.Distance(p,G.Handle(latest))<=Config.Doors.distance
            end,
            onSelect=function() D.Interact(record.id) end}})
    end)
    if ok then entry.targetName,entry.targetSignature=name,signature end
end

function D.Bind(entry,record)
    local def=C.Get(record)
    if not def.moving then return end
    if not entry.entity or not DoesEntityExist(entry.entity) or entry.cancelled then return end
    entry.id=record.id; D.entries[record.id]=entry
    local latest=BuildingClient.records[record.id]
    if latest and latest.definition==record.definition then D.Update(entry,latest,true) end
    if not D.loopStarted then
        D.loopStarted=true
        CreateThread(function()
            while true do
                local id=D.Nearest()
                if id then D.ShowPrompt(id) else D.HidePrompt() end
                Wait(next(D.entries) and Config.Doors.scanInterval or 1000)
            end
        end)
    end
end

function D.Update(entry,record,immediate)
    local def=C.Get(record)
    if not def.moving then return end
    if entry.id then D.RegisterTarget(entry,record) end
    if not immediate and entry.doorOpen==record.open then return end
    entry.doorOpen=record.open; entry.doorGeneration=(entry.doorGeneration or 0)+1
    entry.animating=not immediate
    local target=angles(record)
    if immediate then entry.animating=false; SetEntityRotation(entry.entity,target.x+0.0,target.y+0.0,target.z+0.0,2,true); return end
    local generation=entry.doorGeneration
    local from=GetEntityRotation(entry.entity,2)
    local start=GetGameTimer()
    CreateThread(function()
        while entry.doorGeneration==generation and DoesEntityExist(entry.entity) do
            local t=math.min(1,(GetGameTimer()-start)/Config.Doors.duration)
            local eased=t*t*(3-2*t)
            local function lerp(a,b) return a+((b-a+180)%360-180)*eased end
            SetEntityRotation(entry.entity,lerp(from.x,target.x),lerp(from.y,target.y),lerp(from.z,target.z),2,true)
            if t>=1 then entry.animating=false; break end
            Wait(0)
        end
    end)
end

RegisterCommand(Config.Doors.interactionCommand,function()
    if IsNuiFocused and IsNuiFocused() then return end
    local id=D.Nearest()
    if id then D.Interact(id) end
end,false)
RegisterKeyMapping(Config.Doors.interactionCommand,Config.Text.doorInteract,'keyboard',Config.Doors.interactionKey)

AddEventHandler('onClientResourceStart',function(name)
    if name~='ox_target' then return end
    for id,entry in pairs(D.entries) do
        local record=BuildingClient.records[id]
        entry.targetSignature=nil
        if record then D.RegisterTarget(entry,record) end
    end
end)

local function manageAction(record,action,code)
    if interacting then return end
    interacting=true
    local value=request('manage',record.id,record.revision,action,code)
    interacting=false
    if value.ok then
        if value.record then BuildingClient.Upsert(value.record)
        elseif action=='remove' then BuildingClient.Remove(record.id) end
    else F.Notify(value.reason) end
end

function D.Manage(id)
    if not Config.Management.enabled or interacting then return end
    if BuildingPlacement and BuildingPlacement.active then BuildingPlacement.Stop() end
    local record=BuildingClient.records[id]
    if not record or not record.mine then F.Notify('not_owner'); return end
    local def=C.Get(record)
    local p=GetEntityCoords(PlayerPedId())
    local distance=def.moving and G.Distance(p,G.Handle(record)) or G.BoundsDistance(record,p)
    if distance>Config.Doors.distance+.25 then F.Notify('too_far'); return end
    local options={{title=def.label,description=('HP %.0f / %.0f'):format(record.health,def.health),disabled=true}}
    local nextTier=Config.Tiers[def.tier].next
    if Config.Management.upgrade and nextTier and C.definitions[nextTier..'_'..def.piece] then
        options[#options+1]={title=Config.Text.upgrade..' · '..Config.Tiers[nextTier].label,icon='arrow-up',
            description=C.definitions[nextTier..'_'..def.piece].item,onSelect=function() manageAction(record,'upgrade') end}
    end
    if def.moving and Config.Doors.passwords then
        options[#options+1]={title=Config.Text.setPassword,icon='lock',onSelect=function()
            local code=password(false); if code then manageAction(record,'password',code) end
        end}
        if record.locked and not Config.Doors.requirePassword then
            options[#options+1]={title=Config.Text.clearPassword,icon='unlock',onSelect=function() manageAction(record,'clear_password') end}
        end
    end
    if Config.Management.remove then
        options[#options+1]={title=Config.Text.remove,icon='trash',onSelect=function()
            if lib.alertDialog({header=Config.Text.remove,content=Config.Text.removeConfirm,centered=true,cancel=true})=='confirm' then manageAction(record,'remove') end
        end}
    end
    lib.registerContext({id='corex_building_manage',title=Config.Text.manage,options=options})
    lib.showContext('corex_building_manage')
end
