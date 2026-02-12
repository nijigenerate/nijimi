/*
    Copyright ﾂｩ 2022, Inochi2D Project
    Copyright ﾂｩ 2024, nijigenerate Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module tracking;
import tracking.expr;
public import tracking.input;
public import tracking.ratiobinding;
public import tracking.exprbinding;
public import tracking.eventbinding;
public import tracking.compoundbinding;
public import tracking.receiver;
import core.time : MonoTime;
import std.math : pow;
import fghj;
import i18n;
import std.format;
import std.math.rounding : quantize, round;
import std.math : isFinite;
import std.array;
import std.uni: toUpper;
import std.exception : collectException;

enum TrackingBindingsExtKey = "com.inochi2d.inochi-session.bindings";

alias ParameterUpdateSink = void delegate(uint parameterUuid, int axis, float value, bool additive);
private __gshared ParameterUpdateSink gParameterUpdateSink;

void neSetParameterUpdateSink(ParameterUpdateSink sink) {
    gParameterUpdateSink = sink;
}

private __gshared MonoTime gPrevTick;
private __gshared bool gPrevTickInitialized;
private __gshared double gDeltaSeconds = 1.0 / 60.0;

void neTrackingTick() {
    auto now = MonoTime.currTime;
    if (!gPrevTickInitialized) {
        gPrevTick = now;
        gPrevTickInitialized = true;
        gDeltaSeconds = 1.0 / 60.0;
        return;
    }

    auto ns = (now - gPrevTick).total!"nsecs";
    gPrevTick = now;
    if (ns <= 0) {
        gDeltaSeconds = 1.0 / 60.0;
        return;
    }

    gDeltaSeconds = cast(double)ns / 1_000_000_000.0;
    if (!isFinite(gDeltaSeconds) || gDeltaSeconds <= 0 || gDeltaSeconds > 1.0) {
        gDeltaSeconds = 1.0 / 60.0;
    }
}

double deltaTime() {
    return gDeltaSeconds;
}

float dampen(float value, float target, double dt, double speed = 1) {
    if (dt <= 0) return value;
    // Exponential smoothing; speed is roughly "frames to converge" compatible.
    auto alpha = 1.0 - pow(0.5, dt * speed * 60.0);
    if (alpha < 0) alpha = 0;
    if (alpha > 1) alpha = 1;
    return cast(float)(value + (target - value) * alpha);
}

/**
    Binding Type
*/
enum BindingType {
    /**
        A binding where the base source is blended via
        in/out ratios
    */
    RatioBinding,

    /**
        A binding in which math expressions are used to
        blend between the sources in the VirtualSpace zone.
    */
    ExpressionBinding,

    /**
        A binding triggered by event.
    */
    EventBinding,

    /**
        A Binding which combined values of sub-bindings.
    */
    CompoundBinding,

    /**
        Binding controlled from an external source.
        Eg. over the internet or from a plugin.
    */
    External
}

/**
    Source type
*/
enum SourceType {
    /**
        The source is a blendshape
    */
    Blendshape,

    /**
        Source is the X position of a bone
    */
    BonePosX,

    /**
        Source is the Y position of a bone
    */
    BonePosY,

    /**
        Source is the Y position of a bone
    */
    BonePosZ,

    /**
        Source is the roll of a bone
    */
    BoneRotRoll,

    /**
        Source is the pitch of a bone
    */
    BoneRotPitch,

    /**
        Source is the yaw of a bone
    */
    BoneRotYaw,

    /** 
     * Source is the key press
     */
    KeyPress,
}

/**
    Tracking Binding 
*/

alias Serializer = JsonSerializer!("", void delegate(const(char)[]) pure nothrow @safe);

interface ITrackingBinding {
    void serializeSelf(ref Serializer serializer);
    SerdeException deserializeFromFghj(Fghj data);
    void outRangeToDefault();
    bool update(ITrackingInputFrame input, out float result);
}

class TrackingBinding {
protected:
    // UUID of param to map to
    uint paramUUID;

    // Sum of weighted plugin values
    float sum = 0;

    // Combined value of weights
    float weights = 0;

public:
    struct ParamMeta {
        uint uuid;
        bool isVec2;
        float minX = 0;
        float minY = 0;
        float maxX = 1;
        float maxY = 1;
        float defaultX = 0;
        float defaultY = 0;
        float valueX = 0;
        float valueY = 0;

        float axisMin(int axis) const {
            return axis == 0 ? minX : minY;
        }

        float axisMax(int axis) const {
            return axis == 0 ? maxX : maxY;
        }

