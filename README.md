# Project Zomboid – Base CCTV (for Project Viewpoint)

Install CCTV cameras around your base and watch them from a computer, through
[Project Viewpoint](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528)'s
3D camera. You can look around from each camera.

> **Status: test build.** This version proves the camera view works. Cameras are
> placed with a right-click test menu, kept for the current session only, and
> only you see them. Crafting, installing, power and "same building" rules come next.

## Requirements

Every player needs:

- **ZombieBuddy** (Java mod loader), set up once as its Workshop page describes
- **Project Viewpoint**, with the 3D view on (first or third person, key **O**)
- **Base CCTV** (this mod). On first launch ZombieBuddy asks you to approve
  BaseCCTV's Java code. The jar isn't signed yet, so it shows as unsigned.

Load order: ZombieBuddy, Project Viewpoint, then Base CCTV.

## How it works

Viewpoint draws the game in 3D from a camera that normally sits in your
character's head. Base CCTV's small Java add-on (`BaseCCTV.jar`, loaded by
ZombieBuddy) hooks the same parts of Viewpoint that the *Death Cam* add-on
uses. While you're viewing, it moves that camera to the CCTV camera's
position and angle, and puts it back when you stop. The rest (menus, cameras,
controls, overlay) is ordinary Lua, which talks to the Java add-on through
`BaseCCTVJava`.

If a Viewpoint update changes those internals, the add-on switches itself off
and writes a `[BaseCCTV]` line to `console.txt` instead of crashing.

## Testing the view (single player or your own server)

1. Copy `Contents/mods/BaseCCTV` to `%UserProfile%\Zomboid\mods\BaseCCTV` and
   enable it (with ZombieBuddy and Viewpoint).
2. In game, switch Viewpoint to first person (**O**) and free the cursor
   (middle mouse button) so you can right-click.
3. Stand somewhere in your base, right-click a floor tile a few tiles away →
   **CCTV (test) → Add test camera here**. The camera goes near the ceiling
   above that tile, facing where you stood. Add a few.
4. Right-click a **computer → View Cameras**. If your computer doesn't get the
   option, use **CCTV (test) → View cameras (without a computer)** and also
   **CCTV (test) → Log clicked objects** on the computer. Send me the log line so I
   can recognise it.

While viewing:

| Key | Action |
|---|---|
| Arrow keys | Look around (up to 75° either side of where the camera faces) |
| `+` / `-` | Zoom |
| `,` / `.` | Previous / next camera |
| Backspace | Stop viewing (also: right-click → CCTV: stop viewing) |

Viewing stops by itself if you walk away from where you started, get hurt, or die.

### What to look for

- Does the view jump to the camera and turn with the arrow keys?
- Is your own character visible when a camera looks at you?
- **Zombies and players:** are they visible to the camera even when your character
  can't see them? This decides how the next version works.
- The `[BaseCCTV]` lines in `console.txt`: `client loaded; Java add-on found`,
  `viewing camera at ...`, or any `switched off` / `view error` lines.

## Building the Java add-on

`java/BaseCCTV/build.sh` compiles `BaseCCTV.jar` into the mod folder (JDK 17+;
targets Java 17 like Death Cam, so it loads on ZombieBuddy 2.x and 3.x). The
`stubs/` folder only satisfies the compiler and is never packaged: the real
ZombieBuddy and Viewpoint classes come from the game at runtime.

## Files

```
preview.png                                     Workshop thumbnail
Contents/mods/BaseCCTV/
  common/                                       required by Build 42 (empty)
  42/
    mod.info, poster.png, icon.png
    media/java/client/BaseCCTV.jar              Java add-on (built from java/BaseCCTV)
    media/lua/client/BaseCCTV/CCTV_Client.lua   cameras, viewing, controls, menus
    media/lua/client/BaseCCTV/CCTV_Overlay.lua  REC / camera name / timestamp overlay
java/BaseCCTV/
  src/basecctv/                                 add-on source (Viewpoint hooks + Lua API)
  stubs/                                        compile-time stand-ins (not packaged)
  build.sh
```

The earlier Body Cam (admin spectator) mod is in this repository's git history.
