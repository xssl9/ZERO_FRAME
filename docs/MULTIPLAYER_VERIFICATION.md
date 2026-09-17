# Multiplayer repair / verification

For the subsequent in-place animation, first-person visibility, barrel/cover
and non-disconnecting Esc menu changes, see [gameplay verification](GAMEPLAY_VERIFICATION.md).

## Model and gameplay

`SoldierModel.instantiate()` is the common entry point for body awareness and full
network avatars. The GLB's armature node contains a Blender +90° X rotation, but
its locomotion clips are Y-up. The runtime corrects that node (including the
~100-unit rig's metre scale and +Z-to-Godot-forward rotation), not the camera or
the source binary. The inverse bind matrices must be preserved: they convert the
unit-sized mesh into rig coordinates. Animated bounds are supplied explicitly.
The unused `t_pose` clip in the source has a different root-axis convention and
is not used by the locomotion tree.

Weapons are CPU-skinned once from the existing first-person idle poses, cached,
and attached as weapon-only meshes to the soldier's right hand. They have no
arms, cameras or colliders. The first-person SubViewport remains isolated.
The grip alignment and the source skin's artistic quality still need human
visual review; automated bounds checks are not visual approval.

Hitbox radii are converted from metres to scaled bone units. Damage is traced
against these areas on the host, with cover and self-hit exclusions. Clients
submit a ray and weapon index, not damage or a victim/zone. This is **not** full
anti-cheat or lag compensation: movement remains owner-authoritative, and the
host does not yet simulate the client's inventory/ammunition.

Shot, footstep, landing, breathing and existing rifle-reload recordings travel
as sound events. Remote playback uses positional audio in the level's World3D;
local playback is not duplicated. Flashlight state, shot light pulses and bullet
impact effects are also replicated. The supplied pistol has no reload recording
and the soldier pack has no third-person reload animation; none is invented.

## Steam overlay and invitations

`steam_appid.txt` remains `480`. Steam matchmaking can work even when
`Steam.isOverlayEnabled()` is false. That was reproduced in this environment:
lobby creation, readiness and avatar retrieval succeeded, but the overlay was
not attached to the process.

- Launch an exported build through Steam and enable the Steam overlay in the
  client's settings. For local development, use a Steam shortcut to the game
  executable (or Godot with this project's `--path` argument). Restart the game
  after changing overlay/launch settings; a late API call cannot install an
  overlay hook into an already-running renderer.
- **ПРИГЛАСИТЬ ДРУГА** opens the native invite dialog when Steam reports an overlay.
  Otherwise it opens the in-game friend picker, using `inviteUserToLobby`.
- **ДРУЗЬЯ (БЕЗ ОВЕРЛЕЯ)** always opens that picker, including when Steam reports
  an overlay but its window is not appearing.
- Accepting invites uses `join_requested`; launch invites also accept
  `+connect_lobby <id>` in engine or user arguments.
- All members, including the host, must mark themselves ready. Host departure
  closes the session instead of silently migrating to an unprepared host.

The smoke test below creates and leaves one temporary Friends Only lobby. It
never sends invitations. Delivery/acceptance with a second Steam account, NAT /
Steam relay behaviour, and actual native overlay display require a two-machine
manual check. The local two-process test uses ENet, not Steam transport.

## Commands

Run from the project root with Godot 4.7 and the installed GodotSteam extension:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script scripts/tools/multiplayer_regression.gd
godot --headless --path . --script scripts/tools/all_maps_smoke_test.gd
godot --headless --path . --script scripts/tools/realism_regression.gd
godot --headless --path . --script scripts/tools/recoil_measure.gd
godot --headless --path . --script scripts/tools/recoil_measure.gd -- --pistol
```

In two terminals (start the server first; port 29834 must be free):

```sh
godot --headless --path . --script scripts/tools/network_roundtrip.gd -- --server
godot --headless --path . --script scripts/tools/network_roundtrip.gd -- --client
```

Real Forward+ render/capture and real Steam matchmaking:

```sh
godot --path . --script scripts/tools/multiplayer_regression.gd -- --capture
godot --path . --script scripts/tools/steam_lobby_smoke.gd
```

The capture is written to `build/verification/soldier.png` (generated artifact).
Headless tests explicitly skip Steam initialization so parallel regression
processes do not compete for the same Steam account.

## Manual acceptance checklist

1. Open the capture, then observe a friend standing, crouching and moving in all
   eight directions. Inspect both weapons/grips, aim pitch and model deformation.
2. Look down in first person, aim and fire beside a wall. Check visible legs,
   hidden duplicate head/arms, free-aim, recoil and unchanged weapon-camera framing.
3. Invite and join using both the native overlay and the fallback picker. Test
   joining with the game closed, host leaving, disconnecting and creating a new lobby.
4. On two Steam accounts, hear remote footsteps/shots/reload from the correct
   direction, test head/torso/limb hits and cover, then death and respawn.
