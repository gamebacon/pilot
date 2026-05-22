v5

# Pilot — Claude Code Context

## What this is

3D multiplayer survival tower-defence. Players share an island, harvest resources, craft gear, build forts, and survive nightly enemy waves. Goal: escape the island.

Engine: Godot 4.6, Forward+, Jolt Physics. Steam multiplayer via GodotSteam + `SteamMultiplayerPeer`.

---

## GDScript coding conventions

### Typing — always explicit, no exceptions

Every variable, parameter, and function must carry a type. GDScript's type inference (`:=`) is allowed only when the right-hand side is a constructor call or a literal whose type is unambiguous. For all function calls use an explicit annotation. Typed collections must include their element type: `Array[String]`, `Array[Dictionary]`, not bare `Array`.

```gdscript
# ✅ correct
var speed: float = 5.0
var slot: Inventory.Slot = inventory.get_slot(idx)
var taken: Inventory.DragStack = inventory.take_items(idx, qty)
func get_display_name() -> String: ...
func find_player(id: int) -> Player: ...
func try_pickup(item: PhysicalItem) -> bool: ...

# ❌ wrong — type unknown to the compiler and to the reader
var slot := inventory.get_slot(idx)
var taken := inventory.take_items(idx, qty)
func get_display_name(): ...
```

`:=` is fine for literals and `new()`:

```gdscript
var count   := 0                     # int literal — OK
var label   := Label.new()           # constructor — OK
var drag    := Inventory.DragStack.new() # constructor — OK
```

Every function parameter must also be typed, including inner-class methods and lambdas:

```gdscript
# ✅
func _fill(target: Inventory, stack: Inventory.DragStack) -> Inventory.DragStack:

# ❌
func _fill(target, stack):
```

### No magic numbers

Every numeric constant that has a meaning must be named. Define constants at the top of the file or in a relevant class/autoload.

```gdscript
# ✅
const SNAP_DISTANCE:      float = 0.3
const MAX_CARRY_MASS:     float = 30.0
const ENEMY_BASE_CAP:     int   = 3
const SPAWN_INTERVAL_MIN: float = 1.2

if distance < SNAP_DISTANCE: ...

# ❌
if distance < 0.3: ...
enemies_alive_cap = 3 + (wave - 1) * 2
```

### Function naming

Function names must communicate what the function **does** and, when it returns a value, **what it returns**.

| Pattern | Use for |
| --- | --- |
| `get_*` | Returns a value, no side-effects (`get_active_slot() -> Slot`) |
| `find_*` | Searches and may return null (`find_player(id) -> Player`) |
| `is_*` / `has_*` / `can_*` | Returns `bool` (`is_full()`, `has_item(id)`, `can_place()`) |
| `try_*` | Attempts an operation, returns `bool` success (`try_pickup(item)`) |
| `request_*` | Sends a network request, no direct return (`request_chest_take(...)`) |
| `_on_*` | Signal/event handler (`_on_inv_changed()`) |
| `_build_*` | Constructs and adds UI nodes (`_build_slot(...)`) |
| `_server_do_*` | Server-only execution path (`_server_do_pickup(...)`) |
| `_rpc_*` | RPC target functions — never called directly (`_rpc_sync_inventory(...)`) |

Avoid vague names like `update()`, `handle()`, `process()`, `do_thing()`. If you can't name it clearly, the function is probably doing too much.

### Variable naming

- Booleans: always `is_`, `has_`, or `can_` prefix (`is_sprinting`, `has_authority`, `can_snap`)
- Collections: plural noun (`slots`, `enemies`, `pending_ids`)
- Private fields: `_` prefix (`_slots`, `_world_items`, `_applying_remote`)
- Avoid abbreviations except for universally understood ones (`idx`, `qty`, `pos`, `inv`, `id`)

### Accessing engine singletons from RefCounted

`RefCounted` classes (controllers, data helpers) are not Nodes and don't have `get_tree()` or `multiplayer`. Use these patterns instead:

```gdscript
# SceneTree
var tree: SceneTree = Engine.get_main_loop() as SceneTree

# MultiplayerAPI — use tree.root (a Node), NOT tree.multiplayer (doesn't exist)
var is_server: bool = tree.root.multiplayer.is_server()

# Finding nodes by group
var world: Node = tree.get_first_node_in_group("world")
```

