BuildingCatalog = { definitions = {}, items = {} }
local catalog = assert(json.decode(LoadResourceFile('corex-building-assets', 'catalog.json')), 'Building asset catalog is missing')
local shapes = assert(json.decode(LoadResourceFile(GetCurrentResourceName(), 'data/collisions.json')), 'Building collision data is missing')
local kinds = {
    foundation = 'deck', foundation_triangle = 'deck', floor = 'deck', floor_triangle = 'deck', hatch_frame = 'deck',
    wall = 'wall', wall_half = 'wall', wall_low = 'wall', wall_door = 'wall', wall_window = 'wall', gate_frame = 'wall',
    door = 'insert', gate = 'insert', shutter = 'insert', window_bars = 'insert', hatch = 'insert',
    roof_slope = 'roof', roof_corner = 'roof', gable = 'gable', gable_half = 'gable', ridge = 'ridge',
    pillar = 'pillar', beam = 'beam', stairs = 'access', ramp = 'access', ladder = 'ladder', railing = 'edge', fence = 'edge'
}

for _, asset in ipairs(catalog.models) do
    if Config.Tiers[asset.tier] then
        local id = asset.tier .. '_' .. asset.piece
        local definition = {
            id = id, piece = asset.piece, tier = asset.tier, model = asset.model, kind = assert(kinds[asset.piece]),
            item = Config.Items.prefix .. id, label = Config.Labels[asset.piece] .. ' · ' .. Config.Tiers[asset.tier].label,
            bounds = asset.bounds, sockets = asset.snap_sockets, health = Config.Tiers[asset.tier].health,
            moving = asset.hinge_axis ~= nil, axis = asset.hinge_axis, triangle = asset.piece:find('triangle') ~= nil,
            collision = assert(shapes[asset.model])
        }
        BuildingCatalog.definitions[id] = definition
        BuildingCatalog.items[definition.item] = definition
    end
end

function BuildingCatalog.Get(record)
    return record and BuildingCatalog.definitions[record.definition]
end
