package basecctv;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.core.View", methodName = "fovY")
public class Patch_Fov {
    @Patch.OnExit
    public static void exit(@Patch.Return(readOnly = false) float fov) {
        fov = Cctv.fov(fov);
    }
}
