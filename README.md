# Project Zomboid – Body Cam (Admin Spectator)

A multiplayer mod for streamers. An **admin or moderator** on a second PC or laptop locks
their view onto any online player, like a chest-mounted body camera. Capture that
laptop's game window in OBS and you have a second "body cam" feed.

## How it works (and why)

Project Zomboid's camera always follows the *local* player, and a client only
loads the part of the map around its own character. Pointing the camera at a
distant player isn't possible. Instead, while watching, the mod:

1. Makes the admin character **invisible, ghosted (zombies ignore you), god mode
   and no-clip**, and saves the previous state so it can be restored afterwards.
2. **Pins the admin character onto the target** every tick, copying the target's
   position, floor and **facing direction**. Because line of sight and the
   darkened vision cone come from the admin's position and facing, the view
   matches what the target can see. That is the "body cam" effect.
3. Asks the **server** where the target is every 2 seconds. If the target is far
   away or out of sync, it teleports you there with `/teleportto` and then resumes
   tight tracking. This also handles vehicles, fast travel and respawns.
4. Optionally zooms in and draws a small **REC ● / unit label / in-game timestamp**
   overlay. If the target disconnects or dies, it shows **SIGNAL LOST** and keeps
   retrying.

> **Limitation:** Project Zomboid is isometric, so the camera can't be rotated or
> turned into true first person. "Chest view" here means centered and zoomed in on
> the wearer, with the wearer's vision cone. The **Forward offset** option shifts
> the view a few tiles ahead of the wearer, like a lens pointing forward.

## Install

Put the `BodyCam` folder on **the server and on both clients**:

| Where | Path |
|---|---|
| Local mods (testing) | `%UserProfile%\Zomboid\mods\BodyCam` (copy `Contents/mods/BodyCam`) |
| Workshop upload | Use this repo's `Contents/` folder as the Workshop item content |

On a dedicated server, add the mod to the server `.ini`:

```
Mods=BodyCam
WorkshopItems=<your workshop id, if uploaded>
```

The folder works for **Build 41** (`media/`) and **Build 42** (`42/` + `common/`).
After editing Lua in `media/`, run `tools/sync_b42.sh` to refresh the B42 copy.

## Usage (on the admin laptop)

1. Log in with an account that has `admin` or `moderator` access level
   (`/setaccesslevel "Name" admin` from the server console).
2. **Leave any vehicle** and press **Insert** to open the Body Cam window.
3. Select your streamer character and click **Watch** (or double-click it).
4. **Ctrl+Insert** stops watching from anywhere (or use the Stop button).

Options (saved to `Zomboid/Lua/BodyCam_settings.txt`):

| Option | What it does |
|---|---|
| Show REC / timestamp overlay | Blinking REC dot, unit label, in-game date/time |
| Match target's facing | Copy facing so the vision cone matches the wearer |
| Hide my own character model | Hides the admin's semi-transparent model, which otherwise overlaps the wearer |
| Zoom in when starting | Applies N zoom-in steps (adjustable), undone on stop |
| Teleport back when stopping | Returns you to where you started |
| Resume last target after login | Rejoins the feed automatically after a reconnect (handy for long streams) |
| Forward offset | Moves the view center N tiles in front of the wearer |

The unit label shown in the overlay (default `UNIT 01`) can be changed in the
settings file (`unitLabel=...`).

### OBS / streaming tips

- In the game's **Options → Display**, enable the closer zoom levels (e.g. 50%)
  so "Zoom in" can get close.
- Hide the vanilla HUD on the admin laptop, or crop it out in OBS. The overlay is
  drawn in the top corners.
- Turn the overlay off if you'd rather build the body-cam frame in OBS.

## Caveats

- In multiplayer, the client nearest to zombies may be put in charge of
  simulating them. With the admin laptop sitting on your character, a bad
  connection there could make nearby zombies laggy. Use a wired or stable connection.
- Servers with strict anti-cheat settings may flag the admin's teleports and
  movement. Admin and moderator accounts are normally exempt.
- If you still see a ghostly copy of the admin character on top of yours (some
  builds ignore the hide call), take the admin character's clothes off so it
  stays mostly unnoticeable.

## Files

```
Contents/mods/BodyCam/
  mod.info
  media/lua/shared/BodyCam/BodyCam_Shared.lua   access checks, constants
  media/lua/server/BodyCam/BodyCam_Server.lua   answers "list players" / "where is X" (admins only)
  media/lua/client/BodyCam/BodyCam_Client.lua   follow logic, flags, settings
  media/lua/client/BodyCam/BodyCam_Overlay.lua  REC / timestamp overlay
  media/lua/client/BodyCam/BodyCam_UI.lua       control window + hotkeys
  42/                                           Build 42 copy (generated)
  common/                                       required by Build 42
```
