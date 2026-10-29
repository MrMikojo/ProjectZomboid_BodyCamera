package basecctv;

import me.zed_0xff.zombie_buddy.Patch;
import viewpoint.input.FreeCam;

@Patch(className = "viewpoint.input.FreeCam", methodName = "centre")
public class Patch_Centre {
    @Patch.OnExit
    public static void exit(@Patch.Return(readOnly = false) FreeCam.Place place) {
        place = (FreeCam.Place) Cctv.centre(place);
    }
}
