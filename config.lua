Config = {}
Config.Debug = false
Config.Locale = 'en'
Config.Items = { prefix = 'build_', stack = 20, weight = { wood = 2500, stone = 6000, steel = 5000 } }
Config.Tiers = {
    wood = { health = 500, next = 'stone' },
    stone = { health = 1500, next = 'steel' },
    steel = { health = 3000 }
}
Config.Placement = {
    freeCommand = 'buildingfree', freeKey = 'F9',
    validateTerrain = false, checkWorldCollision = false,
    distance = 6.0, snapRadius = 2.2, hysteresis = 0.28, cameraWeight = 0.45, rotationStep = 15,
    -- maxSlope is in degrees; groundTolerance limits roughness around the terrain plane and snapped ground gaps.
    maxSlope = 18, groundTolerance = 0.5, maxHeight = 30,
    -- Allow building in safe zones; set blockSafeZones=true to prohibit it.
    allowWater = false, blockSafeZones = false, allowForeignSupport = false,
    minFloorSupports = 1, maxUnsupportedDecks = 1, ownerLimit = 500, worldLimit = 5000,
    continuePlacing = true, leaseSeconds = 120, requestDelay = 500
}
Config.Guides = { enabled = true, count = 3, interval = 180, alpha = 40, releaseDistance = 1.0 }
Config.Preview = {
    alpha = 115, valid = { 112, 174, 145, 210 }, invalid = { 184, 100, 102, 210 },
    outline = true, nativeOutline = false, smoothing = 35, shake = 0.06, rejectSound = { 'ERROR', 'HUD_AMMO_SHOP_SOUNDSET' }
}
Config.Streaming = { distance = 180, unloadDistance = 200, interval = 1500, objectLimit = 400, modelTimeout = 5000 }
Config.Doors = {
    interactionCommand = 'buildingdoor', interactionKey = 'E', target = 'auto', scanInterval = 200,
    passwords = true, requirePassword = false, minLength = 4, maxLength = 16,
    ownerBypass = true, openAngle = 95, duration = 650, distance = 2.2,
    attempts = 5, lockoutSeconds = 60, requestDelay = 700, handleModel = 'prop_cs_ciggy_01'
}
Config.Management = { enabled = true, command = 'building', key = 'G', remove = true, upgrade = true }
Config.AdminKit = { command = 'buildkit', ace = 'corex.admin', count = 1, cooldown = 3000 }
Config.Database = { autoCreate = true }
Config.Network = { timeout = 15000 }
Config.DamageResources = { ['corex-zombies'] = true }
Config.DisabledPieces = {}
Config.CanPlace = nil