Always guard against `tree == null` (e.g. during unit test or tool context).

---

## Patterns to follow

- Always fetch items via `ItemRegistry.get_item(id)`, never hardcode resource paths at runtime
- Use `GameState.push_ui()` / `pop_ui()` for any overlay that blocks gameplay
- Server-authoritative: gameplay decisions (spawning, removal, placement) run on server and are replicated via `@rpc("authority", ...)` or request→relay pattern
- Player authority check: `is_multiplayer_authority()` before processing local input; guard is required in both `_unhandled_input` and `_physics_process`
- `NetworkManager.is_active()` before any net-specific code — game must work in solo mode too

---

## Entry point

`ui/lobby.tscn` is the main scene. From there players host or join, then load into `world/world.tscn`.

---

## Autoloads (singletons)

| Name             | File                          | Role                                                                    |
| ---------------- | ----------------------------- | ----------------------------------------------------------------------- |
| `GameState`      | `autoload/game_state.gd`      | Currency, `is_building` flag, `ui_open` stack (push/pop), `debug_mode` |
| `InputHelper`    | `autoload/input_helper.gd`    | Detects gamepad vs keyboard (`is_joy()`)                                |
| `AudioManager`   | `autoload/audio_manager.gd`   | SFX/music bus wrapper                                                   |
| `ItemRegistry`   | `autoload/item_registry.gd`   | Preloads all `ItemData` resources; lookup by string `id`                |
| `ItemTooltip`    | `autoload/item_tooltip.gd`    | Floating tooltip shown on hover/controller cursor                       |
| `NetworkManager` | `autoload/network_manager.gd` | Steam lobby + `SteamMultiplayerPeer`; handshake, player dict            |

`UIStyle` (`autoload/ui_style.gd`) is NOT in `project.godot` autoloads — loaded via `preload` where needed.

---

## Scene structure

```
world.tscn (world/world.gd)
├── WorldGenerator      ← world/world_generator.gd, generates terrain + spawns everything
├── Players/            ← player instances added at runtime by world.gd
├── WaveSpawner         ← spawned by WorldGenerator into world root
├── DayNightCycle       ← spawned by WorldGenerator into world root
├── BuildSystem         ← build/build_system.tscn, handles ghost preview + placement
└── ... (WorldEnvironment, Sun, etc.)

player.tscn (player/player.gd : CharacterBody3D)
├── Head/Camera3D
├── Head/InteractRay    ← RayCast3D, detects interact/enemy targets
├── Head/CarryPoint     ← held item is reparented here
└── Inventory           ← added at runtime (player/inventory.gd)
```

---

## Core systems

### Multiplayer (`autoload/network_manager.gd`)

- Steam listen-server via `SteamMultiplayerPeer`
- Host creates a Friends-Only lobby; world seed stored in Steam lobby metadata so all peers generate the same world
- Handshake: client → `_hello(name)` → server broadcasts `_announce`, sends `_welcome(players)` → client emits `connected_ok`
- Player position sync: `_sync_transform` RPC, `unreliable_ordered`, sent every physics frame by authority

### Player (`player/player.gd`)

- `is_multiplayer_authority()` gate on all local input and physics
- Remote players get a capsule mesh + Label3D name tag
- `GameState.ui_open` → player input frozen (movement coasts to zero)
- `GameState.is_building` → attack input suppressed

### Inventory (`player/inventory.gd`)

- `TOTAL_SLOTS = 32` (24 main + 8 hotbar)
- Each `Slot` holds an `ItemData` reference + `Array[PhysicalItem]` for stacking
- Add priority: stack into existing hotbar → existing main → empty hotbar → empty main
- `changed` signal drives all UI refreshes

### Items

- `ItemData` (Resource) — id, display_name, icon, size, mass, carry_stack, color, audio overrides
- `ToolItemData` extends `ItemData` — adds `attack_damage`, `durability`, `harvest_power`, tool tier
- `PhysicalItem` (RigidBody3D) — the in-world node; carries a reference to `ItemData` and a `net_id` for multiplayer sync
- All items registered in `ItemRegistry` by string `id`; always look up items via `ItemRegistry.get_item(id)`

### Build system (`build/build_system.gd`)

