# Project Zomboid – Body Cam (Admin Spectator)

A multiplayer mod for streamers. An **admin or moderator** on a second PC or laptop locks
their view onto any online player as a **spectator camera held close above them**.
It shows everything around the player, including what's behind them that they
can't see themselves. Capture that laptop's game window in OBS and you have a
second camera feed.

## How it works (and why)

Project Zomboid's camera always follows the *local* player, and a client only
loads the part of the map around its own character. Pointing the camera at a
distant player isn't possible. Instead, while watching, the mod:

1. Makes the admin character **invisible, ghosted (zombies ignore you), god mode
   and no-clip**, and saves the previous state so it can be restored afterwards.
2. Turns on the admin powers **see everyone / hear everyone**, so zombies and
   players behind the wearer stay visible on the feed.
3. **Pins the admin character onto the wearer**, 24 times a second, about 250 ms
   behind them. The camera then hangs above the wearer and zoomed in. It doesn't
   rotate: north stays north, like a spectator camera.
4. Asks the **server** where the wearer is every 2 seconds. If the wearer is far
   away or out of sync, it teleports you there with `/teleportto` and then resumes
   tight tracking. This also handles vehicles, fast travel and respawns.
5. Draws a small **REC ● / unit label / in-game timestamp** overlay (optional). If
   the wearer disconnects or dies, it shows **SIGNAL LOST** and keeps retrying.

> **About the angle:** the vanilla camera is fixed at the game's isometric angle.
> It can zoom right in on the wearer, but it can't point straight down from "3 feet
> above the head". For that you'd need a 3D camera mod with a top-down mode. Body
> Cam keeps the laptop's character on the wearer, so such a camera would follow
> them too.
>
> **Prefer the old chest-cam?** Tick **Turn with their body**. The view then copies
> the wearer's body facing, vision cone included.

## Install (Build 42 dedicated server)

A dedicated server, Indifferent Broccoli included, downloads mods from the Steam
Workshop. Players' games then download them automatically when they join. So the
easiest route is to upload this mod to the Workshop as an **Unlisted** item. It
then won't show in Workshop search, but the server and your players can still
download it.

### 1. Upload to the Workshop (once, from your streaming PC)

