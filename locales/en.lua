BuildingLocales = BuildingLocales or {}
BuildingLocales.en = {
    tiers = { wood = 'Wood', stone = 'Stone', steel = 'Steel' },
    labels = {
        foundation = 'Square Foundation', foundation_triangle = 'Triangle Foundation', floor = 'Square Floor', floor_triangle = 'Triangle Floor',
        wall = 'Wall', wall_half = 'Half Wall', wall_low = 'Low Wall', wall_door = 'Door Frame', wall_window = 'Window Wall',
        door = 'Door', shutter = 'Window Shutter', window_bars = 'Window Bars', roof_slope = 'Sloped Roof', roof_corner = 'Roof Corner',
        gable = 'Full Gable', gable_half = 'Half Gable', ridge = 'Roof Ridge', pillar = 'Pillar', beam = 'Beam',
        stairs = 'Stairs', ramp = 'Ramp', railing = 'Railing', fence = 'Fence', gate_frame = 'Gate Frame', gate = 'Gate',
        ladder = 'Ladder', hatch_frame = 'Hatch Floor', hatch = 'Hatch'
    },
    text = {
        place = '[Left click] Place', cancel = '[Right click / Esc] Cancel', rotate = '[Mouse wheel] Rotate',
        ready = 'Ready to place', magnetic = 'Snapped to support', pending = 'Placing...', placed = 'Placed',
        cycleAttachment = '[Mouse wheel] Choose attachment', freePlacement = '[%s] Change placement mode',
        toggleFree = 'Toggle free building placement', freeMode = 'Free placement', snapMode = 'Snap to structure',
        guides = 'Transparent pieces show available attachment positions',
        open = 'Open', close = 'Close', manage = 'Manage Building', password = 'Door Password',
        doorInteract = 'Open / close nearby building door',
        passwordHint = 'Leave blank for an unlocked door', setPassword = 'Change Password', clearPassword = 'Remove Password',
        upgrade = 'Upgrade', remove = 'Remove', removeConfirm = 'Remove this piece?',
        kitTitle = 'Building Test Kit', kitSummary = '%s kit x%d: %d/%d types provided.',
        kitGiven = 'Added this time: ', kitAlready = 'Already in your inventory: ', kitMissing = 'Remaining (capacity or inventory refusal): ',
        kitUnknown = 'Unconfirmed; check your inventory: ', kitDenied = 'This command is for admins only',
        kitComplete = 'All types provided. To refill missing items for a new test: /%s %s reset',
        kitUsage = 'Use /%s wood|stone|steel [count or reset]; count must be 1 to %d',
        reasons = {
            floor_required = 'Place a building floor or foundation first', ground_required = 'Aim at solid ground supporting the whole piece',
            ground_miss = 'No ground detected beneath one or more corners', ground_height = 'The ground is too far from this snapped foundation',
            aim_lost = 'Aim at a nearby building support',
            frame_required = 'This piece needs a matching frame', support_required = 'No compatible support',
            roof_required = 'Place a sloped roof first; this piece attaches at its ridge',
            wall_required = 'This piece attaches to a compatible wall top', pillar_required = 'This piece needs a supporting pillar',
            occupied = 'This position is already occupied', overlap = 'This piece overlaps another structure', obstructed = 'The space is obstructed',
            not_owner = 'You do not own this structure', wrong_bucket = 'This structure is in another world',
            too_far = 'Move closer to the placement', too_high = 'Maximum building height reached',
            slope = 'The ground is too steep or uneven', water = 'Building in water is disabled', checking = 'Checking placement...',
            checking_ground = 'Checking ground support...', checking_world = 'Checking space for obstacles...',
            probe_failed = 'The collision check failed. Move the piece and try again',
            safe_zone = 'Building inside a safe zone is disabled', limit = 'Building limit reached',
            invalid_position = 'Invalid placement', invalid_item = 'This building item is unavailable',
            preview_changed = 'The preview changed. Check its position and click again', aim_structure = 'Aim at a nearby structure you own',
            expired = 'Use the building item again', missing_item = 'You do not have the required item',
            busy = 'Wait for the current action to finish', unavailable = 'The building system is not ready',
            inventory_unknown = 'Item removal is unconfirmed; an admin must review the saved operation',
            persistence = 'Saving is unconfirmed; the operation is saved for admin review',
            password_invalid = 'Incorrect password or invalid password length', locked = 'This door requires a password',
            rate_limited = 'Wait before trying again', stale = 'The piece changed; try again',
            has_children = 'Remove attached pieces first', no_upgrade = 'This piece is already at the highest tier',
            blocked = 'Building here is not allowed', unconfirmed = 'Action unconfirmed; check the structure before retrying',
            kit_count = 'Keep the current kit quantity, or use reset to start a different quantity'
        }
    }
}
