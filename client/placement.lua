BuildingPlacement = { active = nil }
local P,G,C,F,B = BuildingPlacement,BuildingGeometry,BuildingCatalog,BuildingFeedback,BuildingClient
local blockedControls={14,15,24,25,37,44,140,141,142,241,242,257}

-- Native BOOL output parameters can be numeric (0/1). Lua treats 0 as truthy.
local function nativeTrue(value)
    return value==true or value==1
end

function P.IsPreview(state,entity)
    if not entity or entity==0 then return false end
    if entity==state.ghost then return true end
    for _,entry in pairs(state.guidePool or {}) do if entry.entity==entity then return true end end
    return false
end

function P.ConfigurePreview(entity)
    SetEntityAsMissionEntity(entity,true,true)
    SetEntityCollision(entity,false,false)
    -- This native takes collision-enabled, despite its historical name.
    SetEntityCompletelyDisableCollision(entity,false,false)
    SetEntityHasGravity(entity,false)
    FreezeEntityPosition(entity,true)
    SetEntityInvincible(entity,true)
end

function P.ProtectPlayer(state)
    local ped=PlayerPedId()
    if state.ghost then SetEntityNoCollisionEntity(state.ghost,ped,true) end
    for _,entry in pairs(state.guidePool or {}) do SetEntityNoCollisionEntity(entry.entity,ped,true) end
end

-- Consume asynchronous native results every render frame. Validation is
-- throttled, but a native handle must not wait for that slower tick.
function P.PollProbes(state)
    local active={}
    if state.groundProbe then
        for _,handle in pairs(state.groundProbe.handles) do active[handle]=true end
    end
    if state.worldHandle then active[state.worldHandle]=true end
    local results=state.probeResults or {}; state.probeResults=results
    for handle in pairs(results) do if not active[handle] then results[handle]=nil end end
    for handle in pairs(active) do
        if not results[handle] then
            local status,hit,point,normal,entity=GetShapeTestResult(handle)
            if status~=1 then results[handle]={status,hit,point,normal,entity} end
        end
    end
end

local function probeResult(state,handle)
    local cached=state.probeResults and state.probeResults[handle]
    if cached then
        state.probeResults[handle]=nil
        return table.unpack(cached,1,5)
    end
    return GetShapeTestResult(handle)
end

local function vector(p)
    return {x=p.x,y=p.y,z=p.z}
end

local function key(candidate)
    return tostring(candidate.parent)..':'..tostring(candidate.socket)
end

function P.Select(def,records,point,camera,previous,choices,manual)
    local best,bestScore,old,oldScore=nil,math.huge,nil,nil
    choices=choices or G.Candidates(def,records,point)
    if manual and G.Distance(manual.point,point)<=Config.Guides.releaseDistance then
        for _,candidate in ipairs(choices) do if key(candidate)==manual.key then return candidate end end
    end
    local dx,dy=point.x-camera.x,point.y-camera.y
    local length=math.sqrt(dx*dx+dy*dy)
    for _,candidate in ipairs(choices) do
        local distance=G.Distance(candidate.aim,point)
        if distance<=Config.Placement.snapRadius then
            local score=distance
            if length>.01 and (def.kind=='wall' or def.kind=='edge') then
                local angle=math.rad(candidate.yaw)
                local facing=(dx*math.sin(angle)-dy*math.cos(angle))/length
                score=score+Config.Placement.cameraWeight*(1-facing)
            elseif length>.01 and (def.kind=='deck' or def.kind=='beam' or def.kind=='access') then
                local vx,vy=candidate.x-candidate.aim.x,candidate.y-candidate.aim.y
                local span=math.sqrt(vx*vx+vy*vy)
                if span>.01 then score=score+Config.Placement.cameraWeight*(1-(dx*vx+dy*vy)/(length*span)) end
            end
            if score<bestScore-.0001 or (math.abs(score-bestScore)<.0001 and (not best or key(candidate)<key(best))) then
                best,bestScore=candidate,score
            end
            if previous and key(candidate)==key(previous) then old,oldScore=candidate,score end
        end
    end
    if old and oldScore<=bestScore+Config.Placement.hysteresis then return old end
    return best
end

function P.Choices(state,def,records,point)
    if state.choices and state.choicesDefinition==def.id and state.choicesRecords==records
        and G.Distance(state.choicesPoint,point)<1 then return state.choices end
    state.choicesDefinition,state.choicesRecords,state.choicesPoint=def.id,records,vector(point)
    state.choices=G.Candidates(def,records,point,Config.Placement.distance+9)
    return state.choices
end

