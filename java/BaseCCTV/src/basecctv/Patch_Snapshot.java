package basecctv;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.FP", methodName = "snapshot")
public class Patch_Snapshot {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Object frame) {
        Cctv.frame(frame);
    }
}
