BuildingServer = { records = {}, pending = {}, leases = {}, locks = {}, subscribers = {}, ready = false }
local B, G, C, S = BuildingServer, BuildingGeometry, BuildingCatalog, BuildingStorage
local resource = GetCurrentResourceName()
local inflight, cooldowns, failures, index, counts = {}, {}, {}, {}, {}
local kitProgress, kitBusy = {}, {}
local total, sequence, epoch, Corex = 0, 0, nil, nil

local function debug(message)
    if Config.Debug then print('[corex-building] '..message) end
end

local function result(ok, reason, record)
    return { ok = ok, reason = reason, record = record }
end

local function copy(value)
    local output = {}; for k,v in pairs(value) do output[k]=v end; return output
end

local function session(src,observe)
    if type(src)~='number' or not Corex then return nil end
    local player=Corex.Functions.GetPlayer(src)
    if not player or type(player.identifier)~='string' then return nil end
    if not observe and (player.isBusy or (player.metadata and player.metadata.lifecycleState and player.metadata.lifecycleState~='active')) then return nil end
    for _, presence in ipairs(exports['corex-core']:GetPlayerPresence(player.identifier)) do
        if presence.source==src then return {identifier=player.identifier,token=presence.sessionToken,bucket=GetPlayerRoutingBucket(src)} end
    end
end

local function capacity(owner)
    local owned,world=counts[owner] or 0,total
    for _,op in pairs(B.pending) do
        if op.kind=='place' then world=world+1; if op.record.owner==owner then owned=owned+1 end end
    end
    return {owner=math.max(0,Config.Placement.ownerLimit-owned),world=math.max(0,Config.Placement.worldLimit-world)}
end

local function current(src, captured)
    local active=session(src)
    return active and captured and active.identifier==captured.identifier and active.token==captured.token
        and active.bucket==captured.bucket
end

local function newId()
    return exports[resource]:NewId()
end

local function crypto(method, ...)
    local p=promise.new()
    local args=table.pack(...)
    args.n=args.n+1; args[args.n]=function(ok,value) p:resolve({ok=ok,value=value}) end
    exports[resource][method](exports[resource],table.unpack(args,1,args.n))
    local value=Citizen.Await(p)
    return value.ok and value.value or nil
end

local function codeValid(code)
    if type(code)~='string' or #code>256 then return false end
    local length=utf8.len(code)
    return length and length>=Config.Doors.minLength and length<=Config.Doors.maxLength
        and not code:find('[%z\1-\31\127]') and code:match('%S')
end

local function throttle(src, action, delay)
    local key=tostring(src)..':'..action
    local now=GetGameTimer()
    if cooldowns[key] and now-cooldowns[key]<delay then return false end
    cooldowns[key]=now
    return true
end

local function coordinates(src)
    local ped=GetPlayerPed(src)
    if not ped or ped==0 then return nil end
    local p=GetEntityCoords(ped)
    return {x=p.x,y=p.y,z=p.z}
end

local function cell(record)
    return table.concat({record.bucket or 0,math.floor(record.x/24),math.floor(record.y/24)},':')
end

local function indexAdd(record)
    local key=cell(record); index[key]=index[key] or {}; index[key][record.id]=true
end

local function indexRemove(record)
    local key=cell(record)
    if index[key] then index[key][record.id]=nil; if not next(index[key]) then index[key]=nil end end
end

local function nearby(point,distance,bucket)
    local records={}
    for x=math.floor((point.x-distance)/24),math.floor((point.x+distance)/24) do
        for y=math.floor((point.y-distance)/24),math.floor((point.y+distance)/24) do
            for id in pairs(index[table.concat({bucket,x,y},':')] or {}) do
                local r=B.records[id]
                if r and G.Distance(point,r)<=distance then records[id]=r end
            end
        end
    end
    return records
end

function B.Public(record,src,captured)
    local active=captured or session(src,true)
    local mine=active and active.identifier==record.owner or false
    return { id=record.id,definition=record.definition,x=record.x,y=record.y,z=record.z,yaw=record.yaw,
        parent=record.parent,socket=record.socket,bucket=record.bucket,revision=record.revision,health=record.health,
        grounded=record.grounded,
        open=record.open==true,locked=Config.Doors.passwords and record.passwordHash~=nil and record.passwordHash~='' or false,
        mine=mine,owner=mine and 'self' or 'other',busy=B.locks[record.id]~=nil }
