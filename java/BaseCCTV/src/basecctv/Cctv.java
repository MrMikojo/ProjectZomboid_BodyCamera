package basecctv;

// Puts Project Viewpoint's camera at a CCTV camera while Lua asks for it
// (through BaseCCTVJava). Only volatile fields cross between the Lua thread
// and Viewpoint's threads.
public final class Cctv {
    static final String TAG = "[BaseCCTV] ";
    // Viewpoint's height of one floor level in its render units (from Death Cam).
    private static final double LEVEL = 2.4494896;

    private static volatile boolean broken;
    private static volatile String brokenReason;
    private static volatile double[] wanted;    // x, y, z, yaw, pitch, fov from Lua; null = off
    private static volatile boolean active;
    private static volatile Object place;
    private static volatile double[] pose;      // x, y, z, yaw, pitch (radians)
    private static volatile double fovRad;
    private static volatile boolean centreHooked;
    private static volatile boolean viewHooked;
    private static volatile double frames;
    private static Object bodyFrame;
    private static boolean wasActive;
    private static final double[] origin = new double[3];

    private Cctv() {
    }

    static void request(double x, double y, double z, double yaw, double pitch, double fov) {
        wanted = new double[] { x, y, z, yaw, pitch, fov };
    }

    static void release() {
        wanted = null;
    }

    static double frames() {
        return frames;
    }

    static String status() {
        return broken ? "broken: " + brokenReason : "ok";
    }

    // Viewpoint FP.snapshot, once per 3D frame.
    public static void frame(Object frame) {
        frames = frames + 1;
        if (broken) {
            active = false;
            return;
        }
        try {
            double[] w = wanted;
            if (w == null) {
                if (wasActive) {
                    System.out.println(TAG + "view released");
                }
                wasActive = false;
                active = false;
                place = null;
                return;
            }
            double[] p = new double[] { w[0], w[1], w[2], w[3], w[4] };
            fovRad = w[5];
            pose = p;
            place = Vp.place(frame, p);
            active = true;
            if (!wasActive) {
                wasActive = true;
                System.out.println(TAG + "viewing camera at " + (int) p[0] + "," + (int) p[1] + "," + (int) p[2]
                        + " (hooks: centre " + centreHooked + ", view " + viewHooked + ")");
            }
        } catch (Throwable t) {
            fail(t);
        }
    }

    // Viewpoint FreeCam.centre: where the 3D world is built around.
    public static Object centre(Object original) {
        centreHooked = true;
        Object p = place;
        return active && !broken && p != null ? p : original;
    }

    // Viewpoint FreeCam.view: eye offset from the frame origin and look direction.
    public static boolean view(Object frame, Object eyeArg, Object dirArg, boolean handled) {
        viewHooked = true;
        double[] p = pose;
        if (!active || broken || p == null || frame == null
                || !(eyeArg instanceof float[]) || !(dirArg instanceof float[])) {
            return handled;
        }
        float[] eye = (float[]) eyeArg;
        float[] dir = (float[]) dirArg;
        try {
            Vp.origin(frame, origin);
            eye[0] = (float) (origin[0] - p[0]);
            eye[1] = (float) ((p[2] - origin[2]) * LEVEL);
            eye[2] = (float) (origin[1] - p[1]);
            double cosPitch = Math.cos(p[4]);
            dir[0] = (float) (-Math.cos(p[3]) * cosPitch);
            dir[1] = (float) Math.sin(p[4]);
            dir[2] = (float) (-Math.sin(p[3]) * cosPitch);
            return true;
        } catch (Throwable t) {
            fail(t);
            return handled;
        }
    }

    // Viewpoint View.fovY (radians).
    public static float fov(float original) {
        return active && !broken ? (float) fovRad : original;
    }

    // Viewpoint Characters.behind: don't hide the player's own body while on a camera.
    public static boolean behind(boolean original) {
        return original && !(active && !broken);
    }

    // Viewpoint Characters.snapshot: draw the player's own head/body like a third-person shot.
    public static void bodyOn(Object frame) {
        if (!active || broken || frame == null) {
            return;
        }
        try {
            if (!Vp.drawOwnBody(frame)) {
                Vp.drawOwnBody(frame, true);
                bodyFrame = frame;
            }
        } catch (Throwable t) {
            fail(t);
        }
    }

    public static void bodyOff(Object frame) {
        if (frame == null || bodyFrame != frame) {
            return;
        }
        bodyFrame = null;
        try {
            Vp.drawOwnBody(frame, false);
        } catch (Throwable t) {
            fail(t);
        }
    }

    private static void fail(Throwable t) {
        if (broken) {
            return;
        }
        broken = true;
        active = false;
        place = null;
        brokenReason = String.valueOf(t);
        System.out.println(TAG + "switched off, it no longer fits this version of Viewpoint: " + t);
        t.printStackTrace(System.out);
    }
}
