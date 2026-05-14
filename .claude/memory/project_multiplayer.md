---
name: Multiplayer Architecture
description: How co-op multiplayer is implemented in the sauna sim
type: project
---

Co-op multiplayer added using Godot 4 ENet (listen-server model, up to 8 players).

**Why:** User asked for multiplayer; implemented May 2026.

**How to apply:** When touching networking, player spawning, or build sync, follow this design.

## Entry flow
- Main scene is now `ui/lobby.tscn` (was `world/world.tscn`)
- Lobby: Play Solo → loads world directly; Host → starts ENet server then loads world; Join → connects then loads world on `connected_ok`

## NetworkManager (autoload)
- `autoload/network_manager.gd`
- `host(port)`, `join(ip, port)`, `close()`, `is_active()`, `is_server()`
- `players` dict: peer_id → {name}
- Signals: `player_connected`, `player_disconnected`, `connected_ok`, `connect_failed`, `server_disconnected`

## Player spawning (world.gd)
- `world/world.gd` on the World node
- Solo: world.gd does nothing; static `Player` node in world.tscn handles it
- Multiplayer: static player is queue_free()'d; players spawned into `Players` (Node3D child of World)
- Client sends `_request_players.rpc_id(1)` when world loads → server replies with `_do_spawn` RPCs
- Player nodes named after their peer ID (e.g. "1", "12345")
- `set_multiplayer_authority(id)` called BEFORE `add_child` so `_ready()` sees correct authority

## Player identity
- `player.gd` checks `is_multiplayer_authority()` in `_ready()`
- Local player: sets up normally (camera active, joins "player" group, captures mouse)
- Remote player: camera disabled, interact_ray disabled, capsule mesh + name label added
- Position sync via `@rpc("any_peer", "unreliable_ordered") _sync_transform(pos, rot_y, head_x)`
- BuildSystem / PlankPlacer / Plot all find local player via `is_multiplayer_authority()` check

## What is synced
- Player positions (RPC every physics frame from authority player)
- Blueprint placement on plot (plot.gd `_sync_blueprint` RPC, any_peer, reliable)
- Blueprint slot fills + placed planks (build_system.gd `_sync_fill` RPC, any_peer, reliable)

## What is NOT synced (by design)
- Currency / shop purchases — each player has own money
- Physical item positions — each player has their own local items
- Free-place planks (plank_placer.gd) — local only