- `B` enters build mode; shows a ghost box (BoxMesh) at raycast hit point
- Snap: scans nearby `placed_pieces` group for socket alignment within `SNAP_DIST = 0.3 m`
- Ghost colours: white = free, green = snapping, red = blocked
- Placement synced via RPC: client sends `_request_place` to server, server applies locally and relays to others
- Placed pieces are `PlacedPiece` nodes in group `placed_pieces`; `world.gd` owns `_placed_pieces` dict (net_id → Node3D) as single source of truth

### Wave spawner (`world/wave_spawner.gd`)

- Server-only: only runs on `multiplayer.is_server()`
- Night = `time_of_day > 0.75 or < 0.25`
- Enemies alive cap: `3 + (wave - 1) * 2`; spawn interval converges to 1.2 s by wave 5
- Enemy types: `grunt` (wave 1+), `brute` (wave 2+), `runner` (wave 3+)
- Spawns via `_rpc_spawn` RPC so all peers see enemies

### World generation (`world/world_generator.gd`)

- Seeded via `NetworkManager.world_seed` (same seed = identical world on all peers)
- 320×330 m island, 2.5 m cells, `FastNoiseLite` simplex heightmap + biome noise
- Spawns: terrain, foliage, day/night cycle, core (green glowing pillar), wave spawner, 60 ore deposits

### Crafting (`ui/crafting_ui.gd`, `world/crafting_recipe.gd`)

- Opened by interacting with the Core
- Three tabs: Materials / Tools / Weapons
- Recipes defined as `CraftingRecipe` resources; looked up by tab via `CraftingRecipe.by_tab()`
- Crafting spawns `PhysicalItem` at player position then calls `player.pick_up()`

---

## UI conventions

### Inventory windows

All inventory-style panels (player inventory, crafting table, chests, shops, …) extend `InventoryWindow` (`ui/inventory_window.gd`). The base class provides:

- Window frame: scrim overlay + panel + title bar + close button (auto keyboard/controller badge)
- Drag-and-drop system: pick up, place, split, shift-click transfer, double-click collect
- Mouse-mode management and controller-badge close hint
- `GameState.push_ui()` / `pop_ui()` lifecycle
- `InputHelper.input_changed` wiring

**Creating a new inventory window:**

```gdscript
extends InventoryWindow

func _window_title()   -> String: return "CHEST"
func _window_layout()  -> Layout: return Layout.CENTERED   # or ANCHORED
func _window_anchors() -> Array[float]: return [0.3, 0.1, 0.7, 0.9]  # ANCHORED only

func _build_content(vbox: VBoxContainer) -> void:
    # populate slots using _build_slot(parent, idx, slots_array)
    pass

func _on_opened()  -> void: pass   # connect _inv, call _refresh()
func _on_closed()  -> void: pass   # cleanup
func _refresh()    -> void: pass   # update slot displays
func _handle_input(event: InputEvent) -> bool: return false  # true = consumed
func _quick_transfer(items, from_idx) -> Array[PhysicalItem]: return items  # shift-click
```

Layout modes:

- `CENTERED` — panel auto-sizes to content, centered on screen (player inventory)
- `ANCHORED` — panel stretches to anchor rect, good for scrollable content (crafting)

### Rules

- **Never construct `Color()` anywhere outside `autoload/ui_style.gd`.** All color values live there and are referenced by name everywhere else.
- Any UI that blocks gameplay calls `GameState.push_ui()` on open and `GameState.pop_ui()` on close.
- `ItemTooltip.show_for(item_data, [], anchor_control)` / `ItemTooltip.hide()` for item tooltips.
- Controller detection: `InputHelper.is_joy()` — show badge hints when true.

### Color palette (`autoload/ui_style.gd`)

