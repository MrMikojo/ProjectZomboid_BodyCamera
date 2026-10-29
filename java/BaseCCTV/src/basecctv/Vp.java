package basecctv;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;

// Reflection over Project Viewpoint internals (the same members Death Cam uses).
final class Vp {
    private static Field camX;
    private static Field camY;
    private static Field camZ;
    private static Constructor<?> place;
    private static Field cameraShot;
    private static Field shotOn;

    private Vp() {
    }

    private static void bind(Object frame) throws ReflectiveOperationException {
        if (camX != null) {
            return;
        }
        Class<?> cls = frame.getClass();
        place = Class.forName("viewpoint.input.FreeCam$Place", false, cls.getClassLoader())
                .getConstructor(double.class, double.class, double.class, float.class, float.class);
        cameraShot = cls.getField("cameraShot");
        shotOn = cameraShot.getType().getField("on");
        camX = cls.getField("camX");
        camY = cls.getField("camY");
        camZ = cls.getField("camZ");
    }

    static void origin(Object frame, double[] out) throws ReflectiveOperationException {
        bind(frame);
        out[0] = camX.getFloat(frame);
        out[1] = camY.getFloat(frame);
        out[2] = camZ.getFloat(frame);
    }

    // pose: x, y, z (tiles / levels), yaw, pitch (radians)
    static Object place(Object frame, double[] pose) throws ReflectiveOperationException {
        bind(frame);
        return place.newInstance(pose[0], pose[1], pose[2], (float) pose[3], (float) pose[4]);
    }

    static boolean drawOwnBody(Object frame) throws ReflectiveOperationException {
        bind(frame);
        return shotOn.getBoolean(cameraShot.get(frame));
    }

    static void drawOwnBody(Object frame, boolean on) throws ReflectiveOperationException {
        bind(frame);
        shotOn.setBoolean(cameraShot.get(frame), on);
    }
}
