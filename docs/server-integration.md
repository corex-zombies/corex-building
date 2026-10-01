# Server integration

[Installation and controls](../README.md)

## Admin items

`Config.AdminKit.ace` defaults to `corex.admin`. Only grant it to your server's administrators. It is separate from ordinary owner management through `/building`.

```text
/buildkit wood
/buildkit stone
/buildkit steel
/buildkit wood 2
/buildkit wood reset
/buildkit wood reset 2
```

The command fills missing types within inventory capacity. Repeating it continues the current material kit instead of replenishing types already delivered. Existing inventory counts contribute to the target quantity. `reset` starts another cycle without duplicating existing stock. Progress resets when the resource restarts. An unknown inventory mutation is not automatically retried.

The restricted server command can grant an individual piece:

```text
corex_build_give <playerId> <tier> <piece> <count>
corex_build_give 1 wood foundation 4
```

## Configuration hooks and exports

`Config.CanPlace(source, canonicalRecord)` provides an optional server-side placement policy. `Config.DamageResources` lists resources permitted to apply damage. Defaults permit `corex-zombies`.

```lua
local record = exports['corex-building']:GetStructure(id)
local applied = exports['corex-building']:DamageStructure(id, 40)
```

Public records exclude password hashes. Destructive damage removes the primary-support subtree; it does not redistribute structural loads. The resource does not expose a client event accepting arbitrary damage amounts.

The server checks the player session, persistent owner, routing bucket, placement distance, item lease, canonical support/socket transforms, occupancy and structure limits. Optional GTA terrain probes run on clients. Use a trusted server policy for additional location restrictions.

## Passwords

`Config.Doors.passwords = false` allows nearby active players to toggle doors without a password. Otherwise, passwords are optional unless `requirePassword = true`. With `ownerBypass = true`, owners bypass their own code.

Passwords use salted scrypt hashes in SQL. Length limits count Unicode characters, with a separate 256-byte input limit. Password hashes are excluded from client snapshots.

## Persistence and unconfirmed operations

The SQL tables are `corex_buildings` and `corex_build_operations`. Back up both with your server database. An operation journal precedes item removal; structure and operation changes share a SQL transaction. Confirmed persistence publishes the structure immediately.

When an external inventory mutation cannot be confirmed, the operation remains reserved for review. Inspect the actual inventory and database state before using the server-console recovery command:

```text
corex_build_recover <operationId> commit
corex_build_recover <operationId> discard
```

`commit` does not charge another item. `discard` does not refund one. Already committed database records are reconciled. Do not commit an operation without confirming that its payment succeeded.

## Updating

Preserve your configuration and database, replace the resource files, and merge any new settings into your configuration. Keep `corex-building` and `corex-building-assets` together. If streamed model files change, clients should start a fresh FiveM process. No npm or Python build step is required.
