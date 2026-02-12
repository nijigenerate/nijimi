module tracking.input;

import ft.data : Bone;

interface ITrackingInputFrame {
    bool hasFocus();
    bool tryGetBlendshape(string name, out float value);
    bool tryGetBone(string name, out Bone bone);
    bool isEventOn(int keyCode);
}

final class NullTrackingInputFrame : ITrackingInputFrame {
    override bool hasFocus() {
        return false;
    }

    override bool tryGetBlendshape(string name, out float value) {
        value = 0;
        return false;
    }

    override bool tryGetBone(string name, out Bone bone) {
        bone = Bone.init;
        return false;
    }

    override bool isEventOn(int keyCode) {
        return false;
    }
}

private __gshared ITrackingInputFrame gTrackingInput;

ITrackingInputFrame currentTrackingInput() {
    if (gTrackingInput is null) {
        gTrackingInput = new NullTrackingInputFrame();
    }
    return gTrackingInput;
}

void setTrackingInput(ITrackingInputFrame input) {
    if (input is null) {
        gTrackingInput = new NullTrackingInputFrame();
    } else {
        gTrackingInput = input;
    }
}