        float axisDefault(int axis) const {
            return axis == 0 ? defaultX : defaultY;
        }

        float axisValue(int axis) const {
            return axis == 0 ? valueX : valueY;
        }

        void setAxisValue(int axis, float v) {
            if (axis == 0) valueX = v;
            else valueY = v;
        }

        float unmapAxis(int axis, float offset) const {
            float mn = axisMin(axis);
            float mx = axisMax(axis);
            return (mx - mn) * offset + mn;
        }
    }

    ITrackingBinding delegated;

    /**
        Display name for the binding
    */
    string name;

    /**
        The type of the binding
    */
    BindingType type_;

    /**
        The nijilive parameter it should apply to
    */
    ParamMeta param;

    /**
        Weights the user has set for each plugin
    */
    float[string] pluginWeights;

    /**
        The axis to apply the binding to
    */
    int axis = 0;

    BindingType type() { return type_; }
    void type(BindingType value) {
        type_ = value;
        switch (type_) {
            case BindingType.RatioBinding:
                delegated = new RatioTrackingBinding(this);
                break;
            case BindingType.ExpressionBinding:
                delegated = new ExpressionTrackingBinding(this);
                break;
            case BindingType.EventBinding:
                delegated = new EventTrackingBinding(this);
                break;
            case BindingType.CompoundBinding:
                delegated = new CompoundTrackingBinding(this);
                break;
            default:
                break;
        }
        ///
    }

    void serialize(S)(ref S serializer) {
        auto state = serializer.structBegin;
            serializer.putKey("name");
            serializer.putValue(name);
            serializer.putKey("bindingType");
            serializer.serializeValue(type_);
            serializer.putKey("param");
            serializer.serializeValue(param.uuid);
            serializer.putKey("axis");
            serializer.putValue(axis);

            if (delegated)
                delegated.serializeSelf(serializer);

        serializer.structEnd(state);
    }
    
    SerdeException deserializeFromFghj(Fghj data) {
        data["name"].deserializeValue(name);
        data["bindingType"].deserializeValue(type_);
        type = type_;
        data["param"].deserializeValue(paramUUID);
        if (data["axis"].data.length != 0) data["axis"].deserializeValue(axis);

        if (delegated) {
            delegated.deserializeFromFghj(data);
        }
        
        return null;
    }

    /**
        Sets the parameter out range to the default for the axis
    */
    void outRangeToDefault() {
        if (delegated)
            delegated.outRangeToDefault();
    }

    /**
        Finalizes the tracking binding, if possible.
        Returns true on success.
        Returns false if the parameter does not exist.
    */
    bool finalize() {
        param.uuid = paramUUID;
        if (!param.isVec2) {
            if (axis < 0) axis = 0;
            if (axis > 1) axis = 1;
        }
        return true;
    }

    /**
        Updates the parameter binding
    */
    void update(ITrackingInputFrame input) {
        if (delegated) {
            float updatedValue;
            if (delegated.update(input, updatedValue)) {
                // Keep local mirror for dampening/interpolation state.
                param.setAxisValue(axis, updatedValue);
                auto sink = gParameterUpdateSink;
                if (sink !is null) {
                    sink(param.uuid, axis, updatedValue, false);
                }
            }
        }
    }

    void update() {
        update(currentTrackingInput());
    }
    
    /**
        Submit value for late update application
    */
    void submit(string plugin, float value) {
        if (plugin !in pluginWeights)
            pluginWeights[plugin] = 1;
        
        sum += value*pluginWeights[plugin];
        weights += pluginWeights[plugin];
    }

    /**
        Apply all the weighted plugin values
    */
    void lateUpdate() {
        if (weights > 0) {
            auto delta = cast(float)round(sum / weights);
            auto next = param.axisValue(axis) + delta;
            param.setAxisValue(axis, next);
            auto sink = gParameterUpdateSink;
            if (sink !is null) {
                sink(param.uuid, axis, delta, true);
            }
        }
    }
}

bool neTryLoadBindingsFromExtData(const(ubyte)[] rawBytes, out TrackingBinding[] bindings) {
    bindings = [];
    if (rawBytes is null || rawBytes.length == 0) return false;
    auto raw = cast(string)rawBytes;
    TrackingBinding[] preBindings;
    if (collectException(preBindings = deserialize!(TrackingBinding[])(raw)) !is null) {
        return false;
    }

    foreach (ref binding; preBindings) {
        if (binding.finalize()) {
            bindings ~= binding;
        }
    }
    return true;
}