end

local function push(record, deleted)
    sequence=sequence+1
    for src,subscriber in pairs(B.subscribers) do
        local active=session(src,true); local p=coordinates(src)
        if active and active.token==subscriber.token and active.identifier==subscriber.identifier
            and active.bucket==record.bucket and p and G.Distance(p,record)<=Config.Streaming.unloadDistance+7 then
            subscriber.dirty=true
            TriggerClientEvent('corex-building:client:delta',src,epoch,sequence,
                deleted and {id=record.id,deleted=true,revision=record.revision+1} or B.Public(record,src,active))
        end
    end
end

local function markDirty(record)
    for _,subscriber in pairs(B.subscribers) do
        if subscriber.bucket==record.bucket and subscriber.position
            and G.Distance(subscriber.position,record)<=Config.Streaming.unloadDistance+24 then subscriber.dirty=true end
    end
end

local function store(record)
    local old=B.records[record.id]
    if old then indexRemove(old) else total=total+1; counts[record.owner]=(counts[record.owner] or 0)+1 end
    B.records[record.id]=record; indexAdd(record); push(record)
    debug(('Saved %s / %s / revision %d'):format(record.id,record.definition,record.revision))
end

local function release(op)
    B.pending[op.id]=nil
    for id,lock in pairs(B.locks) do if lock==op.id then B.locks[id]=nil end end
    markDirty(op.record)
end

local function hold(op)
    B.pending[op.id]=op
    pcall(S.Review,op.id)
    print(('[corex-building] Operation %s needs inventory/database review; use corex_build_recover.'):format(op.id))
end

local function check(candidate,owner,src,ignoreOperation)
    local count,world=(counts[owner] or 0),total
    local records=nearby(candidate,13,candidate.bucket)
    for id,op in pairs(B.pending) do
        if op.kind=='place' then
            if id~=ignoreOperation then world=world+1; if op.record.owner==owner then count=count+1 end end
            if op.record.bucket==candidate.bucket and G.Distance(candidate,op.record)<13 then records[op.record.id]=op.record end
        end
    end
    if count>=Config.Placement.ownerLimit or world>=Config.Placement.worldLimit then return false,'limit' end
    local parent,depth=candidate.parent,0
    while parent do
        depth=depth+1
        if depth>64 or not B.records[parent] then return false,'support_required' end
        if B.locks[parent] and B.locks[parent]~=ignoreOperation then return false,'busy' end
        records[parent]=B.records[parent]; parent=records[parent].parent
    end
    local valid,reason=G.Validate(candidate,records,owner)
    if not valid then return false,reason end
    local p=coordinates(src)
    if not p or G.Distance(p,candidate)>Config.Placement.distance then return false,'too_far' end
    if Config.Placement.blockSafeZones and GetResourceState('corex-zones')=='started' then
        local ok,distance=pcall(function() return exports['corex-zones']:GetSafeZoneDistance(candidate) end)
        local bounds=C.Get(candidate).bounds
        local radius=math.sqrt((bounds.max[1]-bounds.min[1])^2+(bounds.max[2]-bounds.min[2])^2)/2
        if not ok or type(distance)~='number' or distance<=radius then return false,'safe_zone' end
    end
    if Config.CanPlace then
        local ok,allowed=pcall(Config.CanPlace,src,copy(candidate))
        if not ok or allowed~=true then return false,'blocked' end
    end
    return true
end

local function run(src, captured, handler)
    if inflight[src] then return result(false,'busy') end
    local guard={session=captured}; inflight[src]=guard
    local ok,value=pcall(handler)
    if inflight[src]==guard then inflight[src]=nil end
    if not ok then
        for id,lock in pairs(B.locks) do
            if lock=='door:'..captured.token or lock=='password:'..captured.token or lock=='remove:'..captured.token then B.locks[id]=nil end
        end
        print('[corex-building] Action failed; no automatic item mutation retry was made.')
        return result(false,'unavailable')
    end
    return value
end

