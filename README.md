# COREX Building

Modular survival building for the [COREX framework](https://github.com/corex-zombies).
28 pieces in wood, stone and steel: **84 usable items and matching models**.

[العربية](docs/README.ar.md) · [Building assets](https://github.com/corex-zombies/corex-building-assets) · [Complete installation package](https://github.com/corex-zombies/corex-building/releases/latest)

## Features

- Camera placement, magnetic attachment points and transparent placement guides.
- Native model collisions, structural supports and occupied-socket checks.
- Persistent buildings, ownership, material upgrades and removal.
- Password-protected doors with animated opening and closing.
- Keyboard interaction and optional `ox_target` integration.
- English and Arabic labels, prompts and menus.
- COREX inventory capabilities and content-pack registration.

## Requirements

An installed COREX server with OneSync enabled and these resources running:

- [corex-core](https://github.com/corex-zombies/corex-core)
- [corex-capabilities](https://github.com/corex-zombies/corex-capabilities)
- [corex-content](https://github.com/corex-zombies/corex-content)
- `ox_lib`, `oxmysql`, and a configured COREX-compatible inventory provider
- [corex-building-assets](https://github.com/corex-zombies/corex-building-assets)

`ox_target` is optional; doors also work with the keyboard interaction.

## Installation

1. Download the complete ZIP from [Releases](https://github.com/corex-zombies/corex-building/releases/latest), or download both repositories.
2. Place `corex-building` in `resources/[corex]/` and `corex-building-assets` in `resources/[assets]/`. Keep these resource names unchanged; remove GitHub's `-main` suffix when extracting source downloads.
3. For `corex-inventory`, copy the 84 PNGs from `corex-building/icons/` to `corex-inventory/html/images/`. The complete package includes these icon copies in that destination. For an external inventory, use its image folder and the definitions described below.
4. Start both resources after the framework, inventory provider, `ox_lib` and `oxmysql`:

```cfg
ensure corex-building-assets
ensure corex-building
```

5. Review `config.lua`. The default language is English; use `Config.Locale = 'ar'` for Arabic.

With `Config.Database.autoCreate = true`, the resource creates its two SQL tables automatically through oxmysql. For manual setup, import `sql/corex_building.sql` and disable auto-creation. Startup reports `Ready: 84 usable building items` when registration is complete.

COREX Content registers items as `build_<tier>_<piece>`, for example `build_wood_foundation` and `build_steel_door`. External inventories with static catalogs may need the server-console output from:

```text
corex_content_snippet corex-building ox_inventory
```

Recipes, shops and loot are configured in your existing resources. This package does not replace them.

## Controls

| Input | Action |
| --- | --- |
| Use a building item | Start its transparent preview |
| Left mouse button | Place the displayed piece |
| Right mouse button / Escape | Cancel |
| Mouse wheel | Rotate freely or cycle compatible attachment positions |
| F9 / `/buildingfree` | Toggle free deck placement |
| E / `/buildingdoor` | Open or close the nearby door |
| G / `/building` | Manage the nearby owned piece |

Keys and command names are configurable. Shift remains sprint. Placement guides indicate compatible attachment positions; the preview explains rejected placements.

The `/building` command is available to building owners, without admin permissions. Owners can upgrade their pieces, remove eligible pieces and change door passwords. Upgrades consume the next material tier's item. Removal refuses to leave attached children unsupported. Doors require the matching frame; upper floors and roofs require appropriate supports.

Owners bypass their own door password by default. Other players enter the password through `ox_lib`. Passwords are stored as salted scrypt hashes. The optional target menu attaches to the visible door, and opening and closing animate around its hinge.

## Configuration

`config.lua` contains placement distances, support limits, streaming ranges, door settings, item weights, health values, language, guides and management controls.

The shipped settings allow building in safe zones and disable optional terrain-flatness and world-obstruction validation (`blockSafeZones`, `validateTerrain`, `checkWorldCollision` are `false`). Structural support, ownership, occupancy and item validation remain active. Review these settings for your server rules.

`Config.DisabledPieces` prevents new placement of selected pieces while preserving saved structures. `Config.Streaming` limits locally rendered structures. Keep `unloadDistance` above `distance`.

Ladders include placement geometry; a custom climbing system is not included. New zombie raid AI is not included. After updating streamed model assets, reconnect from a fresh FiveM process to load the new models.

## Administration and integration

[Server integration](docs/server-integration.md) documents admin kits, exports, damage authorization and recovery of unconfirmed operations.

## Layout

```text
client/       Placement, previews, doors and interaction
server/       Persistence, inventory transactions and password hashing
shared/       Catalog, geometry and localization helpers
locales/      English and Arabic text
data/         Placement collision geometry
icons/        84 inventory icons
sql/          Database schema
docs/         Arabic guide and server integration
config.lua    Server settings
fxmanifest.lua
```

`server/passwords.js` and `data/collisions.json` are required runtime files. Native model files and their shared textures are supplied by the separate assets resource. No build tools, Python installation or dependency installation step is needed for these two resources.

## License

[MIT](LICENSE). Texture credits are included in the [assets repository](https://github.com/corex-zombies/corex-building-assets/blob/main/CREDITS.md).
