module nlshim.core.render.support;

import nlshim.core.runtime_state : currentRenderBackend;
public import nlshim.math : vec2, vec3, vec4, mat4, vec2i;
import nlshim.math.veca : veca;
import inmath.linalg : Vector;
alias vec2us = Vector!(ushort, 2);
alias vec3us = Vector!(ushort, 3);
alias vec4us = Vector!(ushort, 4);
alias Vec2Array = veca!(float, 2);
alias Vec3Array = veca!(float, 3);
alias Vec4Array = veca!(float, 4);

public enum BlendMode {
    Normal,
    Multiply,
    Screen,
    Overlay,
    Darken,
    Lighten,
    ColorDodge,
    LinearDodge,
    AddGlow,
    ColorBurn,
    HardLight,
    SoftLight,
    Difference,
    Exclusion,
    Subtract,
    Inverse,
    DestinationIn,
    ClipToLower,
    SliceFromLower
}

private bool inAdvancedBlending;
private bool inAdvancedBlendingCoherent;
version(OSX)
    enum bool inDefaultTripleBufferFallback = true;
else
    enum bool inDefaultTripleBufferFallback = false;
private bool inForceTripleBufferFallback = inDefaultTripleBufferFallback;
private bool inAdvancedBlendingAvailable;
private bool inAdvancedBlendingCoherentAvailable;

private auto blendBackend() { return currentRenderBackend(); }

version (InDoesRender) {
    void setAdvancedBlendCoherent(bool enabled) { blendBackend().setAdvancedBlendCoherent(enabled); }
    void setLegacyBlendMode(BlendMode blendingMode) { blendBackend().setLegacyBlendMode(blendingMode); }
    void setAdvancedBlendEquation(BlendMode blendingMode) { blendBackend().setAdvancedBlendEquation(blendingMode); }
    void issueBlendBarrier() { blendBackend().issueBlendBarrier(); }
    bool hasAdvancedBlendSupport() { return blendBackend().supportsAdvancedBlend(); }
    bool hasAdvancedBlendCoherentSupport() { return blendBackend().supportsAdvancedBlendCoherent(); }
} else {
    void setAdvancedBlendCoherent(bool) { }
    void setLegacyBlendMode(BlendMode) { }
    void setAdvancedBlendEquation(BlendMode) { }
    void issueBlendBarrier() { }
    bool hasAdvancedBlendSupport() { return false; }
    bool hasAdvancedBlendCoherentSupport() { return false; }
}

private void inApplyBlendingCapabilities() {
    bool desiredAdvanced = inAdvancedBlendingAvailable && !inForceTripleBufferFallback;
    bool desiredCoherent = inAdvancedBlendingCoherentAvailable && !inForceTripleBufferFallback;

    if (desiredCoherent != inAdvancedBlendingCoherent) {
        setAdvancedBlendCoherent(desiredCoherent);
    }

    inAdvancedBlending = desiredAdvanced;
    inAdvancedBlendingCoherent = desiredCoherent;
}

private void inSetBlendModeLegacy(BlendMode blendingMode) {
    setLegacyBlendMode(blendingMode);
}

public bool inUseMultistageBlending(BlendMode blendingMode) {
    if (inForceTripleBufferFallback) return false;
    switch(blendingMode) {
        case BlendMode.Normal,
             BlendMode.LinearDodge,
             BlendMode.AddGlow,
             BlendMode.Subtract,
             BlendMode.Inverse,
             BlendMode.DestinationIn,
             BlendMode.ClipToLower,
             BlendMode.SliceFromLower:
                 return false;
        default: return inAdvancedBlending;
    }
}

public void nlApplyBlendingCapabilities() {
    inApplyBlendingCapabilities();
}

public void inInitBlending() {
    inForceTripleBufferFallback = inDefaultTripleBufferFallback;
    inAdvancedBlendingAvailable = hasAdvancedBlendSupport();
    inAdvancedBlendingCoherentAvailable = hasAdvancedBlendCoherentSupport();
    inApplyBlendingCapabilities();
}

public void nlSetTripleBufferFallback(bool enable) {
    if (inForceTripleBufferFallback == enable) return;
    inForceTripleBufferFallback = enable;
    inApplyBlendingCapabilities();
}

public bool nlIsTripleBufferFallbackEnabled() {
    return inForceTripleBufferFallback;
}

public bool inIsAdvancedBlendMode(BlendMode mode) {
    if (!inAdvancedBlending) return false;
    switch(mode) {
        case BlendMode.Multiply:
        case BlendMode.Screen:
        case BlendMode.Overlay:
        case BlendMode.Darken:
        case BlendMode.Lighten:
        case BlendMode.ColorDodge:
        case BlendMode.ColorBurn:
        case BlendMode.HardLight:
        case BlendMode.SoftLight:
        case BlendMode.Difference:
        case BlendMode.Exclusion:
            return true;
        default:
            return false;
    }
}

public void inSetBlendMode(BlendMode blendingMode, bool legacyOnly=false) {
    if (!inAdvancedBlending || legacyOnly) inSetBlendModeLegacy(blendingMode);
    else setAdvancedBlendEquation(blendingMode);
}

public void inBlendModeBarrier(BlendMode mode) {
    if (inAdvancedBlending && !inAdvancedBlendingCoherent && inIsAdvancedBlendMode(mode))
        issueBlendBarrier();
}

// ===== Drawable helpers =====

version (InDoesRender) import nlshim.core.render.backends : RenderBackend;
version (InDoesRender) import nlshim.core.runtime_state : currentRenderBackend;

public void incDrawableBindVAO() {
    version (InDoesRender) {
        currentRenderBackend().bindDrawableVao();
    }
}

private bool doGenerateBounds = false;
public void inSetUpdateBounds(bool state) { doGenerateBounds = state; }
public bool inGetUpdateBounds() { return doGenerateBounds; }

// Minimal placeholders to satisfy type references after core/nodes removal.
class Drawable {}
class Part : Drawable {}
class Mask : Drawable {}
class Projectable : Drawable {}
class Composite : Projectable {}
