package basecctv;

import me.zed_0xff.zombie_buddy.Exposer;

// Lua API, exposed by ZombieBuddy as the global BaseCCTVJava.
// Positions: x/y in tiles, z in levels. Angles in degrees: yaw 0 = east (+x),
// 90 = south (+y); pitch negative looks down.
@Exposer.LuaClass
public class BaseCCTVJava {
    public static void setView(double x, double y, double z, double yaw, double pitch, double fov) {
        Cctv.request(x, y, z, Math.toRadians(yaw), Math.toRadians(pitch), Math.toRadians(fov));
    }

    public static void clearView() {
        Cctv.release();
    }

    // Number of Viewpoint 3D frames seen; if it doesn't grow, the 3D view isn't running.
    public static double getFrames() {
        return Cctv.frames();
    }

    // "ok", or "broken: <reason>" if this Viewpoint version doesn't fit.
    public static String getStatus() {
        return Cctv.status();
    }

    public static String getVersion() {
        return Main.VERSION;
    }
}
