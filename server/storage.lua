BuildingStorage = {}
local S = BuildingStorage

local function payload(record)
    local copy = {}
    for key, value in pairs(record) do
        if key ~= 'passwordHash' and key ~= 'aim' then copy[key] = value end
    end
    return json.encode(copy)
end

local function decode(row)
    if not row then return nil end
    local record = json.decode(row.payload)
    record.passwordHash = row.password_hash ~= '' and row.password_hash or nil
    record.revision = tonumber(row.revision)
    return record
end

function S.Init()
    if Config.Database.autoCreate then
        local sql = assert(LoadResourceFile(GetCurrentResourceName(), 'sql/corex_building.sql'))
        for statement in sql:gmatch('([^;]+);') do MySQL.query.await(statement) end
    end
    return true
end

function S.Load()
    local records, pending = {}, {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM corex_buildings')) do
        local record = decode(row)
        records[record.id] = record
    end
    for _, row in ipairs(MySQL.query.await("SELECT payload FROM corex_build_operations WHERE status IN ('prepared', 'review')")) do
        local op = json.decode(row.payload)
        pending[op.id] = op
    end
    return records, pending
end

function S.Get(id)
    return decode(MySQL.single.await('SELECT * FROM corex_buildings WHERE id = ?', { id }))
end

function S.Prepare(operation)
    return MySQL.insert.await('INSERT INTO corex_build_operations (id, status, payload) VALUES (?, ?, ?)',
        {operation.id, 'prepared', json.encode(operation)}) ~= nil
end

function S.Review(id)
    MySQL.update.await("UPDATE corex_build_operations SET status = 'review' WHERE id = ? AND status = 'prepared'", {id})
end

local function same(a, b)
    if not a or a.id ~= b.id or a.revision ~= b.revision then return false end
    -- FiveM's dkjson encodes numbers through tostring, which does not preserve
    -- every binary float digit. Confirm against exactly the JSON we wrote,
    -- not against the higher-precision in-memory placement calculation.
    local expected=json.decode(payload(b))
    expected.passwordHash=b.passwordHash
    for _, key in ipairs({'definition','owner','bucket','x','y','z','yaw','parent','socket','health','open','grounded','passwordHash'}) do
        if a[key] ~= expected[key] then return false end
    end
    return true
end
S.Matches=same

function S.Commit(operation)
    local record = operation.record
    local statements
    if operation.kind == 'place' then
        statements = {{query='INSERT INTO corex_buildings (id, owner, bucket, payload, password_hash, revision) VALUES (?, ?, ?, ?, ?, ?)',
            values={record.id, record.owner, record.bucket, payload(record), record.passwordHash or '', record.revision}}}
    else
        statements = {{query='UPDATE corex_buildings SET payload = ?, password_hash = ?, revision = ? WHERE id = ? AND revision = ?',
            values={payload(record), record.passwordHash or '', record.revision, record.id, operation.expected}}}
    end
    statements[#statements+1] = {query="UPDATE corex_build_operations SET status = 'applied' WHERE id = ? AND EXISTS (SELECT 1 FROM corex_buildings WHERE id = ? AND revision = ?)",
        values={operation.id,record.id,record.revision}}
    pcall(MySQL.transaction.await, statements)
    local read, current = pcall(S.Get, record.id)
    return read and same(current,record), current
end

function S.Update(record, previous)
    local ok, changed = pcall(MySQL.update.await,
        'UPDATE corex_buildings SET payload = ?, password_hash = ?, revision = ? WHERE id = ? AND revision = ?',
        {payload(record),record.passwordHash or '',record.revision,record.id,previous})
    if ok and changed == 1 then return true end
    local read, current = pcall(S.Get,record.id)
    return read and same(current,record)
end

function S.Delete(ids)
    local statements = {}
    for _, id in ipairs(ids) do statements[#statements+1] = {query='DELETE FROM corex_buildings WHERE id = ?',values={id}} end
    return MySQL.transaction.await(statements) == true
end

function S.Discard(id)
    return MySQL.update.await("UPDATE corex_build_operations SET status = 'discarded' WHERE id = ? AND status IN ('prepared', 'review')",{id}) == 1
end

function S.MarkApplied(id)
    MySQL.update.await("UPDATE corex_build_operations SET status = 'applied' WHERE id = ?",{id})
end