function B.Begin(src,item)
    if not B.ready then return nil,'unavailable' end
    if inflight[src] then return nil,'busy' end
    local active,def=session(src),C.items[item]
    if not active then return nil,'unavailable' end
    if not def or Config.DisabledPieces[def.piece] then return nil,'invalid_item' end
    if not CoreXInventoryBridge.HasItem(src,item,1) then return nil,'missing_item' end
    if not current(src,active) then return nil,'expired' end
    local lease={token=newId(),definition=def.id,item=item,session=active,expires=os.time()+Config.Placement.leaseSeconds,state='open'}
    B.leases[src]=lease
    return {token=lease.token,definition=def.id,bucket=active.bucket,epoch=epoch}
end

local function execute(src,active,op)
    B.pending[op.id]=op
    markDirty(op.record)
    local prepared,accepted=pcall(S.Prepare,op)
    if not prepared or accepted~=true then hold(op); return result(false,'persistence') end
    if not current(src,active) then
        local discarded,ok=pcall(S.Discard,op.id)
        if discarded and ok then release(op) else hold(op) end
        return result(false,'expired')
    end
    local reached,reply=pcall(function()
        return exports['corex-capabilities']:Call('inventory','removeItem',{originResource=resource,traceId=op.id},src,op.item,1)
    end)
    if reached and type(reply)=='table' and reply.ok==true and reply.value==false then
        local discarded,ok=pcall(S.Discard,op.id)
        if discarded and ok then release(op); return result(false,'missing_item') end
        hold(op); return result(false,'persistence')
    end
    if not reached or type(reply)~='table' or reply.ok~=true or reply.value~=true then hold(op); return result(false,'inventory_unknown') end
    op.charged=true
    local committed,ok,persisted=pcall(S.Commit,op)
    if not committed or not ok then hold(op); return result(false,'persistence') end
    local record=persisted or op.record
    release(op); store(record)
    return result(true,nil,B.Public(record,src))
end

