package basecctv;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.models.Characters", methodName = "behind")
public class Patch_Behind {
    @Patch.OnExit
    public static void exit(@Patch.Return(readOnly = false) boolean behind) {
        behind = Cctv.behind(behind);
    }
}