1. Copy this whole repository folder (the one containing `preview.png` and
   `Contents/`) to `%UserProfile%\Zomboid\Workshop\BodyCam\`.
2. Start Project Zomboid → **Workshop** → **Create and update items** → pick
   `BodyCam` → upload.
3. On the Steam page that opens, set visibility to **Unlisted** (not *Private*,
   or the server can't download it). Note the number at the end of the page's URL.
   That's the **Workshop ID**.

### 2. Enable it on the server (Indifferent Broccoli panel)

1. Stop the server.
2. Add the mod using the panel's mod manager, or edit the server `.ini`
   (usually `servertest.ini`):
   - add the Workshop ID to `WorkshopItems=`
   - add `BodyCam` to `Mods=` (match the format the existing entries use; Build 42
     entries may start with a backslash, e.g. `\BodyCam`)
3. Start the server. Both your streaming account and the admin laptop download
   the mod automatically when they connect.

### Testing locally first (optional)

Copy `Contents/mods/BodyCam` to `%UserProfile%\Zomboid\mods\BodyCam`, enable it
in **Mods**, and start a single-player game. The window opens with **Insert**
(single player has no other players to watch, but you can check the UI loads).

### Folder layout

Build 42 only loads mods that have a `42/` folder (and a `common/` folder, which can
stay empty). All code lives in `Contents/mods/BodyCam/42/`.

## Usage (on the admin laptop)

1. Log in with an account that has the **admin**, **moderator**, **overseer** or **gm**
   role (`/setaccesslevel "Name" admin` from the server console or panel). If you
   use a custom role name, add the admin account's username to the
   **Body Cam → Allowed usernames** sandbox option (`BodyCam.AllowedUsers`,
   comma-separated) in the server's `_SandboxVars.lua` or the panel. The server
   checks this for every request, so the password-protected public server stays
   safe: normal players can't locate anyone.
2. **Leave any vehicle** and press **Insert** to open the Body Cam window, or
   right-click the ground → **Body Cam...**. The hotkeys can be rebound under
   **Options → Mods → Body Cam** (handy on laptops without an Insert key).
3. Select your streamer character and click **Watch** (or double-click it).
4. **Ctrl+Insert** stops watching from anywhere (or use the Stop button, the
   right-click menu, or the optional "Stop watching" key).

### Troubleshooting

Open `%UserProfile%\Zomboid\console.txt` on the admin laptop and search for `[BodyCam]`:

| What you see | Meaning |
|---|---|
| No `[BodyCam]` lines at all | The mod isn't loaded on this client: check it's in the server's mod list and downloaded |
| `Client UI loaded` but no `Hotkey pressed` when you press Insert | The key isn't reaching the game (laptop Fn key?): rebind it in Options → Mods, or use right-click → Body Cam... |
| `Game started as ..., allowed: false` | The account's role isn't recognised: set it to admin, or add the username to `BodyCam.AllowedUsers` |
| `Server module loaded` missing from the **server** log | The mod isn't enabled on the server |
| `Signal lost: <reason>` | Why the feed dropped (target not synced, too far, stopped updating, dead). Send these lines when reporting problems |
| `Follow error: ...` | A bug in the follow loop. It stops itself after repeated errors instead of lagging the game |

Options (saved to `Zomboid/Lua/BodyCam_settings.txt`):

| Option | What it does |
|---|---|
| Show REC / timestamp overlay | Blinking REC dot, unit label, in-game date/time |
| See everyone | Admin see/hear-everyone powers while watching, so whatever's behind the wearer shows on the feed (default on) |
| Turn with their body | Chest-cam style: copy the wearer's body facing and vision cone (default off) |
| Hide my own character model | Hides the admin's semi-transparent model, which otherwise overlaps the wearer |
| Zoom in when starting | Applies N zoom-in steps (default 5, adjustable), undone on stop. The game stops at its closest zoom level |
| Teleport back when stopping | Returns you to where you started |
| Resume last target after login | Rejoins the feed automatically after a reconnect (handy for long streams) |
| Forward offset | Moves the view center N tiles in front of the wearer (0 keeps them centered) |
| Camera update rate | How many times a second the view moves (default **24 fps**, choices 12–60). Gives a choppier camera cadence and less work per second |
| Camera delay | How far behind the wearer the view runs (default 250 ms, 0–1000). Smooths network jitter; raise it if movement stutters |

The unit label shown in the overlay (default `UNIT 01`) can be changed in the
settings file (`unitLabel=...`). Your OBS VHS shader goes on top of the in-game
REC/timestamp overlay, so they combine naturally.

### With Project Viewpoint

- Use the **normal (non-first-person) view** on the admin laptop for this camera
  (Viewpoint: **O** toggles first person).
- Viewpoint's free camera is **Insert + O**, which also opens the Body Cam window.
  Rebind one of them (Body Cam: **Options → Mods → Body Cam**).

### OBS / streaming tips

- In the game's **Options → Display**, enable the closest zoom levels so the
  camera can sit tight above the wearer.
- Hide the vanilla HUD on the admin laptop, or crop it out in OBS. The overlay is
  drawn in the top corners.
- Turn the overlay off if you'd rather build the body-cam frame in OBS.

## Caveats

- In multiplayer, the client nearest to zombies may be put in charge of
  simulating them. With the admin laptop sitting on your character, a bad
  connection there could make nearby zombies laggy. Use a wired or stable connection.
- Build 42 multiplayer has stronger anti-cheat. Admin roles are normally exempt,
  but if the admin laptop gets kicked or rubber-bands while following, check the
  server log for anti-cheat entries and loosen that specific check (or tell me
  what it says).
- If you still see a ghostly copy of the admin character on top of yours (some
  builds ignore the hide call), take the admin character's clothes off so it
  stays mostly unnoticeable.
- The darkening of tiles outside a character's view comes from the admin
  character's own vision cone. "See everyone" keeps zombies and players visible
  there, but the ground may still be shaded on one side. Tell me how it looks.

## Files

```
preview.png                                       Workshop thumbnail
Contents/mods/BodyCam/
  common/                                         required by Build 42 (empty)
  42/
    mod.info, poster.png, icon.png
    media/sandbox-options.txt                     BodyCam.AllowedUsers option
    media/lua/shared/BodyCam/BodyCam_Shared.lua   role checks, constants
    media/lua/shared/Translate/EN/Sandbox_EN.txt  sandbox option labels
    media/lua/server/BodyCam/BodyCam_Server.lua   answers "list players" / "where is X" (admins only)
    media/lua/client/BodyCam/BodyCam_Client.lua   follow logic, flags, settings
    media/lua/client/BodyCam/BodyCam_Overlay.lua  REC / timestamp overlay
    media/lua/client/BodyCam/BodyCam_UI.lua       control window + hotkeys
```
