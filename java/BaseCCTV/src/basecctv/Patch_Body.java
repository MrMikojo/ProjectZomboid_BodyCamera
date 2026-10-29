package basecctv;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.models.Characters", methodName = "snapshot")
public class Patch_Body {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object frame) {
        Cctv.bodyOn(frame);
    }

    @Patch.OnExit
    public static void exit(@Patch.Argument(0) Object frame) {
        Cctv.bodyOff(frame);
    }
}
