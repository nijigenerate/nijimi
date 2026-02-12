module tracking.ratiobinding;

import tracking;
import tracking.expr;
import ft.data : Bone;
import fghj;
import i18n;
import std.format;
import std.math.rounding : quantize;
import std.math : isFinite, PI;
import std.array;
import std.algorithm : clamp;

/**
    Ratio Tracking Binding 
*/
class RatioTrackingBinding : ITrackingBinding {
private:
    /**
        Maps an input value to an offset (0.0->1.0)
    */
    float mapValue(float value, float min, float max) {
        float range = max - min;
        float tmp = (value - min);
        float off = tmp / range;
        return clamp(off, 0, 1);
    }

    /**
        Maps an offset (0.0->1.0) to a value
    */
    float unmapValue(float offset, float min, float max) {
        float range = max - min;
        return (range * offset) + min;
    }


public:
    this(TrackingBinding binding) { this.binding = binding; }

    TrackingBinding binding;
    /// Last input value
    float inVal = 0;

    /// Last output value
    float outVal = 0;

    /// Ratio for input
    float inMin = 0;
    float inMax = 1;

    /// Ratio for output
    float outMin = 0;
    float outMax = 1;

    /**
        The type of the tracking source
    */
    SourceType sourceType;

    /**
        Name of the source blendshape or bone
    */
    string sourceName;

    /**
        Display Name of the source blendshape or bone
    */
    string sourceDisplayName;

    /**
        Whether to inverse the binding
    */
    bool inverse;

    /**
        Dampening level
    */
    int dampenLevel = 0;

    override
    void serializeSelf(ref Serializer serializer) {
        serializer.putKey("sourceType");
        serializer.serializeValue(sourceType);
        serializer.putKey("sourceName");
        serializer.putValue(sourceName);
        serializer.putKey("sourceDisplayName");
        serializer.putValue(sourceDisplayName);
        serializer.putKey("inverse");
        serializer.putValue(inverse);

        serializer.putKey("inRange");
        auto inState = serializer.listBegin();
            serializer.elemBegin();
            serializer.putValue(inMin);
            serializer.elemBegin();
            serializer.putValue(inMax);
        serializer.listEnd(inState);
        serializer.putKey("outRange");
        auto outState = serializer.listBegin();
            serializer.elemBegin();
            serializer.putValue(outMin);
            serializer.elemBegin();
            serializer.putValue(outMax);
        serializer.listEnd(outState);
        serializer.putKey("dampenLevel");
        serializer.putValue(dampenLevel);
    }
    
    override
    SerdeException deserializeFromFghj(Fghj data) {
        data["sourceType"].deserializeValue(sourceType);
        data["sourceName"].deserializeValue(sourceName);
        data["inverse"].deserializeValue(inverse);
        if (data["dampenLevel"].data.length != 0) data["dampenLevel"].deserializeValue(dampenLevel);
        if (data["inRange"].data.length != 0) {
            size_t i = 0;
            foreach (elem; data["inRange"].byElement) {
                float v;
                elem.deserializeValue(v);
                if (i == 0) inMin = v;
                else if (i == 1) inMax = v;
                ++i;
            }
        }
        if (data["outRange"].data.length != 0) {
            size_t i = 0;
            foreach (elem; data["outRange"].byElement) {
                float v;
                elem.deserializeValue(v);
                if (i == 0) outMin = v;
                else if (i == 1) outMax = v;
                ++i;
            }
        }
        this.createSourceDisplayName();
        return null;
    }

    /**
        Sets the parameter out range to the default for the axis
    */
    void outRangeToDefault() {
        outMin = binding.param.axisMin(binding.axis);
        outMax = binding.param.axisMax(binding.axis);
    }

    /**
        Updates the parameter binding
    */
    bool update(ITrackingInputFrame input, out float result) {
        if (sourceName.length == 0) {
            binding.param.setAxisValue(binding.axis, binding.param.axisDefault(binding.axis));
            return false;
        }

        float src = 0;
        if (input !is null) {
            Bone bone;
            switch(sourceType) {

                case SourceType.Blendshape:
                    input.tryGetBlendshape(sourceName, src);
                    break;

                case SourceType.BonePosX:
                    if (input.tryGetBone(sourceName, bone)) src = bone.position.x;
                    break;

                case SourceType.BonePosY:
                    if (input.tryGetBone(sourceName, bone)) src = bone.position.y;
                    break;

                case SourceType.BonePosZ:
                    if (input.tryGetBone(sourceName, bone)) src = bone.position.z;
                    break;

                case SourceType.BoneRotRoll:
                    if (input.tryGetBone(sourceName, bone)) src = cast(float)(bone.rotation.roll * 180.0 / PI);
                    break;

                case SourceType.BoneRotPitch:
                    if (input.tryGetBone(sourceName, bone)) src = cast(float)(bone.rotation.pitch * 180.0 / PI);
                    break;

                case SourceType.BoneRotYaw:
                    if (input.tryGetBone(sourceName, bone)) src = cast(float)(bone.rotation.yaw * 180.0 / PI);
                    break;

                default: assert(0);
            }
        }

        // Smoothly transition back to default pose if tracking is lost.
        if (input is null || !input.hasFocus()) {
            result= dampen(binding.param.axisValue(binding.axis), binding.param.axisDefault(binding.axis), deltaTime(), 1);
            
            // Fix anoying -e values from dampening
            result = quantize(result, 0.0001);
            return true;
        }

        // Calculate the input ratio (within 0->1)
        float target = mapValue(src, inMin, inMax);
        if (inverse) target = 1f-target;

        // NOTE: Dampen level of 0 = no damping
        // Dampen level 1-10 is inverse due to the dampen function taking *speed* as a value.
        if (dampenLevel == 0) inVal = target;
        else {
            inVal = dampen(inVal, target, deltaTime(), cast(float)(11-dampenLevel));
            inVal = quantize(inVal, 0.0001);
        }
        
        // Calculate the output ratio (whatever outRange is)
        outVal = unmapValue(inVal, outMin, outMax);
        result = outVal;
        return true;
    }

    void createSourceDisplayName() {
        switch(sourceType) {
            case SourceType.Blendshape:
                sourceDisplayName = sourceName;
                break;
            case SourceType.BonePosX:
                sourceDisplayName = _("%s (X)").format(sourceName);
                break;
            case SourceType.BonePosY:
                sourceDisplayName = _("%s (Y)").format(sourceName);
                break;
            case SourceType.BonePosZ:
                sourceDisplayName = _("%s (Z)").format(sourceName);
                break;
            case SourceType.BoneRotRoll:
                sourceDisplayName = _("%s (Roll)").format(sourceName);
                break;
            case SourceType.BoneRotPitch:
                sourceDisplayName = _("%s (Pitch)").format(sourceName);
                break;
            case SourceType.BoneRotYaw:
                sourceDisplayName = _("%s (Yaw)").format(sourceName);
                break;
            case SourceType.KeyPress:
                sourceDisplayName = _("%s (Key)").format(sourceName);
                break;
            default: assert(0);    
        }
    }
}



