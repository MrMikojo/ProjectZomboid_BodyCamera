package basecctv;

import me.zed_0xff.zombie_buddy.Patch;

@Patch(className = "viewpoint.input.FreeCam", methodName = "view")
public class Patch_View {
    @Patch.OnExit
    public static void exit(@Patch.Argument(0) Object frame, @Patch.Argument(4) Object eye,
            @Patch.Argument(5) Object dir, @Patch.Return(readOnly = false) boolean handled) {
        handled = Cctv.view(frame, eye, dir, handled);
    }
}
