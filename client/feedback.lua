BuildingFeedback = {}
local F = BuildingFeedback

function F.Call(name,...)
    local p,done=promise.new(),false
    SetTimeout(Config.Network.timeout,function()
        if not done then done=true; p:resolve({ok=false,reason='unconfirmed'}) end
    end)
    local ok=pcall(lib.callback,'corex-building:'..name,false,function(value)
        if not done then done=true; p:resolve(type(value)=='table' and value or {ok=false,reason='unavailable'}) end
    end,...)
    if not ok and not done then done=true; p:resolve({ok=false,reason='unavailable'}) end
    return Citizen.Await(p)
end

function F.Notify(reason,kind)
    TriggerEvent('corex:notify',Config.Text.reasons[reason] or reason,kind or 'error')
end

function F.Reject(reason)
    if Config.Preview.rejectSound then PlaySoundFrontend(-1,Config.Preview.rejectSound[1],Config.Preview.rejectSound[2],true) end
    if Config.Preview.shake>0 then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE',Config.Preview.shake) end
    F.Notify(reason)
end

function F.Show(def,valid,reason,pending,snapped,guides,free)
    guides=guides or 0
    local signature=table.concat({def.id or def.label,tostring(valid),reason or '',tostring(pending),tostring(snapped),guides,tostring(free)},':')
    if signature==F.signature then return end
    F.signature=signature
    local status=pending and Config.Text.pending or (valid and Config.Text.ready or Config.Text.reasons[reason] or reason)
    local rotation=snapped and Config.Text.cycleAttachment or Config.Text.rotate
    local text=def.label..'\n'..status..'\n'..Config.Text.place..' · '..Config.Text.cancel..'\n'..rotation
    if def.kind=='deck' then
        text=text..'\n'..(free and Config.Text.freeMode or Config.Text.snapMode)..' · '..Config.Text.freePlacement:format(Config.Placement.freeKey)
    end
    if guides>0 then text=text..'\n'..Config.Text.guides end
    if text==F.last then return end
    F.last=text
    local color=valid and Config.Preview.valid or Config.Preview.invalid
    lib.showTextUI(text,{position='right-center',icon=valid and 'hammer' or 'ban',
        style={borderRadius=6,width=320,whiteSpace='pre-line',textAlign=Config.Locale=='ar' and 'right' or 'left',
            borderLeft='3px solid '..string.format('#%02x%02x%02x',table.unpack(color,1,3)),backgroundColor='#20272B',color='#E7E7E2'}})
end

function F.Hide()
    if not F.last then return end
    local open,text=lib.isTextUIOpen()
    if open and text==F.last then lib.hideTextUI() end
    F.last=nil
    F.signature=nil
end

function F.CleanupOldUI()
    local open,text=lib.isTextUIOpen()
    if not open or type(text)~='string' then return end
    for _,locale in pairs(BuildingLocales) do
        if text:find(locale.text.place,1,true) and text:find(locale.text.cancel,1,true) then lib.hideTextUI(); return end
    end
end

AddEventHandler('onClientResourceStart',function(name)
    if name==GetCurrentResourceName() then F.CleanupOldUI() end
end)

function F.Ghost(entity,valid)
    F.ghosts=F.ghosts or {}
    local cached=F.ghosts[entity]
    if cached and cached.valid==valid and cached.alpha==Config.Preview.alpha and cached.outline==Config.Preview.outline
        and cached.nativeOutline==Config.Preview.nativeOutline then return end
    F.ghosts[entity]={valid=valid,alpha=Config.Preview.alpha,outline=Config.Preview.outline,nativeOutline=Config.Preview.nativeOutline}
    SetEntityAlpha(entity,Config.Preview.alpha,false)
    if not Config.Preview.nativeOutline then F.outlineSupported=false; return end
    if Config.Preview.outline and F.outlineSupported~=false then
        F.outlineSupported=pcall(function()
            SetEntityDrawOutlineShader(1)
            SetEntityDrawOutlineColor(table.unpack(valid and Config.Preview.valid or Config.Preview.invalid))
            SetEntityDrawOutline(entity,true)
        end)
        F.ghosts[entity].nativeActive=F.outlineSupported
    end
end

function F.Forget(entity)
    if F.ghosts then F.ghosts[entity]=nil end
end

function F.DrawFallback(def,candidate,valid)
    if not candidate or not Config.Preview.outline or F.outlineSupported~=false then return end
    local vertices={}
    for i=0,7 do
        vertices[i+1]=BuildingGeometry.Offset(candidate,def.bounds[(i&1)==0 and 'min' or 'max'][1],
            def.bounds[(i&2)==0 and 'min' or 'max'][2],def.bounds[(i&4)==0 and 'min' or 'max'][3])
    end
    local color=valid and Config.Preview.valid or Config.Preview.invalid
    for i=0,7 do
        for _,bit in ipairs({1,2,4}) do
            if (i&bit)==0 then
                local a,b=vertices[i+1],vertices[(i|bit)+1]
                DrawLine(a.x,a.y,a.z,b.x,b.y,b.z,table.unpack(color))
            end
        end
    end
end