| Constant            | Purpose                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| `PRIMARY`           | Gold accent — active slots, focus rings, highlights                        |
| `PRIMARY_VARIANT`   | Hover / pressed state of PRIMARY                                           |
| `ON_PRIMARY`        | Text/icons drawn on a PRIMARY background                                   |
| `SECONDARY`         | Sky blue — controller D-pad cursor, interactive focus                      |
| `ON_SECONDARY`      | Text/icons drawn on a SECONDARY background                                 |
| `BACKGROUND`        | Page/world background                                                      |
| `ON_BACKGROUND`     | Text/icons drawn directly on `BACKGROUND` — **not inside panels**          |
| `ON_BACKGROUND_DIM` | Secondary/hint text drawn directly on `BACKGROUND` — **not inside panels** |
| `SURFACE`           | Panels, slots, tooltips, badges                                            |
| `SURFACE_VARIANT`   | Raised cards within a panel                                                |
| `SURFACE_BORDER`    | Panel and slot borders                                                     |
| `SCRIM`             | Full-screen dim overlay behind modals                                      |
| `ON_SURFACE`        | Primary text/icons drawn on a `SURFACE` element                            |
| `ON_SURFACE_DIM`    | Secondary/hint text drawn on a `SURFACE` element                           |
| `STATUS_OK`         | Green — success, safe, A button                                            |
| `STATUS_WARN`       | Red — danger, destructive, back, exit, B button                            |
| `STATUS_CAUTION`    | Yellow — warning, X button                                                 |
| `STATUS_INFO`       | Blue — informational, Y button                                             |
| `BTN_SHOULDER`      | Dark grey — L1/R1/L2/R2 shoulder badges                                    |

### Factory functions — always use these, never raw `add_theme_*_override` chains

```gdscript
# Create a new Label (font + size + color wired up)
UIStyle.make_label(text, UIStyle.SIZE_BODY, UIStyle.ON_BACKGROUND, bold)

# Style an existing @onready Label from a scene (inside a panel → ON_SURFACE / ON_SURFACE_DIM)
UIStyle.apply_label(lbl, UIStyle.SIZE_SM, UIStyle.ON_SURFACE_DIM)

# StyleBoxFlat for panels, tooltips, cards
UIStyle.make_panel_style(UIStyle.SURFACE, UIStyle.SURFACE_BORDER, radius, margin)

# Focus outline drawn outside the button rect
UIStyle.make_focus_style(UIStyle.PRIMARY)
```

### Font sizes

| Constant       | Value | Use                   |
| -------------- | ----- | --------------------- |
| `SIZE_XS`      | 9     | Badge labels          |
| `SIZE_SM`      | 11    | Secondary text, stats |
| `SIZE_BODY`    | 14    | Default body text     |
| `SIZE_LG`      | 18    | Section headings      |
| `SIZE_HEADING` | 22    | Panel titles          |

### Input prompt badges

```gdscript
# Badge from InputMap action (auto keyboard vs controller)
UIStyle.make_prompt("open_inventory", "Inventory")

# Raw badge label (for L1/R1 or labels not in InputMap)
UIStyle.make_badge("L1", "Cycle")

# Two badges separated by "/" — e.g. L1/R1 cycle hint
UIStyle.make_badge_pair("L1", "R1", "Cycle Tab")

# Multi-row hint area from an array of parts
# Parts starting with "@" are rendered as action badges; others are plain text
UIStyle.make_row(["@open_inventory", "Inventory"])
UIStyle.set_hint(container, [["@attack", "Place"], ["@exit_build", "Cancel"]])
```

---

## Input system

- **Never check `event.keycode`, `event.physical_keycode`, or `event.button_index` directly in gameplay code.** All input goes through named InputMap actions.
- Use `event.is_action_pressed("action_name")` in `_unhandled_input` / `_input`.
- Use `Input.is_action_pressed("action_name")` for polling in `_process` / `_physics_process`.
- All bindings live in `project.godot` `[input]` section — check there for action names.

---

## Groups

| Group             | Members                               |
| ----------------- | ------------------------------------- |
| `player`          | Local player node                     |
| `world`           | `world.gd` root                       |
| `world_generator` | `WorldGenerator` node                 |
| `day_night`       | `DayNightCycle` node                  |
| `wave_spawner`    | `WaveSpawner` node                    |
| `enemies`         | All live enemy bodies                 |
| `harvestable`     | Trees, rocks, ore deposits            |
| `placed_pieces`   | All `PlacedPiece` nodes               |
| `physical_items`  | All `PhysicalItem` nodes in the world |
| `crafting_ui`     | `CraftingUI` node                     |
| `inventory_hud`   | `InventoryHUD` node                   |

---

## Item resource files

- `items/resources/` — base materials (stone, wood_log, wooden_plank, wooden_wall)
- `items/resources/tools/` — axe/pickaxe in wooden/stone/iron tiers
- `items/resources/weapons/` — sword in wooden/stone/iron tiers
- `items/resources/ores/` — flint, coal, copper, iron, quartz, gold, amber, diamond, obsidian
- `world/ores/` — `OreData` deposit resources (rarity, drop item, etc.)
