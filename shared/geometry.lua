BuildingGeometry = {}
local G, C = BuildingGeometry, BuildingCatalog
local rad, abs = math.rad, math.abs
local compiled = {}
local transformedCache=setmetatable({}, {__mode='k'})

local function cross(a,b)
    return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]}
end

local function subtract(a,b)
    return {a[1]-b[1],a[2]-b[2],a[3]-b[3]}
end

local function direction(list,vector)
    local length=math.sqrt(vector[1]^2+vector[2]^2+vector[3]^2)
    if length<.000001 then return end
    local axis={vector[1]/length,vector[2]/length,vector[3]/length}
    for _,other in ipairs(list) do if abs(axis[1]*other[1]+axis[2]*other[2]+axis[3]*other[3])>.99999 then return end end
    list[#list+1]=axis
end

local function parts(record)
    local def=C.Get(record)
    local cached=transformedCache[record]
    if cached and cached.definition==record.definition and cached.x==record.x and cached.y==record.y
        and cached.z==record.z and cached.yaw==record.yaw then return cached.parts end
    if not compiled[def.id] then
        local components={}
        for _,shape in ipairs(def.collision) do
            local component={vertices=shape.vertices,normals={},edges={}}
            for _,face in ipairs(shape.faces) do
                local a,b,c=shape.vertices[face[1]+1],shape.vertices[face[2]+1],shape.vertices[face[3]+1]
                direction(component.normals,cross(subtract(b,a),subtract(c,a)))
                for i,index in ipairs(face) do
                    direction(component.edges,subtract(shape.vertices[face[i%#face+1]+1],shape.vertices[index+1]))
                end
            end
            components[#components+1]=component
        end
        compiled[def.id]=components
    end
    local transformed={}
    local cosine,sine=math.cos(rad(record.yaw)),math.sin(rad(record.yaw))
    local function rotate(v) return {v[1]*cosine-v[2]*sine,v[1]*sine+v[2]*cosine,v[3]} end
    for _,component in ipairs(compiled[def.id]) do
        local value={vertices={},normals={},edges={}}
        for _,v in ipairs(component.vertices) do local p=G.Offset(record,table.unpack(v)); value.vertices[#value.vertices+1]={p.x,p.y,p.z} end
        for _,v in ipairs(component.normals) do value.normals[#value.normals+1]=rotate(v) end
        for _,v in ipairs(component.edges) do value.edges[#value.edges+1]=rotate(v) end
        transformed[#transformed+1]=value
    end
    transformedCache[record]={definition=record.definition,x=record.x,y=record.y,z=record.z,yaw=record.yaw,parts=transformed}
    return transformed
end

function G.SolidOverlap(a,b)
    local ap,bp=parts(a),parts(b)
    for _,aa in ipairs(ap) do
        for _,bb in ipairs(bp) do
            local axes={}
            for _,n in ipairs(aa.normals) do direction(axes,n) end
            for _,n in ipairs(bb.normals) do direction(axes,n) end
            for _,ae in ipairs(aa.edges) do for _,be in ipairs(bb.edges) do direction(axes,cross(ae,be)) end end
            local overlapping=true
            for _,axis in ipairs(axes) do
                local function project(vertices)
                    local lo,hi=math.huge,-math.huge
                    for _,p in ipairs(vertices) do
                        local n=p[1]*axis[1]+p[2]*axis[2]+p[3]*axis[3]
                        lo,hi=math.min(lo,n),math.max(hi,n)
                    end
                    return lo,hi
                end
                local amin,amax=project(aa.vertices); local bmin,bmax=project(bb.vertices)
                if math.min(amax,bmax)-math.max(amin,bmin)<.01 then overlapping=false; break end
            end
            if overlapping then return true end
        end
    end
    return false
end

function G.Number(value)
    return type(value) == 'number' and value == value and abs(value) < 20000
end

function G.Position(value)
    return type(value) == 'table' and G.Number(value.x) and G.Number(value.y) and G.Number(value.z)
end

function G.Distance(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end

function G.MatchesPreview(candidate,preview)
    return G.Position(preview) and G.Number(preview.yaw) and G.Distance(candidate,preview)<=.01
        and abs((candidate.yaw-preview.yaw+180)%360-180)<=.1
end

function G.CameraDirection(rotation)
    local pitch,yaw=rad(rotation.x),rad(rotation.z)
    return {x=-math.sin(yaw)*math.cos(pitch),y=math.cos(yaw)*math.cos(pitch),z=math.sin(pitch)}
end

function G.BoundsDistance(record,point)
    local def=C.Get(record); local angle=rad(record.yaw)
    local dx,dy=point.x-record.x,point.y-record.y
    local localPoint={dx*math.cos(angle)+dy*math.sin(angle),-dx*math.sin(angle)+dy*math.cos(angle),point.z-record.z}
    local distance=0
    for i=1,3 do
        local closest=math.max(def.bounds.min[i],math.min(def.bounds.max[i],localPoint[i]))
        distance=distance+(localPoint[i]-closest)^2
    end
    return math.sqrt(distance)
end

function G.Handle(record)
    local def=C.Get(record)
    local x,y,z=def.bounds.max[1]-.13,-.10,def.axis=='Y' and .08 or def.bounds.max[3]*.5
    local yaw=record.yaw
    if record.open then
        if def.axis=='Z' then yaw=yaw-Config.Doors.openAngle
        else
            local angle=rad(-Config.Doors.openAngle)
            x,z=x*math.cos(angle)+z*math.sin(angle),-x*math.sin(angle)+z*math.cos(angle)
        end
    end
    return G.Offset({x=record.x,y=record.y,z=record.z,yaw=yaw},x,y,z)
end

function G.Offset(record, x, y, z)
    local angle = rad(record.yaw)
    return { x = record.x + x*math.cos(angle)-y*math.sin(angle),
        y = record.y + x*math.sin(angle)+y*math.cos(angle), z = record.z + z }
end

local function quantize(value)
    return math.floor(value * 100 + 0.5)
end

function G.Key(record)
    local def = C.Get(record)
    if def.kind == 'insert' then return 'insert:' .. tostring(record.parent) end
    local period = def.kind == 'deck' and (def.triangle and 120 or 90) or 180
    return table.concat({def.kind == 'edge' and 'wall' or def.kind, record.bucket or 0,
        quantize(record.x), quantize(record.y), quantize(record.z), quantize(record.yaw % period)}, ':')
end

function G.WallEnds(record)
    return G.Offset(record,-1.5,0,0), G.Offset(record,1.5,0,0)
end

function G.Edges(record)
    local edges = {}
    for _, socket in ipairs(C.Get(record).sockets) do
        if socket.kind == 'module_edge' then
            local p = socket.position
            edges[#edges+1] = { name = socket.name, localPosition = p,
                position = G.Offset(record,p[1],p[2],p[3]),
                yaw = (record.yaw + math.deg(math.atan(p[1],-p[2]))) % 360 }
        end
    end
    return edges
end

function G.Corners(record)
    if C.Get(record).triangle then return {{-1.5,-math.sqrt(3)/2},{1.5,-math.sqrt(3)/2},{0,math.sqrt(3)}} end
    return {{-1.5,-1.5},{1.5,-1.5},{1.5,1.5},{-1.5,1.5}}
end

local function edge(record, name)
    for _, value in ipairs(G.Edges(record)) do if value.name == name then return value end end
end

local function height(record)
    return C.Get(record).bounds.max[3]
end

local function attached(def, parent, socket, position, yaw)
    return { definition = def.id, parent = parent.id, socket = socket,
        x = position.x, y = position.y, z = position.z, yaw = (yaw or parent.yaw) % 360,
        bucket = parent.bucket or 0, aim = position }
end

function G.SupportReason(def)
    if def.kind=='insert' then return 'frame_required' end
    if def.kind=='ridge' then return 'roof_required' end
    if def.kind=='roof' or def.kind=='gable' then return 'wall_required' end
    if def.kind=='beam' then return 'pillar_required' end
    return 'floor_required'
end

function G.Resolve(def, request, records)
    if not def or type(request) ~= 'table' then return nil, 'invalid_item' end
    if not request.parent then
        if def.kind ~= 'deck' then return nil, G.SupportReason(def) end
        if not G.Position(request) or not G.Number(request.yaw) then return nil, 'invalid_position' end
        if request.ground ~= true then return nil, 'ground_required' end
        return { definition = def.id, x = request.x, y = request.y, z = request.z,
            yaw = request.yaw % 360, bucket = request.bucket or 0, ground = true, grounded = true }
    end
    local parent = records[request.parent]
    local pd = C.Get(parent)
    if not parent or not pd or type(request.socket) ~= 'string' then return nil, 'support_required' end
    local socket = request.socket
    if def.kind == 'insert' then
        local expected = ({door='wall_door',gate='gate_frame',shutter='wall_window',window_bars='wall_window',hatch='hatch_frame'})[def.piece]
        local name = ({shutter='shutter_hinge',window_bars='bars',hatch='hatch_hinge'})[def.piece] or 'hinge'
        if pd.piece ~= expected or socket ~= name then return nil, 'frame_required' end
        for _, value in ipairs(pd.sockets) do
            if value.name == name then
                local p = value.position
                return attached(def,parent,socket,G.Offset(parent,p[1],p[2],p[3]))
            end
        end
    elseif pd.kind == 'deck' then
        if def.kind == 'deck' then
            local parentEdge, ownEdge = socket:match('^([^~]+)~([^~]+)$')
            local pe = parentEdge and edge(parent,parentEdge)
            local prototype = {definition=def.id,x=0,y=0,z=0,yaw=0}
            local oe = ownEdge and edge(prototype,ownEdge)
            if pe and oe then
                local yaw = (pe.yaw + 180 - oe.yaw) % 360
                local offset = G.Offset({x=0,y=0,z=0,yaw=yaw},table.unpack(oe.localPosition))
                local position = {x=pe.position.x-offset.x,y=pe.position.y-offset.y,z=parent.z}
                local value=attached(def,parent,socket,position,yaw); value.aim=pe.position
                return value
            end
        elseif def.kind == 'pillar' then
            local x,y = socket:match('^corner:([%-0-9%.]+):([%-0-9%.]+)$')
            x,y = tonumber(x),tonumber(y)
            if x and y then
                for _,corner in ipairs(G.Corners(parent)) do
                    if abs(corner[1]-x)<1e-8 and abs(corner[2]-y)<1e-8 then
                        return attached(def,parent,socket,G.Offset(parent,corner[1],corner[2],0))
                    end
                end
            end
        else
            local pe=edge(parent,socket)
            if pe and (def.kind=='wall' or def.kind=='edge' or def.kind=='access' or def.kind=='ladder') then
                local value=attached(def,parent,socket,pe.position,pe.yaw)
                value.aim=pe.position
                if def.kind=='access' then
                    local pos=G.Offset(value,0,1.5,0); value.x,value.y=pos.x,pos.y
                elseif def.kind=='ladder' then
                    local pos=G.Offset(value,0,-.25,0); value.x,value.y=pos.x,pos.y
                end
                return value
            end
        end
    elseif pd.kind == 'wall' or pd.kind == 'beam' then
        local top=G.Offset(parent,0,0,height(parent))
        if def.piece=='gable' and (socket=='gable_left' or socket=='gable_right') then
            return attached(def,parent,socket,G.Offset(parent,socket=='gable_left' and -1.5 or 1.5,0,height(parent)))
        elseif socket=='top' and (def.kind=='wall' or def.kind=='edge' or def.piece=='gable_half') then
            return attached(def,parent,socket,top)
        elseif def.kind=='deck' and (socket=='cap_in' or socket=='cap_out') and not def.triangle then
            local position=G.Offset(parent,0,socket=='cap_in' and 1.5 or -1.5,height(parent))
            local value=attached(def,parent,socket,position); value.aim=top
            return value
        elseif socket=='top' and def.kind=='roof' then
            local value=attached(def,parent,socket,top)
            local pos=G.Offset(value,0,1.5,0); value.x,value.y=pos.x,pos.y; value.aim=top
            return value
        end
    elseif pd.kind=='roof' then
        if socket=='high' and (def.piece=='roof_slope' or def.kind=='ridge') then
            local top=G.Offset(parent,0,1.5,1.5)
            local value=attached(def,parent,socket,top,def.kind=='ridge' and parent.yaw or parent.yaw+180)
            if def.kind=='roof' then
                local pos=G.Offset(value,0,-1.5,-1.5); value.x,value.y,value.z=pos.x,pos.y,pos.z
            end
            value.aim=top
            return value
        end
    elseif pd.kind=='pillar' and def.kind=='beam' and (socket=='beam_left' or socket=='beam_right') then
        local pos=G.Offset(parent,socket=='beam_left' and -1.5 or 1.5,0,3-def.bounds.max[3])
        local value=attached(def,parent,socket,pos); value.aim=G.Offset(parent,0,0,3)
        return value
    elseif pd.kind=='access' and def.kind=='deck' and not def.triangle and socket=='landing' then
        local value=attached(def,parent,socket,G.Offset(parent,0,3,3))
        value.aim=G.Offset(parent,0,1.5,3)
        return value
    end
    return nil, def.kind=='insert' and 'frame_required' or 'support_required'
end

local function box(record)
    local def=C.Get(record)
    local lo,hi=def.bounds.min,def.bounds.max
    local halfX,halfY=(hi[1]-lo[1])/2,(hi[2]-lo[2])/2
    if def.kind=='deck' and not def.triangle then halfX,halfY=1.5,1.5 end
    if def.kind=='wall' or def.kind=='edge' then halfX=1.5 end
    if def.kind=='roof' or def.kind=='access' then halfY=1.5 end
    local center=G.Offset(record,(lo[1]+hi[1])/2,(lo[2]+hi[2])/2,0)
    local angle=rad(record.yaw)
    return {x=center.x,y=center.y,hx=halfX,hy=halfY,
        axes={{math.cos(angle),math.sin(angle)},{-math.sin(angle),math.cos(angle)}},
        zmin=record.z+lo[3],zmax=record.z+hi[3],record=record}
end

function G.Overlap(a,b)
    local aa,bb=box(a),box(b)
    if math.min(aa.zmax,bb.zmax)-math.max(aa.zmin,bb.zmin)<.025 then return false end
    local function polygon(record,v)
        if C.Get(record).kind=='deck' and C.Get(record).triangle then
            return {G.Offset(record,-1.5,-math.sqrt(3)/2,0),G.Offset(record,1.5,-math.sqrt(3)/2,0),G.Offset(record,0,math.sqrt(3),0)}
        end
        local result={}
        for _,corner in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}}) do
            result[#result+1]={x=v.x+v.axes[1][1]*v.hx*corner[1]+v.axes[2][1]*v.hy*corner[2],
                y=v.y+v.axes[1][2]*v.hx*corner[1]+v.axes[2][2]*v.hy*corner[2]}
        end
        return result
    end
    local pa,pb=polygon(a,aa),polygon(b,bb)
    for _,poly in ipairs({pa,pb}) do
        for i,point in ipairs(poly) do
            local nextPoint=poly[i%#poly+1]
            local nx,ny=-(nextPoint.y-point.y),nextPoint.x-point.x
            local length=math.sqrt(nx*nx+ny*ny); nx,ny=nx/length,ny/length
            local function project(points)
                local lo,hi=math.huge,-math.huge
                for _,p in ipairs(points) do local n=p.x*nx+p.y*ny; lo=math.min(lo,n); hi=math.max(hi,n) end
                return lo,hi
            end
            local amin,amax=project(pa); local bmin,bmax=project(pb)
            if math.min(amax,bmax)-math.max(amin,bmin)<.045 then return false end
        end
    end
    return true
end

local function ancestors(record,records)
    local result, count={},0
    while record and record.parent do
        count=count+1
        if count>64 or result[record.parent] then return nil end
        result[record.parent]=true; record=records[record.parent]
    end
    return result,record
end

local function seam(a,b)
    local ad,bd=C.Get(a),C.Get(b)
    if (ad.kind=='wall' or ad.kind=='edge') and (bd.kind=='wall' or bd.kind=='edge') and abs(a.z-b.z)<.025 then
        local a1,a2=G.WallEnds(a); local b1,b2=G.WallEnds(b)
        return math.min(G.Distance(a1,b1),G.Distance(a1,b2),G.Distance(a2,b1),G.Distance(a2,b2))<.045
    end
    local function floorCap(deck,wall)
        local dk=C.Get(deck).kind
        if dk~='deck' and dk~='gable' then return false end
        if C.Get(wall).kind~='wall' and C.Get(wall).kind~='beam' then return false end
        if abs(deck.z-wall.z-height(wall))>.025 then return false end
        if dk=='gable' then return abs((deck.yaw-wall.yaw)%180)<.025 end
        for _, e in ipairs(G.Edges(deck)) do
            if G.Distance(e.position,G.Offset(wall,0,0,height(wall)))<.045 then return true end
        end
        return false
    end
    if floorCap(a,b) or floorCap(b,a) then return true end
    local function postCap(deck,post)
        return C.Get(deck).kind=='deck' and C.Get(post).kind=='pillar' and abs(deck.z-post.z-height(post))<.025
    end
    if postCap(a,b) or postCap(b,a) then return true end
    local function postJoin(post,wall)
        if C.Get(post).kind~='pillar' then return false end
        if C.Get(wall).kind=='beam' then
            local top=G.Offset(post,0,0,3)
            return math.min(G.Distance(top,G.Offset(wall,-1.5,0,height(wall))),G.Distance(top,G.Offset(wall,1.5,0,height(wall))))<.045
        end
        if C.Get(wall).kind~='wall' and C.Get(wall).kind~='edge' then return false end
        local p1,p2=G.WallEnds(wall)
        return abs(post.z-wall.z)<.025 and math.min(G.Distance(post,p1),G.Distance(post,p2))<.045
    end
    return postJoin(a,b) or postJoin(b,a)
end

function G.Validate(candidate,records,owner)
    local def=C.Get(candidate)
    if not def then return false,'invalid_item' end
    local lineage,root=ancestors(candidate,records)
    if not lineage then return false,'support_required' end
    if candidate.parent then
        local parent=records[candidate.parent]
        if not parent then return false,'support_required' end
        if parent.busy or parent.reserved then return false,'busy' end
        if (parent.bucket or 0)~=(candidate.bucket or 0) then return false,'wrong_bucket' end
        if not Config.Placement.allowForeignSupport and parent.owner~=owner then return false,'not_owner' end
    end
    if root and candidate.z+def.bounds.max[3]-root.z>Config.Placement.maxHeight then return false,'too_high' end
    if def.kind=='deck' and not candidate.grounded and candidate.parent then
        local unsupported,ancestor=1,records[candidate.parent]
        while ancestor and C.Get(ancestor).kind=='deck' do
            if ancestor.grounded or C.Get(ancestor).piece:find('foundation') then break end
            unsupported=unsupported+1; ancestor=records[ancestor.parent]
        end
        if unsupported>Config.Placement.maxUnsupportedDecks then return false,'support_required' end
    end
    local key=G.Key(candidate)
    for id,other in pairs(records) do
        if id~=candidate.id and (other.bucket or 0)==(candidate.bucket or 0) then
            if G.Key(other)==key then return false,'occupied' end
            if not lineage[id] and not seam(candidate,other) and G.Overlap(candidate,other) and G.SolidOverlap(candidate,other) then return false,'overlap' end
        end
    end
    if def.kind=='deck' and candidate.parent and C.Get(records[candidate.parent]).kind=='wall' then
        local count=0
        for _,other in pairs(records) do
            if C.Get(other).kind=='wall' and (other.bucket or 0)==(candidate.bucket or 0)
                and (Config.Placement.allowForeignSupport or other.owner==owner)
                and abs(other.z+height(other)-candidate.z)<.025 then
                for _,e in ipairs(G.Edges(candidate)) do
                    if G.Distance(e.position,G.Offset(other,0,0,height(other)))<.045 then count=count+1; break end
                end
            end
        end
        if count<Config.Placement.minFloorSupports then return false,'support_required' end
    end
    if def.piece=='gable' then
        for _,x in ipairs({-1.5,1.5}) do
            local position,found=G.Offset(candidate,x,0,0),false
            for _,other in pairs(records) do
                if C.Get(other).kind=='wall' and (other.bucket or 0)==(candidate.bucket or 0)
                    and (Config.Placement.allowForeignSupport or other.owner==owner)
                    and G.Distance(position,G.Offset(other,0,0,height(other)))<.045 then found=true; break end
            end
            if not found then return false,'support_required' end
        end
    end
    return true
end

function G.Candidates(def,records,point,radius)
    local result={}
    for id,parent in pairs(records) do
        if not parent.reserved and G.Distance(parent,point)<(radius or Config.Placement.distance+7) then
            local pd=C.Get(parent)
            local sockets={}
            if pd.kind=='deck' then
                if def.kind=='deck' then
                    for _,pe in ipairs(G.Edges(parent)) do
                        for _,oe in ipairs(G.Edges({definition=def.id,x=0,y=0,z=0,yaw=0})) do
                            sockets[#sockets+1]=pe.name..'~'..oe.name
                        end
                    end
                elseif def.kind=='pillar' then
                    for _,corner in ipairs(G.Corners(parent)) do sockets[#sockets+1]='corner:'..corner[1]..':'..corner[2] end
                elseif def.piece=='hatch' then sockets={'hatch_hinge'}
                elseif def.kind=='wall' or def.kind=='edge' or def.kind=='access' or def.kind=='ladder' then
                    for _,pe in ipairs(G.Edges(parent)) do sockets[#sockets+1]=pe.name end
                end
            elseif pd.kind=='wall' or pd.kind=='beam' then
                if def.piece=='gable' then sockets={'gable_left','gable_right'}
                elseif def.kind=='wall' or def.kind=='edge' or def.piece=='gable_half' or def.kind=='roof' then sockets={'top'}
                elseif def.kind=='deck' and not def.triangle then sockets={'cap_in','cap_out'}
                elseif def.kind=='insert' then
                    local socket=({door='hinge',gate='hinge',shutter='shutter_hinge',window_bars='bars'})[def.piece]
                    if socket then sockets={socket} end
                end
            elseif pd.kind=='roof' and (def.piece=='roof_slope' or def.kind=='ridge') then sockets={'high'}
            elseif pd.kind=='pillar' and def.kind=='beam' then sockets={'beam_left','beam_right'}
            elseif pd.kind=='access' and def.kind=='deck' and not def.triangle then sockets={'landing'} end
            for _,socket in ipairs(sockets) do
                local value=G.Resolve(def,{parent=id,socket=socket},records)
                if value then result[#result+1]=value end
            end
        end
    end
    return result
end

function G.Descendants(id,records)
    local result,queue,seen={},{id},{[id]=true}
    local index=1
    while queue[index] do
        for child,record in pairs(records) do
            if record.parent==queue[index] and not seen[child] then
                result[#result+1]=child; queue[#queue+1]=child; seen[child]=true
            end
        end
        index=index+1
    end
    return result
end
