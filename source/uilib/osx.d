module uilib.osx;

version (OSX) {
    import bindbc.sdl;
    import core.sys.posix.dlfcn : dlopen, dlsym, RTLD_NOW, RTLD_LOCAL;
    import std.conv : to;
    import std.string : toStringz;

    alias ObjcId = void*;
    alias ObjcSel = void*;
    alias ObjcBool = byte;
    alias ObjcGetClassFn = extern(C) ObjcId function(const(char)*);
    alias ObjcRegisterSelFn = extern(C) ObjcSel function(const(char)*);
    alias MsgSendIdFn = extern(C) ObjcId function(ObjcId, ObjcSel);
    alias MsgSendBoolFn = extern(C) void function(ObjcId, ObjcSel, ObjcBool);
    alias MsgSendObjFn = extern(C) void function(ObjcId, ObjcSel, ObjcId);
    alias MsgSendULongFn = extern(C) ulong function(ObjcId, ObjcSel);
    alias MsgSendIndexObjFn = extern(C) ObjcId function(ObjcId, ObjcSel, ulong);
    alias MsgSendBoolSelFn = extern(C) ObjcBool function(ObjcId, ObjcSel, ObjcSel);
    alias MsgSendSetValuesFn = extern(C) void function(ObjcId, ObjcSel, const(int)*, int);

    private void debugLog(void function(string) debugFn, string message) {
        if (debugFn !is null) {
            debugFn(message);
        }
    }

    void configureTransparentWindow(SDL_Window* window, void function(string) debugFn = null) {
        if (window is null) {
            debugLog(debugFn, "[transparent] skipped: window is null");
            return;
        }

        auto objcHandle = dlopen("/usr/lib/libobjc.A.dylib".toStringz, RTLD_NOW | RTLD_LOCAL);
        if (objcHandle is null) {
            debugLog(debugFn, "[transparent] macOS: failed to open /usr/lib/libobjc.A.dylib");
            return;
        }

        auto objcGetClass = cast(ObjcGetClassFn)dlsym(objcHandle, "objc_getClass".toStringz);
        auto selRegisterName = cast(ObjcRegisterSelFn)dlsym(objcHandle, "sel_registerName".toStringz);
        auto objcMsgSendRaw = dlsym(objcHandle, "objc_msgSend".toStringz);
        if (objcGetClass is null || selRegisterName is null || objcMsgSendRaw is null) {
            debugLog(debugFn, "[transparent] macOS: objc runtime symbols not found");
            return;
        }

        auto msgSendId = cast(MsgSendIdFn)objcMsgSendRaw;
        auto msgSendBool = cast(MsgSendBoolFn)objcMsgSendRaw;
        auto msgSendObj = cast(MsgSendObjFn)objcMsgSendRaw;
        auto msgSendULong = cast(MsgSendULongFn)objcMsgSendRaw;
        auto msgSendIndexObj = cast(MsgSendIndexObjFn)objcMsgSendRaw;
        auto msgSendBoolSel = cast(MsgSendBoolSelFn)objcMsgSendRaw;
        auto msgSendSetValues = cast(MsgSendSetValuesFn)objcMsgSendRaw;

        auto props = SDL_GetWindowProperties(window);
        auto nsWindow = cast(ObjcId)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (nsWindow is null) {
            debugLog(debugFn, "[transparent] macOS: nsWindow is null");
            return;
        }

        auto nsColorClass = objcGetClass("NSColor".toStringz);
        if (nsColorClass is null) {
            debugLog(debugFn, "[transparent] macOS: NSColor class not found");
            return;
        }

        auto selClearColor = selRegisterName("clearColor".toStringz);
        auto selCGColor = selRegisterName("CGColor".toStringz);
        auto selContentView = selRegisterName("contentView".toStringz);
        auto selSubviews = selRegisterName("subviews".toStringz);
        auto selCount = selRegisterName("count".toStringz);
        auto selObjectAtIndex = selRegisterName("objectAtIndex:".toStringz);
        auto selLayer = selRegisterName("layer".toStringz);
        auto selSublayers = selRegisterName("sublayers".toStringz);
        auto selSetWantsLayer = selRegisterName("setWantsLayer:".toStringz);
        auto selSetOpaque = selRegisterName("setOpaque:".toStringz);
        auto selSetBackgroundColor = selRegisterName("setBackgroundColor:".toStringz);
        auto selSetHasShadow = selRegisterName("setHasShadow:".toStringz);
        auto selOpenGLContext = selRegisterName("openGLContext".toStringz);
        auto selSetValuesForParameter = selRegisterName("setValues:forParameter:".toStringz);
        auto selRespondsToSelector = selRegisterName("respondsToSelector:".toStringz);
        if (selClearColor is null || selCGColor is null ||
            selContentView is null || selSubviews is null || selCount is null || selObjectAtIndex is null ||
            selLayer is null || selSublayers is null ||
            selSetWantsLayer is null || selSetOpaque is null ||
            selSetBackgroundColor is null || selSetHasShadow is null ||
            selOpenGLContext is null || selSetValuesForParameter is null || selRespondsToSelector is null) {
            debugLog(debugFn, "[transparent] macOS: selector lookup failed");
            return;
        }

        auto clearColor = msgSendId(nsColorClass, selClearColor);
        if (clearColor is null) {
            debugLog(debugFn, "[transparent] macOS: [NSColor clearColor] returned null");
            return;
        }
        auto clearCg = msgSendId(clearColor, selCGColor);

        msgSendBool(nsWindow, selSetOpaque, cast(ObjcBool)0);
        msgSendObj(nsWindow, selSetBackgroundColor, clearColor);
        // Shadow darkens transparent edge pixels; disable by default.
        msgSendBool(nsWindow, selSetHasShadow, cast(ObjcBool)0);

        size_t touchedViews = 0;
        size_t touchedLayers = 0;

        void applyLayerTreeTransparency(ObjcId layer) {
            if (layer is null) return;
            touchedLayers++;
            msgSendBool(layer, selSetOpaque, cast(ObjcBool)0);
            if (clearCg !is null) {
                msgSendObj(layer, selSetBackgroundColor, clearCg);
            }
            auto sublayers = msgSendId(layer, selSublayers);
            if (sublayers is null) return;
            auto subCount = msgSendULong(sublayers, selCount);
            foreach (i; 0 .. subCount) {
                auto sublayer = msgSendIndexObj(sublayers, selObjectAtIndex, cast(ulong)i);
                applyLayerTreeTransparency(sublayer);
            }
        }

        auto applyViewTransparency = (ObjcId view) {
            if (view is null) return;
            touchedViews++;
            msgSendBool(view, selSetWantsLayer, cast(ObjcBool)1);
            msgSendBool(view, selSetOpaque, cast(ObjcBool)0);
            auto layer = msgSendId(view, selLayer);
            applyLayerTreeTransparency(layer);
        };

        auto contentView = msgSendId(nsWindow, selContentView);
        applyViewTransparency(contentView);
        if (contentView !is null) {
            auto subviews = msgSendId(contentView, selSubviews);
            if (subviews !is null) {
                auto subCount = msgSendULong(subviews, selCount);
                foreach (i; 0 .. subCount) {
                    auto subview = msgSendIndexObj(subviews, selObjectAtIndex, cast(ulong)i);
                    applyViewTransparency(subview);
                }
            }
        }

        // OpenGL path only: request non-opaque context surface explicitly when available.
        version (EnableVulkanBackend) {
        } else {
            if (contentView !is null) {
                auto hasOpenGLContext = msgSendBoolSel(contentView, selRespondsToSelector, selOpenGLContext);
                if (hasOpenGLContext != 0) {
                    auto glctx = msgSendId(contentView, selOpenGLContext);
                    if (glctx !is null) {
                        enum NSOpenGLCPSurfaceOpacity = 236;
                        int zero = 0;
                        msgSendSetValues(glctx, selSetValuesForParameter, &zero, NSOpenGLCPSurfaceOpacity);
                    }
                }
            }
        }

        debugLog(debugFn, "[transparent] macOS: applied non-opaque settings views=" ~ touchedViews.to!string ~ " layers=" ~ touchedLayers.to!string);
    }

    void setWindowMousePassthrough(SDL_Window* window, bool enabled, void function(string) debugFn = null) {
        if (window is null) return;

        auto objcHandle = dlopen("/usr/lib/libobjc.A.dylib".toStringz, RTLD_NOW | RTLD_LOCAL);
        if (objcHandle is null) {
            debugLog(debugFn, "[input-pass] macOS: failed to open /usr/lib/libobjc.A.dylib");
            return;
        }

        auto selRegisterName = cast(ObjcRegisterSelFn)dlsym(objcHandle, "sel_registerName".toStringz);
        auto objcMsgSendRaw = dlsym(objcHandle, "objc_msgSend".toStringz);
        if (selRegisterName is null || objcMsgSendRaw is null) {
            debugLog(debugFn, "[input-pass] macOS: objc runtime symbols not found");
            return;
        }

        auto msgSendBool = cast(MsgSendBoolFn)objcMsgSendRaw;
        auto props = SDL_GetWindowProperties(window);
        auto nsWindow = cast(ObjcId)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (nsWindow is null) {
            debugLog(debugFn, "[input-pass] macOS: nsWindow is null");
            return;
        }

        auto selSetIgnoresMouseEvents = selRegisterName("setIgnoresMouseEvents:".toStringz);
        if (selSetIgnoresMouseEvents is null) {
            debugLog(debugFn, "[input-pass] macOS: selector lookup failed");
            return;
        }

        msgSendBool(nsWindow, selSetIgnoresMouseEvents, enabled ? cast(ObjcBool)1 : cast(ObjcBool)0);
        debugLog(debugFn, "[input-pass] macOS: ignoresMouseEvents=" ~ (enabled ? "true" : "false"));
    }
}
