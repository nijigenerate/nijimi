module tracking.receiver;

import tracking;
import tracking.ext.exvmc : ExVMCAdaptor, neIsEventOn;
import std.conv : to;
import ft.data : Bone;

final class VMCTrackingInputFrame : ITrackingInputFrame {
private:
    ExVMCAdaptor adaptor_;

public:
    this(ExVMCAdaptor adaptor) {
        adaptor_ = adaptor;
    }

    override bool hasFocus() {
        return adaptor_ !is null && adaptor_.isReceivingData();
    }

    override bool tryGetBlendshape(string name, out float value) {
        value = 0;
        if (adaptor_ is null || name.length == 0) return false;
        auto ref blendshapes = adaptor_.getBlendshapes();
        if (auto v = name in blendshapes) {
            value = *v;
            return true;
        }
        return false;
    }

    override bool tryGetBone(string name, out Bone bone) {
        bone = Bone.init;
        if (adaptor_ is null || name.length == 0) return false;
        auto ref bones = adaptor_.getBones();
        if (auto b = name in bones) {
            bone = *b;
            return true;
        }
        return false;
    }

    override bool isEventOn(int keyCode) {
        return neIsEventOn(keyCode);
    }
}

class TrackingReceiver {
private:
    TrackingBinding[] bindings_;
    string vmcAddress_ = "0.0.0.0";
    ushort vmcPort_ = 39540;
    ExVMCAdaptor vmc_;
    VMCTrackingInputFrame input_;

public:
    @property ref TrackingBinding[] bindings() {
        return bindings_;
    }

    @property string vmcAddress() const {
        return vmcAddress_;
    }

    @property void vmcAddress(string value) {
        if (value.length == 0) return;
        vmcAddress_ = value;
    }

    @property ushort vmcPort() const {
        return vmcPort_;
    }

    @property void vmcPort(ushort value) {
        if (value == 0) return;
        vmcPort_ = value;
    }

    void clearBindings() {
        bindings_.length = 0;
    }

    bool loadBindingsFromExtData(const(ubyte)[] extData) {
        TrackingBinding[] loaded;
        if (!neTryLoadBindingsFromExtData(extData, loaded)) {
            bindings_.length = 0;
            return false;
        }
        bindings_ = loaded;
        return true;
    }

    void setBindings(TrackingBinding[] bindings) {
        bindings_ = bindings.dup;
    }

    void setParameterUpdateSink(ParameterUpdateSink sink) {
        neSetParameterUpdateSink(sink);
    }

    void setupVMCReceiver() {
        if (vmc_ is null) {
            vmc_ = new ExVMCAdaptor();
            input_ = new VMCTrackingInputFrame(vmc_);
        } else if (vmc_.isRunning()) {
            vmc_.stop();
        }
        string[string] xdata;
        xdata["address"] = vmcAddress_;
        xdata["port"] = to!string(vmcPort_);
        xdata["appName"] = "nijimi";
        vmc_.setOptions(xdata);
        vmc_.start();
    }

    void stop() {
        if (vmc_ !is null && vmc_.isRunning()) {
            vmc_.stop();
        }
    }

    void update() {
        neTrackingTick();
        if (vmc_ is null) {
            setupVMCReceiver();
        }
        if (vmc_ !is null) {
            if (!vmc_.isRunning()) {
                setupVMCReceiver();
            }
            vmc_.poll();
        }
        setTrackingInput(input_);

        foreach (ref binding; bindings_) {
            if (binding is null) continue;
            binding.update(input_);
        }
    }
}