function P.Rotate(state,direction)
    state.yaw=(state.yaw+direction*Config.Placement.rotationStep)%360
    state.groundProbe=nil; state.groundResult=nil; state.validation=nil
    local selected=state.candidate
    if not selected or not selected.parent or state.forceFree then return end
    local choices={}
    for _,candidate in ipairs(state.choices or {}) do
        if candidate.parent==selected.parent then choices[#choices+1]=candidate end
    end
    table.sort(choices,function(a,b)
        if a.yaw~=b.yaw then return a.yaw<b.yaw end
        return key(a)<key(b)
    end)
    if #choices<2 then return end
    local index=1
    for i,candidate in ipairs(choices) do if key(candidate)==key(selected) then index=i; break end end
    local nextChoice=choices[(index-1+direction)%#choices+1]
    state.manual={key=key(nextChoice),point=vector(state.lastPoint or selected.aim or selected)}
    state.candidate=nextChoice
end

function P.HideGuides(state)
    for _,entry in pairs(state.guidePool or state.guides or {}) do
        if entry.visible~=false and DoesEntityExist(entry.entity) then
            SetEntityVisible(entry.entity,false,false)
            SetEntityAlpha(entry.entity,0,false)
            entry.visible=false
        end
    end
    state.guides=nil; state.guideSignature=nil
end

function P.ClearGuides(state)
    for _,entry in pairs(state.guidePool or state.guides or {}) do
        if DoesEntityExist(entry.entity) then DeleteEntity(entry.entity) end
    end
    state.guides=nil; state.guidePool=nil
    state.guideSignature=nil
end

function P.MoveGhost(state,candidate,force)
    local previous=state.visualPose; local now=GetGameTimer()
    local applied=state.appliedPose
    local x,y,z=candidate.x,candidate.y,candidate.z
    if previous and not force and not candidate.parent and Config.Preview.smoothing>0 then
        local alpha=1-math.exp(-math.max(1,now-previous.time)/Config.Preview.smoothing)
        x=previous.x+(x-previous.x)*alpha; y=previous.y+(y-previous.y)*alpha; z=previous.z+(z-previous.z)*alpha
    end
    if not applied or force or math.abs(x-applied.x)+math.abs(y-applied.y)+math.abs(z-applied.z)>.0001 then
        SetEntityCoordsNoOffset(state.ghost,x,y,z,false,false,false)
        state.appliedPose={x=x,y=y,z=z}
    end
    if not previous or force or previous.yaw~=candidate.yaw then SetEntityHeading(state.ghost,candidate.yaw+0.0) end
    state.visualPose={x=x,y=y,z=z,yaw=candidate.yaw,time=now}
end

function P.Stop()
    F.Hide()
    local state=P.active
    if not state then return end
    P.active=nil; state.cancelled=true
    P.ClearGuides(state)
    if state.ghost and DoesEntityExist(state.ghost) then
        local appearance=F.ghosts and F.ghosts[state.ghost]
        if appearance and appearance.nativeActive then pcall(function() SetEntityDrawOutline(state.ghost,false) end) end
        DeleteEntity(state.ghost)
    end
    F.Forget(state.ghost)
    if state.hash then SetModelAsNoLongerNeeded(state.hash) end
    TriggerServerEvent('corex-building:server:cancel',state.lease.token)
end

function P.Raycast(state)
    if state.ray and nativeTrue(state.ray.hit) and not P.IsPreview(state,state.ray.entity) then
        state.surfacePoint=state.ray.point; state.surfaceTime=state.ray.time
    end
    if state.rayHandle then
        local status,hit,point,normal,entity=GetShapeTestResult(state.rayHandle)
        state.rayStatus=status
        if status~=1 or GetGameTimer()-(state.rayStarted or GetGameTimer())>=1000 then
            state.rayHandle=nil
            if status==2 then
                hit=nativeTrue(hit) and not P.IsPreview(state,entity)
                state.ray={hit=hit,point=vector(point),normal=vector(normal),entity=entity,time=GetGameTimer()}
                if hit then state.surfacePoint=state.ray.point; state.surfaceTime=state.ray.time end
            end
        end
    end
    local cam,rot=GetGameplayCamCoord(),GetGameplayCamRot(2)
    local direction=G.CameraDirection(rot)
    local distance=Config.Placement.distance+5
    if not state.rayHandle then
        state.rayStarted=GetGameTimer()
        state.rayHandle=StartShapeTestLosProbe(cam.x,cam.y,cam.z,cam.x+direction.x*distance,
            cam.y+direction.y*distance,cam.z+direction.z*distance,19,state.ghost or PlayerPedId(),7)
    end
    local ray=state.ray
    local point=state.surfacePoint
    local p=GetEntityCoords(PlayerPedId())
    state.player=vector(p)
    if point and state.surfaceTime and GetGameTimer()-state.surfaceTime>80 then point=nil; state.surfacePoint=nil end
    if point and (not G.Position(point) or G.Distance(point,vector(p))>distance) then
        point=nil; state.surfacePoint=nil
    end
    if not point then
        local angle=math.rad(rot.z)
        point={x=p.x-math.sin(angle)*3,y=p.y+math.cos(angle)*3,z=p.z-1}
    end
    return ray,point,vector(cam)
end

local function nearPose(a,b,radius)
    return a and (a.x-b.x)^2+(a.y-b.y)^2<=radius^2 and math.abs((a.yaw-b.yaw+180)%360-180)<1
end

local function terrainHeight(sample)
    RequestCollisionAtCoord(sample.x,sample.y,sample.top)
    local found,z=GetGroundZFor_3dCoord(sample.x,sample.y,sample.top,false)
    sample.nativeFound=found; sample.nativeZ=z
    if nativeTrue(found) and type(z)=='number' and z>=sample.bottom and z<=sample.top then
        return {hit=true,z=z}
    end
end

local function terrainRay(state,sample)
    return StartShapeTestLosProbe(sample.x,sample.y,sample.top,
        sample.x,sample.y,sample.bottom,17,state.ghost or PlayerPedId(),7)
end

local function groundProbe(state,candidate,def,exact)
    local probe=state.groundProbe
    if exact and probe and not nearPose(probe.at,candidate,.01) then probe=nil; state.groundProbe=nil end
    if probe then
        for i,handle in pairs(probe.handles) do
            local status,hit,point,_,entity=probeResult(state,handle)
            probe.samples[i].rayStatus=status
            probe.samples[i].rayHit=hit; probe.samples[i].rayEntity=entity
            local expired=GetGameTimer()-probe.started>=1000
            if status==2 or status==0 or expired then
                local value
                if status==2 and nativeTrue(hit) then value={hit=true,z=point.z}
                else value=terrainHeight(probe.samples[i]) end
                local sample=probe.samples[i]
                if status~=2 and not value then
                    sample.retries=(sample.retries or 0)+1
                    if expired or sample.retries>=3 then value={hit=false,failed=true} end
                end
                if value or status==2 then
                    probe.handles[i]=nil; probe.values[i]=value or {hit=false}
                    if value and value.failed then probe.failed=true end
                else
                    probe.handles[i]=terrainRay(state,probe.samples[i])
                end
            end
        end
        if not next(probe.handles) then
            probe.time=GetGameTimer(); state.groundResult=probe; state.groundProbe=nil; probe=nil
        end
    end
    local completed=state.groundResult
    local usable=completed and nearPose(completed.at,candidate,exact and .01 or .6)
        and (completed.failed or GetGameTimer()-completed.time<500)
    if not probe and (not usable or not nearPose(completed.at,candidate,.2) or GetGameTimer()-completed.time>150) then
        local points=def.triangle and {{-1.35,-.75},{1.35,-.75},{0,1.5}} or {{-1.35,-1.35},{1.35,-1.35},{1.35,1.35},{-1.35,1.35}}
        probe={at={x=candidate.x,y=candidate.y,yaw=candidate.yaw},handles={},values={},samples={},started=GetGameTimer()}
        local playerZ=GetEntityCoords(PlayerPedId()).z
        for i,point in ipairs(points) do
            local p=G.Offset(candidate,point[1],point[2],0)
            local sample={x=p.x,y=p.y,localX=point[1],localY=point[2],top=math.max(p.z,playerZ)+2,bottom=math.min(p.z,playerZ)-5}
            probe.samples[i]=sample
            RequestCollisionAtCoord(sample.x,sample.y,sample.top)
            probe.handles[i]=terrainRay(state,sample)
        end
        state.groundProbe=probe
    end
    if not usable then return false,'checking' end
    local lo,hi,sum=math.huge,-math.huge,0
    for _,value in ipairs(completed.values) do
        if value.failed then return false,'probe_failed' end
        if not value.hit then return false,'ground_miss' end
        lo,hi=math.min(lo,value.z),math.max(hi,value.z)
        sum=sum+value.z
    end
    local v=completed.values
    local dx,dy
    if def.triangle then dx=(v[2].z-v[1].z)/2.7; dy=(v[3].z-(v[1].z+v[2].z)/2)/2.25
    else dx=(v[2].z+v[3].z-v[1].z-v[4].z)/5.4; dy=(v[3].z+v[4].z-v[1].z-v[2].z)/5.4 end
    local normalZ=1/math.sqrt(1+dx*dx+dy*dy)
    local groundZ,deviation=sum/#v,0
    -- Measure roughness relative to the terrain plane. Its total rise is
    -- already limited by maxSlope and must not impose a second, yaw-dependent limit.
    for i,value in ipairs(v) do
        local sample=completed.samples[i]
        deviation=math.max(deviation,math.abs(value.z-groundZ-dx*sample.localX-dy*sample.localY))
    end
    completed.minZ,completed.maxZ,completed.groundZ=lo,hi,groundZ
    completed.normalZ,completed.deviation=normalZ,deviation
    if normalZ<math.cos(math.rad(Config.Placement.maxSlope)) then return false,'slope' end
    if deviation>Config.Placement.groundTolerance then return false,'slope' end
    local bottom=candidate.z+def.bounds.min[3]
    if candidate.parent and math.max(math.abs(bottom-lo),math.abs(bottom-hi))>Config.Placement.groundTolerance then return false,'ground_height' end
    if not candidate.parent then
        -- Keep the walking surface above the highest sampled terrain without
        -- changing the level of pieces snapped to an existing structure.
        groundZ=math.max(groundZ,hi-(def.bounds.max[3]-def.bounds.min[3]))
    end
    return true,nil,normalZ,groundZ
end

local function worldProbe(state,candidate,def)
    local reusable=nearPose(state.worldAt,candidate,.6) and math.abs((state.worldAt and state.worldAt.z or 0)-candidate.z)<.25
    if not reusable then state.worldClear=nil; state.worldFailed=nil; state.worldRetries=0 end
    if state.worldHandle then
        local status,hit,point,normal,entity=probeResult(state,state.worldHandle)
        state.worldStatus=status
        if status~=1 or GetGameTimer()-(state.worldTime or 0)>=1000 then
            state.worldHandle=nil
            if reusable and status==2 then
                hit=nativeTrue(hit)
                state.worldFailed=nil; state.worldRetries=0
                local groundTop=candidate.z+def.bounds.min[3]
                local ground=state.groundResult
                if candidate.grounded and ground and ground.maxZ and nearPose(ground.at,candidate,.6) then
                    groundTop=math.max(groundTop,ground.maxZ)
                end
                -- Upward-facing world terrain may touch the lower bound on
                -- a permitted slope. Vertical walls and entity props remain obstacles.
                state.worldClear=not hit or B.entityIds[entity]~=nil
                    or (entity==0 and normal.z>.5 and point.z<=groundTop+Config.Placement.groundTolerance)
                state.worldResult={hit=hit,entity=entity,z=point.z,normalZ=normal.z}
            elseif reusable then
                -- A non-colliding custom preview may not have a usable physical
                -- bound. Its model bounding box provides an independent query.
                state.worldUseBox=true
                state.worldRetries=(state.worldRetries or 0)+1
                if status==1 or state.worldRetries>=3 then state.worldFailed=true; state.worldClear=nil end
            end
        end
    end
    if not state.worldHandle and GetGameTimer()-(state.worldTime or 0)>120 then
        state.worldTime=GetGameTimer()
        state.worldAt={x=candidate.x,y=candidate.y,z=candidate.z,yaw=candidate.yaw}
        state.worldHandle=state.worldUseBox and StartShapeTestBoundingBox(state.ghost,19,7)
            or StartShapeTestBound(state.ghost,19,7)
        state.worldCreatedHandle=state.worldHandle
    end
    return state.worldClear==true,state.worldFailed and 'probe_failed' or (state.worldClear==false and 'obstructed' or 'checking')
end

function P.Update(state,ray,point,camera,force)
    local def=C.definitions[state.lease.definition]
    state.lastRay,state.lastPoint,state.lastCamera=ray,vector(point),vector(camera)
    local records=B.PlacementRecords(point)
    local choices=P.Choices(state,def,records,point)
    if state.manual and G.Distance(state.manual.point,point)>Config.Guides.releaseDistance then state.manual=nil end
    local selected=not state.forceFree and P.Select(def,records,point,camera,state.candidate,choices,state.manual) or nil
    local candidate
    if selected then candidate={}; for name,value in pairs(selected) do candidate[name]=value end end
    local request
    if candidate then request={parent=candidate.parent,socket=candidate.socket}
    else
        local root={x=point.x,y=point.y,z=point.z-def.bounds.min[3],yaw=state.yaw,bucket=B.bucket,
            ground=ray and nativeTrue(ray.hit) and not B.entityIds[ray.entity] or false}
        candidate=G.Resolve(def,root,records)
        request={x=point.x,y=point.y,yaw=state.yaw,ground=root.ground,groundZ=point.z,normalZ=ray and ray.normal.z or 0}
        if not candidate then candidate={definition=def.id,x=point.x,y=point.y,z=point.z,yaw=state.yaw,bucket=B.bucket} end
    end
    request.token=state.lease.token
    local needsGround=not candidate.parent or def.piece:find('foundation')~=nil
    local reason,valid=nil,true
    if not B.ready then valid,reason=false,'unavailable'
    elseif B.capacity and (B.capacity.owner<=0 or B.capacity.world<=0) then valid,reason=false,'limit'
    elseif not candidate.parent and def.kind~='deck' then valid,reason=false,G.SupportReason(def)
    elseif not needsGround and (not ray or GetGameTimer()-ray.time>350) then valid,reason=false,'aim_lost'
    else
        if needsGround then
            state.checkStage='ground'
            request.ground=true
            request.groundZ=candidate.z+def.bounds.min[3]
            local normalZ,groundZ
            if Config.Placement.validateTerrain then
                valid,reason,normalZ,groundZ=groundProbe(state,candidate,def)
            else
                normalZ=1
                groundZ=candidate.parent and request.groundZ or point.z
                if not candidate.parent and not (ray and nativeTrue(ray.hit) and ray.normal and ray.normal.z>.5) then
                    local playerZ=(state.player or GetEntityCoords(PlayerPedId())).z
                    local cached=state.directGround
                    local height
                    if cached and not force and GetGameTimer()-cached.time<150
                        and (cached.x-candidate.x)^2+(cached.y-candidate.y)^2<.04 then height=cached.height
                    else
                        height=terrainHeight({x=candidate.x,y=candidate.y,top=math.max(point.z,playerZ)+2,
                            bottom=math.min(point.z,playerZ)-5})
                        state.directGround={x=candidate.x,y=candidate.y,time=GetGameTimer(),height=height}
                    end
                    if height then groundZ=height.z
                    elseif math.abs(groundZ-playerZ)>2.5 then groundZ=playerZ-1 end
                end
            end
            request.normalZ=normalZ; request.groundZ=groundZ; candidate.grounded=valid
            if valid then
                local cached=state.waterResult
                if cached and not force and GetGameTimer()-cached.time<150
                    and (cached.x-candidate.x)^2+(cached.y-candidate.y)^2<.04 and math.abs(cached.z-groundZ)<.1 then
                    request.water=cached.water
                else
                    local water,waterZ=GetWaterHeightNoWaves(candidate.x,candidate.y,groundZ+2)
                    request.water=nativeTrue(water) and waterZ>=groundZ-.05 or false
                    state.waterResult={x=candidate.x,y=candidate.y,z=groundZ,time=GetGameTimer(),water=request.water}
                end
                if request.water and not Config.Placement.allowWater then valid,reason=false,'water'
                elseif not candidate.parent then candidate.z=groundZ-def.bounds.min[3] end
            end
        end
        if valid then
            local pose=table.concat({candidate.definition,candidate.parent or '',candidate.socket or '',
                math.floor(candidate.x*100),math.floor(candidate.y*100),math.floor(candidate.z*100),candidate.yaw,
                tostring(candidate.grounded),tostring(state.forceFree)},':')
            local cached=state.validation
            if not force and cached and cached.pose==pose and cached.records==records then valid,reason=cached.valid,cached.reason
            else
                valid,reason=G.Validate(candidate,records,'self')
                state.validation={pose=pose,records=records,valid=valid,reason=reason}
            end
        end
        if valid and G.Distance(state.player or vector(GetEntityCoords(PlayerPedId())),candidate)>Config.Placement.distance then valid,reason=false,'too_far' end
        if valid and Config.Placement.blockSafeZones then
            local radius=math.sqrt((def.bounds.max[1]-def.bounds.min[1])^2+(def.bounds.max[2]-def.bounds.min[2])^2)/2
            for _,zone in ipairs(B.zones or {}) do
                if G.Distance(candidate,zone.coords)<=zone.radius+radius then valid,reason=false,'safe_zone'; break end
            end
        end
    end
    P.MoveGhost(state,candidate,force)
    if valid and Config.Placement.checkWorldCollision then state.checkStage='world'; valid,reason=worldProbe(state,candidate,def) end
    state.candidate,state.request,state.valid,state.reason=candidate,request,valid,reason
    local displayReason=reason=='checking' and (state.checkStage=='ground' and 'checking_ground' or 'checking_world') or reason
    F.Ghost(state.ghost,valid); F.Show(def,valid,displayReason,state.pending,candidate.parent~=nil,
        state.guides and #state.guides or 0,state.forceFree)
end

function P.UpdateGuides(state)
    if not Config.Guides.enabled or state.forceFree or not state.hash then
        if state.guides then P.HideGuides(state) end
        return
    end
    local now=GetGameTimer()
    local point=state.lastPoint
    if not point then return end
    local signature=table.concat({state.lease.definition,math.floor(point.x*4),math.floor(point.y*4),math.floor(point.z*4),
        state.candidate and G.Key(state.candidate) or ''},':')
    if state.guides and state.guideSignature==signature and state.guideVersion==B.placementVersion then return end
    if state.guideTime and now-state.guideTime<Config.Guides.interval and state.guideVersion==B.placementVersion then return end
    state.guideTime,state.guideVersion,state.guideSignature=now,B.placementVersion,signature
    local choices={}
    for _,candidate in ipairs(state.choices or {}) do choices[#choices+1]=candidate end
    table.sort(choices,function(a,b) return G.Distance(a.aim,point)<G.Distance(b.aim,point) end)
    local records=B.PlacementRecords(point); local wanted,seen={},{}
    local selectedKey=state.candidate and G.Key(state.candidate)
    for i=1,math.min(#choices,12) do
        local candidate=choices[i]; local pose=G.Key(candidate)
        if not seen[pose] and pose~=selectedKey and G.Distance(candidate,state.player or point)<=Config.Placement.distance then
            seen[pose]=true
            local valid=G.Validate(candidate,records,'self')
            if valid then wanted[#wanted+1]=candidate; if #wanted>=Config.Guides.count then break end end
        end
    end
    -- Reuse a bounded pool instead of destroying physics/render instances when
    -- the aim or Shift mode changes. A guide keeps its model data until Stop.
    local pool=state.guidePool or {}; state.guidePool=pool
    local guides={}
    for i,candidate in ipairs(wanted) do
        local pose=G.Key(candidate); local entry=pool[i]
        if entry and not DoesEntityExist(entry.entity) then entry=nil; pool[i]=nil end
        if not entry then
            local entity=CreateObjectNoOffset(state.hash,candidate.x,candidate.y,candidate.z-100.0,false,false,false)
            if entity~=0 then
                P.ConfigurePreview(entity)
                SetEntityAlpha(entity,Config.Guides.alpha,false); SetEntityLodDist(entity,Config.Streaming.distance)
                entry={key=pose,entity=entity,visible=true}; pool[i]=entry
            end
        end
        if entry then
            if entry.visible==false then
                SetEntityVisible(entry.entity,true,false); SetEntityAlpha(entry.entity,Config.Guides.alpha,false)
            end
            SetEntityCoordsNoOffset(entry.entity,candidate.x,candidate.y,candidate.z,false,false,false)
            SetEntityHeading(entry.entity,candidate.yaw+0.0)
            entry.key,entry.candidate,entry.visible=pose,candidate,true; guides[#guides+1]=entry
        end
    end
    for i,entry in pairs(pool) do
        if i>#wanted and entry.visible~=false and DoesEntityExist(entry.entity) then
            SetEntityVisible(entry.entity,false,false); SetEntityAlpha(entry.entity,0,false); entry.visible=false
        end
    end
    state.guides=guides
end

function P.DrawGuides(state)
    for _,entry in ipairs(state.guides or {}) do
        local aim=entry.candidate.aim
        DrawMarker(27,aim.x,aim.y,aim.z+.025,0.0,0.0,0.0,0.0,0.0,0.0,.25,.25,.04,
            112,174,145,150,false,false,2,false,nil,nil,false)
    end
end

local function rejectPlacement(state,reason)
    if reason=='ground_miss' or reason=='checking' or reason=='ground_height' or reason=='slope' or reason=='probe_failed' then
        local probe=reason=='checking' and (state.groundProbe or state.groundResult) or (state.groundResult or state.groundProbe)
        if probe and GetGameTimer()-(state.diagnosticTime or 0)>2000 then
            state.diagnosticTime=GetGameTimer()
            local corners={}
            for i,sample in ipairs(probe.samples) do
                local value=probe.values[i]
                corners[i]=string.format('%d:ray=%s/hit=%s/entity=%s/native=%s/z=%s',i,tostring(sample.rayStatus),
                    tostring(sample.rayHit),tostring(sample.rayEntity),tostring(sample.nativeFound),
                    tostring(value and value.z or sample.nativeZ))
            end
            local slope=probe.normalZ and math.deg(math.acos(math.min(1,probe.normalZ)))
            print(string.format('[corex-building] Ground resolver v5: %s at=%.2f,%.2f yaw=%.1f slope=%s/max=%s roughness=%s/tolerance=%s %s',
                reason,probe.at.x,probe.at.y,probe.at.yaw,tostring(slope),tostring(Config.Placement.maxSlope),
                tostring(probe.deviation),tostring(Config.Placement.groundTolerance),table.concat(corners,' ')))
            print(string.format('[corex-building] Probe stage=%s cameraStatus=%s cameraHit=%s worldStatus=%s worldRetries=%s worldHandle=%s worldMethod=%s',
                tostring(state.checkStage),tostring(state.rayStatus),tostring(state.ray and state.ray.hit),
                tostring(state.worldStatus),tostring(state.worldRetries),tostring(state.worldCreatedHandle),
                state.worldUseBox and 'bounding_box' or 'bound'))
        end
    end
    F.Reject(reason)
end

function P.PrepareShown(state)
    if not state.candidate or not state.request then return nil,nil,'invalid_position' end
    local def=C.definitions[state.lease.definition]
    local candidate,request={},{}
    for name,value in pairs(state.candidate) do candidate[name]=value end
    for name,value in pairs(state.request) do request[name]=value end
    local shown=state.visualPose or candidate
    if not G.Position(shown) or not G.Number(shown.yaw) then return nil,nil,'invalid_position' end
    local records=B.PlacementRecords(shown)
    if candidate.parent then
        local resolved=G.Resolve(def,{parent=candidate.parent,socket=candidate.socket},records)
        if not resolved or not G.MatchesPreview(resolved,shown) then return nil,nil,'preview_changed' end
        candidate.x,candidate.y,candidate.z,candidate.yaw=resolved.x,resolved.y,resolved.z,resolved.yaw
    else
        candidate.x,candidate.y,candidate.z,candidate.yaw=shown.x,shown.y,shown.z,shown.yaw
        request.x,request.y,request.yaw=shown.x,shown.y,shown.yaw
        request.groundZ=shown.z+def.bounds.min[3]; request.ground=true
    end
    if not B.ready then return nil,nil,'unavailable' end
    if B.capacity and (B.capacity.owner<=0 or B.capacity.world<=0) then return nil,nil,'limit' end
    local valid,reason=G.Validate(candidate,records,'self')
    if not valid then return nil,nil,reason end
    local player=vector(GetEntityCoords(PlayerPedId()))
    if G.Distance(player,candidate)>Config.Placement.distance then return nil,nil,'too_far' end
    if def.kind=='deck' and (not candidate.parent or def.piece:find('foundation')) then
        local groundZ=candidate.z+def.bounds.min[3]
        local water,waterZ=GetWaterHeightNoWaves(candidate.x,candidate.y,groundZ+2)
        request.water=nativeTrue(water) and waterZ>=groundZ-.05 or false
        if request.water and not Config.Placement.allowWater then return nil,nil,'water' end
    end
    request.preview={x=candidate.x,y=candidate.y,z=candidate.z,yaw=candidate.yaw}
    return candidate,request
end

local function submit(state)
    if state.pending then return end
    if not state.valid then rejectPlacement(state,state.reason); return end
    local candidate,request,reason=P.PrepareShown(state)
    if not candidate then state.valid=false; state.reason=reason; rejectPlacement(state,reason); return end
    state.candidate,state.request=candidate,request
    P.MoveGhost(state,candidate,true)
    state.pending=true
    F.Show(C.definitions[state.lease.definition],true,nil,true,state.candidate and state.candidate.parent~=nil)
    CreateThread(function()
        local def=C.definitions[state.lease.definition]
        if Config.Placement.validateTerrain and def.kind=='deck' and (not state.candidate.parent or def.piece:find('foundation')) then
            state.groundProbe=nil; state.groundResult=nil
            local start=GetGameTimer()
            while not state.cancelled and P.active==state do
                local valid,reason,normalZ,groundZ=groundProbe(state,state.candidate,def,true)
                if valid then
                    local checkedZ=state.candidate.parent and state.candidate.z or groundZ-def.bounds.min[3]
                    if math.abs(checkedZ-request.preview.z)>.01 then
                        state.pending=false; state.valid=false; state.reason='preview_changed'; F.Reject('preview_changed'); return
                    end
                    local water,waterZ=GetWaterHeightNoWaves(state.candidate.x,state.candidate.y,groundZ+2)
                    request.water=nativeTrue(water) and waterZ>=groundZ-.05 or false
                    if request.water and not Config.Placement.allowWater then
                        state.pending=false; state.valid=false; state.reason='water'; F.Reject('water'); return
                    end
                    request.groundZ,request.normalZ=groundZ,normalZ
                    if not state.candidate.parent then state.candidate.z=groundZ-def.bounds.min[3] end
                    P.MoveGhost(state,state.candidate,true)
                    break
                elseif reason~='checking' or GetGameTimer()-start>1000 then
                    state.pending=false; state.valid=false; state.reason=reason; rejectPlacement(state,reason); return
                end
                Wait(0)
            end
        end
        if def.moving and Config.Doors.passwords then
            local code=BuildingDoors.Password(not Config.Doors.requirePassword)
            if code==nil then state.pending=false; return end
            request.code=code
        end
        if state.cancelled or P.active~=state then return end
        local value=F.Call('place',request)
        if state.cancelled or P.active~=state then return end
        state.pending=false
        if type(value)~='table' then F.Reject('unavailable'); return end
        if not value.ok then
            F.Reject(value.reason)
            if value.reason=='expired' or value.reason=='missing_item' or value.reason=='inventory_unknown'
                or value.reason=='persistence' or value.reason=='unconfirmed' then P.Stop() end
            return
        end
        if value.record then B.Upsert(value.record) end
        P.HideGuides(state)
        if B.capacity then B.capacity.owner=math.max(0,B.capacity.owner-1); B.capacity.world=math.max(0,B.capacity.world-1) end
        PlaySoundFrontend(-1,'SELECT','HUD_FRONTEND_DEFAULT_SOUNDSET',true)
        if value.lease then state.lease=value.lease; state.valid=false; state.groundProbe=nil; state.groundResult=nil
        else P.Stop() end
    end)
end
P.Submit=submit

function P.Begin(lease)
    P.Stop()
    if not C.definitions[lease.definition] then return end
    if (not B.ready or B.bucket~=lease.bucket or B.epoch~=lease.epoch) and not B.Sync() then
        TriggerServerEvent('corex-building:server:cancel',lease.token); F.Notify('unavailable'); return
    end
    local def=C.definitions[lease.definition]
    local state={lease=lease,yaw=math.floor(GetEntityHeading(PlayerPedId())/Config.Placement.rotationStep+.5)*Config.Placement.rotationStep}
    P.active=state
    pcall(function() exports['corex-inventory']:CloseShop() end)
    pcall(function() exports['ox_inventory']:closeInventory() end)
    SetNuiFocus(false,false)
    state.hash=GetHashKey(def.model)
    local ok=pcall(lib.requestModel,state.hash,Config.Streaming.modelTimeout)
    if not ok or state.cancelled or P.active~=state then
        if P.active==state then P.Stop(); F.Notify('unavailable') end
        return
    end
    local p=GetEntityCoords(PlayerPedId())
    state.ghost=CreateObjectNoOffset(state.hash,p.x,p.y,p.z-100.0,false,false,false)
    if state.ghost==0 then P.Stop(); F.Notify('unavailable'); return end
    P.ConfigurePreview(state.ghost)
    SetEntityVisible(state.ghost,true,false); SetEntityLodDist(state.ghost,Config.Streaming.unloadDistance)
    SetEntityAlwaysPrerender(state.ghost,true)
    F.Ghost(state.ghost,false)
    CreateThread(function()
        while P.active==state and not state.cancelled do
            for _,control in ipairs(blockedControls) do DisableControlAction(0,control,true) end
            if IsEntityDead(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false) then P.Stop(); break end
            P.ProtectPlayer(state)
            local wheel=0
            if not state.pending then
                if IsDisabledControlJustPressed(0,14) or IsDisabledControlJustPressed(0,241) then wheel=1 end
                if IsDisabledControlJustPressed(0,15) or IsDisabledControlJustPressed(0,242) then wheel=-1 end
                if wheel~=0 then P.Rotate(state,wheel) end
            end
            local ray,point,camera=P.Raycast(state)
            if Config.Placement.validateTerrain or Config.Placement.checkWorldCollision then P.PollProbes(state) end
            if not state.pending then
                state.updateTime=GetGameTimer(); P.Update(state,ray,point,camera)
                P.UpdateGuides(state)
            end
            if IsDisabledControlJustPressed(0,25) or IsControlJustPressed(0,202) then P.Stop(); break end
            if not state.pending then
                if IsDisabledControlJustPressed(0,24) then submit(state) end
            end
            F.DrawFallback(def,state.visualPose or state.candidate,state.valid)
            P.DrawGuides(state)
            Wait(0)
        end
    end)
end

RegisterCommand(Config.Placement.freeCommand,function()
    local state=P.active
    if not state or state.pending or C.definitions[state.lease.definition].kind~='deck' then return end
    state.forceFree=not state.forceFree
    state.manual=nil; state.validation=nil; state.groundProbe=nil; state.groundResult=nil
end,false)
RegisterKeyMapping(Config.Placement.freeCommand,Config.Text.toggleFree,'keyboard',Config.Placement.freeKey)

RegisterNetEvent('corex-building:client:begin',function(lease)
    if source~=65535 or type(lease)~='table' then return end
    P.Begin(lease)
end)