function B.Place(src,request)
    if not B.ready then return result(false,'unavailable') end
    if type(request)~='table' then return result(false,'invalid_position') end
    if request.parent and (type(request.parent)~='string' or #request.parent>32 or type(request.socket)~='string' or #request.socket>80) then return result(false,'invalid_position') end
    local lease=B.leases[src]
    if not lease or lease.token~=request.token or os.time()>lease.expires or not current(src,lease.session) then return result(false,'expired') end
    if lease.state~='open' or inflight[src] then return result(false,'busy') end
    if not throttle(src,'place',Config.Placement.requestDelay) then return result(false,'rate_limited') end
    local response=run(src,lease.session,function()
        local def=C.definitions[lease.definition]
        local canonical=copy(request); canonical.bucket=lease.session.bucket
        if not request.parent and def.kind=='deck' then
            if not G.Number(request.groundZ) then return result(false,'invalid_position') end
            if Config.Placement.validateTerrain then
                if not G.Number(request.normalZ) then return result(false,'ground_required') end
                if request.normalZ<math.cos(math.rad(Config.Placement.maxSlope)) then return result(false,'slope') end
                local p=coordinates(src)
                if not p or math.abs(request.groundZ-p.z)>2.5 then return result(false,'ground_required') end
            end
            if request.water and not Config.Placement.allowWater then return result(false,'water') end
            canonical.z=request.groundZ-def.bounds.min[3]
        end
        local candidate,reason=G.Resolve(def,canonical,B.records)
        if not candidate then return result(false,reason) end
        if request.parent and def.piece:find('foundation') then
            if Config.Placement.validateTerrain then
                if request.ground~=true or not G.Number(request.groundZ) or not G.Number(request.normalZ)
                    or math.abs(candidate.z+def.bounds.min[3]-request.groundZ)>Config.Placement.groundTolerance then return result(false,'ground_required') end
                if request.normalZ<math.cos(math.rad(Config.Placement.maxSlope)) then return result(false,'slope') end
            end
            if request.water and not Config.Placement.allowWater then return result(false,'water') end
            candidate.grounded=true
        end
        candidate.bucket=lease.session.bucket
        if candidate.parent and B.records[candidate.parent].bucket~=candidate.bucket then return result(false,'wrong_bucket') end
        if request.preview and not G.MatchesPreview(candidate,request.preview) then return result(false,'preview_changed') end
        candidate.id=lease.token; candidate.owner=lease.session.identifier
        local valid,denial=check(candidate,candidate.owner,src)
        if not valid then return result(false,denial) end
        if not CoreXInventoryBridge.HasItem(src,lease.item,1) then return result(false,'missing_item') end
        if not current(src,lease.session) or B.leases[src]~=lease then return result(false,'expired') end
        local hash
        if def.moving and Config.Doors.passwords then
            if request.code and request.code~='' then
                if not codeValid(request.code) then return result(false,'password_invalid') end
                hash=crypto('HashPassword',request.code)
                if not hash then return result(false,'unavailable') end
            elseif Config.Doors.requirePassword then return result(false,'password_invalid') end
        end
        if not current(src,lease.session) or B.leases[src]~=lease then return result(false,'expired') end
        valid,denial=check(candidate,candidate.owner,src)
        if not valid then return result(false,denial) end
        candidate.aim=nil; candidate.ground=nil; candidate.revision=1; candidate.health=def.health
        candidate.open=false; candidate.passwordHash=hash
        lease.state='pending'
        local op={id=lease.token,kind='place',item=lease.item,record=candidate}
        if candidate.parent then B.locks[candidate.parent]=op.id end
        local value=execute(src,lease.session,op)
        if B.leases[src]==lease then B.leases[src]=nil end
        return value
    end)
    if response.ok and current(src,lease.session) and Config.Placement.continuePlacing then response.lease=B.Begin(src,lease.item) end
    return response
end

local function accessible(src,id,revision,ownerOnly)
    local active,record=session(src),type(id)=='string' and #id<=32 and B.records[id]
    if not active or not record then return nil,nil,'unavailable' end
    if active.bucket~=record.bucket then return nil,nil,'wrong_bucket' end
    if ownerOnly and record.owner~=active.identifier then return nil,nil,'not_owner' end
    if record.revision~=revision then return nil,nil,'stale' end
    if B.locks[id] then return nil,nil,'busy' end
    local p=coordinates(src)
    local distance=p and (C.Get(record).moving and G.Distance(p,G.Handle(record)) or G.BoundsDistance(record,p))
    if not distance or distance>Config.Doors.distance+.25 then return nil,nil,'too_far' end
    return active,record
end

function B.Toggle(src,id,revision,desired,code)
    if not B.ready then return result(false,'unavailable') end
    if type(desired)~='boolean' then return result(false,'invalid_position') end
    local active,record,reason=accessible(src,id,revision,false)
    if not active then return result(false,reason) end
    if not C.Get(record).moving then return result(false,'invalid_item') end
    if record.open==desired then return result(true,nil,B.Public(record,src)) end
    if not throttle(src,'door',Config.Doors.requestDelay) then return result(false,'rate_limited') end
    return run(src,active,function()
        B.locks[id]='door:'..active.token
        local function finish(value) B.locks[id]=nil; return value end
        if Config.Doors.passwords and record.passwordHash and record.passwordHash~=''
            and not (Config.Doors.ownerBypass and record.owner==active.identifier) then
            local attempts=failures[active.identifier]
            if attempts and os.time()<attempts.untilTime then return finish(result(false,'rate_limited')) end
            if attempts and os.time()>=attempts.windowEnd then attempts=nil end
            if not code then return finish(result(false,'locked')) end
            if not codeValid(code) then return finish(result(false,'password_invalid')) end
            local verified=crypto('VerifyPassword',code,record.passwordHash)
            if not verified then
                attempts=attempts or {count=0,untilTime=0,windowEnd=os.time()+Config.Doors.lockoutSeconds}
                attempts.count=attempts.count+1
                if attempts.count>=Config.Doors.attempts then attempts.untilTime=os.time()+Config.Doors.lockoutSeconds; attempts.count=0 end
                failures[active.identifier]=attempts
                return finish(result(false,'password_invalid'))
            end
            failures[active.identifier]=nil
        end
        if not current(src,active) then return finish(result(false,'expired')) end
        local changed=copy(record); changed.open=desired; changed.revision=record.revision+1
        if not S.Update(changed,record.revision) then return finish(result(false,'persistence')) end
        B.locks[id]=nil; store(changed)
        return result(true,nil,B.Public(changed,src))
    end)
end

function B.Manage(src,id,revision,action,code)
    if not B.ready or not Config.Management.enabled then return result(false,'unavailable') end
    local active,record,reason=accessible(src,id,revision,true)
    if not active then return result(false,reason) end
    return run(src,active,function()
        if action=='upgrade' and Config.Management.upgrade then
            local def=C.Get(record); local tier=Config.Tiers[def.tier].next
            local nextDef=tier and C.definitions[tier..'_'..def.piece]
            if not nextDef then return result(false,'no_upgrade') end
            if not CoreXInventoryBridge.HasItem(src,nextDef.item,1) then return result(false,'missing_item') end
            if not current(src,active) then return result(false,'expired') end
            local changed=copy(record); changed.definition=nextDef.id; changed.health=math.max(1,math.floor(record.health/def.health*nextDef.health))
            changed.revision=record.revision+1
            local op={id=newId(),kind='upgrade',item=nextDef.item,record=changed,expected=record.revision}
            B.locks[id]=op.id
            return execute(src,active,op)
        elseif action=='remove' and Config.Management.remove then
            if #G.Descendants(id,B.records)>0 then return result(false,'has_children') end
            for _,op in pairs(B.pending) do if op.record.parent==id or op.record.id==id then return result(false,'busy') end end
            B.locks[id]='remove:'..active.token
            local called,ok=pcall(S.Delete,{id}); ok=called and ok; B.locks[id]=nil
            if not ok then return result(false,'persistence') end
            indexRemove(record); B.records[id]=nil; total=total-1; counts[record.owner]=counts[record.owner]-1; push(record,true)
            return result(true)
        elseif (action=='password' or action=='clear_password') and C.Get(record).moving and Config.Doors.passwords then
            if action=='clear_password' and Config.Doors.requirePassword then return result(false,'password_invalid') end
            if action=='password' and not codeValid(code) then return result(false,'password_invalid') end
            B.locks[id]='password:'..active.token
            local hash=action=='password' and crypto('HashPassword',code) or nil
            if not current(src,active) then B.locks[id]=nil; return result(false,'expired') end
            if action=='password' and not hash then B.locks[id]=nil; return result(false,'unavailable') end
            local changed=copy(record); changed.passwordHash=hash; changed.revision=record.revision+1
            local ok=S.Update(changed,record.revision); B.locks[id]=nil
            if not ok then return result(false,'persistence') end
            store(changed); return result(true,nil,B.Public(changed,src))
        end
        return result(false,'blocked')
    end)
end

function B.State(src,cacheTag)
    if not B.ready then return result(false,'unavailable') end
    local active,p=session(src,true),coordinates(src)
    if not active or not p then return result(false,'unavailable') end
    local subscriber=B.subscribers[src]
    if not subscriber or subscriber.token~=active.token or subscriber.bucket~=active.bucket or subscriber.epoch~=epoch then
        subscriber=copy(active); B.subscribers[src]=subscriber
    end
    local step=math.max(.05,math.min(8,(Config.Streaming.unloadDistance-Config.Streaming.distance)/2))
    local region=table.concat({math.floor(p.x/step),math.floor(p.y/step),math.floor(p.z/step)},':')
    if subscriber.tag and subscriber.tag==cacheTag and subscriber.region==region and not subscriber.dirty then
        return {ok=true,unchanged=true,epoch=epoch,sequence=sequence,bucket=active.bucket,capacity=capacity(active.identifier)}
    end
    if subscriber.epoch==epoch and not throttle(src,'snapshot',math.min(500,Config.Streaming.interval/2)) then return result(false,'rate_limited') end
    subscriber.position,subscriber.region,subscriber.epoch,subscriber.dirty=p,region,epoch,false
    subscriber.version=(subscriber.version or 0)+1
    subscriber.tag=epoch..':'..src..':'..subscriber.version
    local list={}
    for _,record in pairs(nearby(p,Config.Streaming.unloadDistance,active.bucket)) do list[#list+1]=record end
    table.sort(list,function(a,b) return G.Distance(a,p)<G.Distance(b,p) end)
    local public,reserved={},{}
    for i=1,math.min(#list,Config.Streaming.objectLimit) do public[#public+1]=B.Public(list[i],src,active) end
    for _,op in pairs(B.pending) do
        if op.kind=='place' and op.record.bucket==active.bucket and G.Distance(op.record,p)<Config.Streaming.unloadDistance then
            local entry=B.Public(op.record,src,active); entry.reserved=true; reserved[#reserved+1]=entry
        end
    end
    local zones={}
    if Config.Placement.blockSafeZones and GetResourceState('corex-zones')=='started' then
        local ok,value=pcall(function() return exports['corex-zones']:GetSafeZones() end)
        if ok and type(value)=='table' then zones=value end
    end
    return {ok=true,epoch=epoch,sequence=sequence,bucket=active.bucket,cacheTag=subscriber.tag,
        records=public,reservations=reserved,zones=zones,capacity=capacity(active.identifier)}
end

function B.Recover(id,commit)
    local op=B.pending[id]
    if not op then return false,'unknown_operation' end
    local existing=S.Get(op.record.id)
    if existing and S.Matches(existing,op.record) then
        S.MarkApplied(id); release(op); store(existing); return true,'already_applied'
    end
    if commit then
        if op.record.parent and not B.records[op.record.parent] then return false,'support_required' end
        local records=copy(B.records)
        for _,other in pairs(B.pending) do if other.kind=='place' then records[other.record.id]=other.record end end
        local valid,reason=G.Validate(op.record,records,op.record.owner)
        if not valid then return false,reason end
        local ok=S.Commit(op)
        if not ok then return false,'persistence' end
        release(op); store(op.record)
    else
        if not S.Discard(id) then return false,'persistence' end
        release(op)
    end
    return true
end

function B.Damage(id,amount)
    local caller=GetInvokingResource()
    if caller~=resource and not Config.DamageResources[caller] then return false end
    local record=B.records[id]
    if not B.ready or not record or not G.Number(amount) or amount<=0 or B.locks[id] then return false end
    B.locks[id]='damage'
    local changed=copy(record); changed.health=math.max(0,record.health-amount); changed.revision=record.revision+1
    if changed.health>0 then
        local ok=S.Update(changed,record.revision); B.locks[id]=nil
        if ok then store(changed) end
        return ok
    end
    local ids=G.Descendants(id,B.records); ids[#ids+1]=id
    for _,child in ipairs(ids) do if B.locks[child] and child~=id then B.locks[id]=nil; return false end end
    for _,child in ipairs(ids) do B.locks[child]='damage' end
    local called,ok=pcall(S.Delete,ids); ok=called and ok
    for _,child in ipairs(ids) do
        B.locks[child]=nil
        if ok then
            local r=B.records[child]; indexRemove(r); B.records[child]=nil
            total=total-1; counts[r.owner]=counts[r.owner]-1; push(r,true)
        end
    end
    return ok
end

function B.RegisterItems()
    local pack={id='corex-building',resource=resource,framework='qbcore',items={},usableItems={}}
    for _,def in pairs(C.definitions) do
        pack.items[def.item]={label=def.label,weight=Config.Items.weight[def.tier],type='item',image=def.model..'.png',corexImage=def.model..'.png',
            unique=false,useable=true,shouldClose=true,maxStack=Config.Items.stack,description=def.label}
        pack.usableItems[#pack.usableItems+1]=def.item
        local item=def.item
        local registration=exports['corex-capabilities']:Call('usable_items','register',
            {originResource=resource,traceId='usable:'..item},item,function(src)
            local lease,reason=B.Begin(src,item)
            if lease then TriggerClientEvent('corex-building:client:begin',src,lease)
            else TriggerClientEvent('corex:notify',src,Config.Text.reasons[reason or 'unavailable'],'error') end
        end)
        if not registration or registration.ok~=true or registration.value~=true then
            B.startReason=type(registration)=='table' and type(registration.error)=='table' and registration.error.code or 'INVALID_USABLE_REPLY'
            error('Building usable registry unavailable: '..tostring(B.startReason))
        end
    end
    B.startStage='content-pack'
    local registered=exports['corex-content']:RegisterPack(pack)
    assert(registered and registered.ok,'Building content pack registration failed')
    B.itemCount=#pack.usableItems
end

function B.Start()
    B.ready=false
    B.startStage,B.startReason='core',nil
    Corex=exports['corex-core']:GetCoreObject()
    if not Corex then return false end
    B.startStage='database'
    if not S.Init() then return false end
    B.startStage='saved-buildings'
    local records,pending=S.Load()
    B.records,B.pending,B.locks,B.leases=records,pending,{},{}
    B.subscribers={}
    B.startStage='password-helper'
    index,counts,total={}, {},0; epoch=newId(); sequence=0
    B.startStage='saved-buildings'
    for id,record in pairs(records) do
        assert(C.Get(record) and G.Position(record) and G.Number(record.yaw),'Unknown/corrupt saved building '..tostring(id))
        indexAdd(record); total=total+1; counts[record.owner]=(counts[record.owner] or 0)+1
    end
    for _,op in pairs(pending) do
        assert(C.Get(op.record) and G.Position(op.record),'Unknown pending building operation')
        if op.kind=='place' and op.record.parent then B.locks[op.record.parent]=op.id
        elseif op.kind=='upgrade' then B.locks[op.record.id]=op.id end
    end
    B.startStage='usable-items'; B.RegisterItems()
    B.ready=true
    B.startStage='ready'
    print(('[corex-building] Ready: %d usable building items, %d saved structures.'):format(B.itemCount,total))
    return true
end

function B.GiveKit(src,tier,count,reset)
    if src==0 then return result(false,'invalid_player') end
    if not IsPlayerAceAllowed(src,Config.AdminKit.ace) then return result(false,'forbidden') end
    tier=type(tier)=='string' and tier:lower() or ''
    tier=({iron='steel',['خشب']='wood',['حجر']='stone',['حديد']='steel'})[tier] or tier
    if not Config.Tiers[tier] then return result(false,'usage') end
    local active=session(src,true)
    if not B.ready or not active then return result(false,'unavailable') end
    if inflight[src] or kitBusy[active.identifier] then return result(false,'busy') end
    local kits=kitProgress[active.identifier] or {}
    local previous=kits[tier]
    local progress=not reset and previous or nil
    count=tonumber(count or (previous and previous.count) or Config.AdminKit.count)
    if not count or count%1~=0 or count<1 or count>Config.Items.stack then return result(false,'usage') end
    if progress and progress.count~=count then return result(false,'kit_count') end
    if not throttle(src,'kit',Config.AdminKit.cooldown) then return result(false,'rate_limited') end
    local guard={}; kitBusy[active.identifier]=guard
    local value=run(src,active,function()
        progress=progress or {count=count,delivered={},unknown={}}
        kits[tier]=progress; kitProgress[active.identifier]=kits
        local definitions={}
        for _,def in pairs(C.definitions) do if def.tier==tier then definitions[#definitions+1]=def end end
        table.sort(definitions,function(a,b) return a.item<b.item end)
        local report={ok=true,tier=tier,count=count,total=#definitions,given={},already={},missing={},unknown={},delivered=0}
        local stopped=false
        local function stillCurrent()
            local player=session(src,true)
            return player and player.identifier==active.identifier and player.token==active.token and player.bucket==active.bucket
        end
        local function inventoryCall(operation,def,amount)
            local reached,reply=pcall(function()
                local args={src,def.item}; if amount~=nil then args[3]=amount end
                return exports['corex-capabilities']:Call('inventory',operation,
                    {originResource=resource,traceId='kit:'..def.item},table.unpack(args))
            end)
            return reached and type(reply)=='table' and reply.ok==true,reply and type(reply)=='table' and reply.value
        end
        for _,def in ipairs(definitions) do
            if not stillCurrent() then return result(false,'expired') end
            if not progress.delivered[def.item] then
                if progress.unknown[def.item] then report.unknown[#report.unknown+1]=def.item
                elseif stopped then report.missing[#report.missing+1]=def.item
                else
                    local known,owned=inventoryCall('getItemCount',def)
                    if not stillCurrent() then return result(false,'expired') end
                    local list
                    if not known or type(owned)~='number' or owned<0 or owned~=owned or owned==math.huge or owned%1~=0 then
                        list=report.missing; stopped=true
                    elseif owned>=count then list=report.already; progress.delivered[def.item]=true
                    else
                        local accepted,added=inventoryCall('addItem',def,count-owned)
                        if accepted and added==true then list=report.given; progress.delivered[def.item]=true
                        elseif accepted and added==false then list=report.missing
                        else list=report.unknown; progress.unknown[def.item]=true; stopped=true end
                    end
                    list[#list+1]=def.item
                end
            end
            if progress.delivered[def.item] then report.delivered=report.delivered+1 end
        end
        if not stillCurrent() then return result(false,'expired') end
        local message=Config.Text.kitSummary:format(Config.Tiers[tier].label,count,report.delivered,report.total)
        for _,section in ipairs({{report.given,Config.Text.kitGiven},{report.already,Config.Text.kitAlready},
            {report.missing,Config.Text.kitMissing},{report.unknown,Config.Text.kitUnknown}}) do
            if #section[1]>0 then
                local labels={}; for _,name in ipairs(section[1]) do labels[#labels+1]=C.items[name].label end
                message=message..'\n'..section[2]..table.concat(labels,'، ')
            end
        end
        if report.delivered==report.total then message=message..'\n'..Config.Text.kitComplete:format(Config.AdminKit.command,tier) end
        TriggerClientEvent('corex:client:notify',src,message,(#report.missing+#report.unknown)>0 and 'warning' or 'success',15000,Config.Text.kitTitle)
        return report
    end)
    if kitBusy[active.identifier]==guard then kitBusy[active.identifier]=nil end
    return value
end

RegisterCommand(Config.AdminKit.command,function(src,args)
    local reset=args[2]=='reset' or args[3]=='reset'
    local count=args[2]; if count=='reset' then count=args[3] end
    local value=B.GiveKit(src,args[1],count,reset)
    if value.ok or value.reason=='expired' then return end
    local message=value.reason=='forbidden' and Config.Text.kitDenied
        or ((value.reason=='usage' or value.reason=='invalid_player') and Config.Text.kitUsage:format(Config.AdminKit.command,Config.Items.stack))
        or Config.Text.reasons[value.reason] or Config.Text.reasons.unavailable
    if src==0 then print('[corex-building] '..message)
    else TriggerClientEvent('corex:client:notify',src,message,'error') end
end,false)

lib.callback.register('corex-building:state',B.State)
lib.callback.register('corex-building:place',B.Place)
lib.callback.register('corex-building:toggle',B.Toggle)
lib.callback.register('corex-building:manage',B.Manage)
RegisterNetEvent('corex-building:server:cancel',function(token)
    local lease=B.leases[source]
    if lease and lease.token==token and lease.state=='open' then B.leases[source]=nil end
end)
AddEventHandler('playerDropped',function()
    B.leases[source]=nil; inflight[source]=nil; B.subscribers[source]=nil
    cooldowns[tostring(source)..':place']=nil; cooldowns[tostring(source)..':door']=nil
    cooldowns[tostring(source)..':snapshot']=nil
    cooldowns[tostring(source)..':kit']=nil
end)
AddEventHandler('onResourceStart',function(name)
    if name=='corex-zones' then for _,subscriber in pairs(B.subscribers) do subscriber.dirty=true end end
    if B.ready and (name=='corex-capabilities' or name=='corex-content') then SetTimeout(250,function() pcall(B.RegisterItems) end) end
end)
CreateThread(function()
    while not B.ready do
        local ok,started=pcall(B.Start)
        if not ok or not started then
            print(('[corex-building] Startup deferred at %s%s.'):format(B.startStage or 'unknown',B.startReason and (' ('..B.startReason..')') or ''))
            Wait(5000)
        end
    end
end)
exports('GetStructure',function(id) local r=B.records[id]; return r and B.Public(r,0) end)
exports('DamageStructure',B.Damage)
exports('RecoverOperation',function(id,commit)
    if GetInvokingResource()~=resource then return false end
    return B.Recover(id,commit==true)
end)
RegisterCommand('corex_build_recover',function(src,args)
    if src~=0 or not args[1] or (args[2]~='commit' and args[2]~='discard') then return end
    local ok,reason=B.Recover(args[1],args[2]=='commit')
    print(('[corex-building] Recovery %s: %s'):format(args[1],ok and 'complete' or (reason or 'failed')))
end,true)
RegisterCommand('corex_build_give',function(src,args)
    if src~=0 and not IsPlayerAceAllowed(src,'command.corex_build_give') then return end
    local target,count=tonumber(args[1]),tonumber(args[4] or '1')
    local def=args[2] and args[3] and C.definitions[args[2]..'_'..args[3]]
    if not def or not target or not count or count%1~=0 or count<1 or count>Config.Items.stack then return end
    CoreXInventoryBridge.AddItem(target,def.item,count)
end,true)
