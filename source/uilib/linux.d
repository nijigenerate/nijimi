module uilib.linux;

version (linux) {
    import bindbc.sdl;
    import core.stdc.stdint : int16_t, uint16_t;
    import core.stdc.stdint : uint32_t;
    import core.sys.posix.dlfcn : dlopen, dlsym, RTLD_NOW, RTLD_LOCAL;
    import std.conv : to;
    import std.string : toStringz;

    alias XDisplay = void;
    alias XWindow = ulong;
    alias XAtom = ulong;
    alias XBool = int;
    struct XRectangle {
        int16_t x;
        int16_t y;
        uint16_t width;
        uint16_t height;
    }

    alias XInternAtomFn = XAtom function(XDisplay* display, const(char)* atom_name, XBool only_if_exists);
    alias XChangePropertyFn = int function(XDisplay* display,
                                           XWindow w,
                                           XAtom property,
                                           XAtom type,
                                           int format,
                                           int mode,
                                           const(ubyte)* data,
                                           int nelements);
    alias XFlushFn = int function(XDisplay* display);
    alias XShapeCombineRectanglesFn = int function(XDisplay* display,
                                                   XWindow dest,
                                                   int destKind,
                                                   int xOff,
                                                   int yOff,
                                                   XRectangle* rectangles,
                                                   int n_rectangles,
                                                   int op,
                                                   int ordering);

    enum PropModeReplace = 0;
    enum ShapeSet = 0;
    enum ShapeInput = 2;
    enum YXBanded = 0;

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

        auto props = SDL_GetWindowProperties(window);
        auto display = cast(XDisplay*)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
        auto xwindow = cast(XWindow)SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        if (display is null || xwindow == 0) return;

        auto x11 = dlopen("libX11.so.6".toStringz, RTLD_NOW | RTLD_LOCAL);
        if (x11 is null) return;

        auto xInternAtom = cast(XInternAtomFn)dlsym(x11, "XInternAtom".toStringz);
        auto xChangeProperty = cast(XChangePropertyFn)dlsym(x11, "XChangeProperty".toStringz);
        auto xFlush = cast(XFlushFn)dlsym(x11, "XFlush".toStringz);
        if (xInternAtom is null || xChangeProperty is null || xFlush is null) return;

        auto atomCardinal = xInternAtom(display, "CARDINAL".toStringz, 0);
        if (atomCardinal == 0) return;

        // Explicitly keep compositor path enabled so alpha visuals are respected.
        auto atomBypass = xInternAtom(display, "_NET_WM_BYPASS_COMPOSITOR".toStringz, 0);
        if (atomBypass != 0) {
            uint32_t bypass = 0;
            xChangeProperty(display,
                            xwindow,
                            atomBypass,
                            atomCardinal,
                            32,
                            PropModeReplace,
                            cast(const(ubyte)*)&bypass,
                            1);
        }

        // Keep whole-window opacity at 1.0; per-pixel alpha still comes from rendering.
        auto atomOpacity = xInternAtom(display, "_NET_WM_WINDOW_OPACITY".toStringz, 0);
        if (atomOpacity != 0) {
            uint32_t opacity = uint32_t.max;
            xChangeProperty(display,
                            xwindow,
                            atomOpacity,
                            atomCardinal,
                            32,
                            PropModeReplace,
                            cast(const(ubyte)*)&opacity,
                            1);
        }

        xFlush(display);
        debugLog(debugFn, "[transparent] linux-x11: applied compositor/opacity window properties");
    }

    void setWindowMousePassthrough(SDL_Window* window, bool enabled, void function(string) debugFn = null) {
        if (window is null) return;

        auto props = SDL_GetWindowProperties(window);
        auto display = cast(XDisplay*)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
        auto xwindow = cast(XWindow)SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        if (display is null || xwindow == 0) {
            debugLog(debugFn, "[input-pass] linux: no X11 window handle (Wayland or unsupported backend)");
            return;
        }

        auto xext = dlopen("libXext.so.6".toStringz, RTLD_NOW | RTLD_LOCAL);
        if (xext is null) {
            xext = dlopen("libXext.so".toStringz, RTLD_NOW | RTLD_LOCAL);
        }
        if (xext is null) {
            debugLog(debugFn, "[input-pass] linux-x11: failed to open libXext");
            return;
        }

        auto xshapeCombineRectangles = cast(XShapeCombineRectanglesFn)dlsym(xext, "XShapeCombineRectangles".toStringz);
        auto x11 = dlopen("libX11.so.6".toStringz, RTLD_NOW | RTLD_LOCAL);
        if (x11 is null) {
            x11 = dlopen("libX11.so".toStringz, RTLD_NOW | RTLD_LOCAL);
        }
        if (xshapeCombineRectangles is null || x11 is null) {
            debugLog(debugFn, "[input-pass] linux-x11: required X11/XShape symbols unavailable");
            return;
        }

        auto xFlush = cast(XFlushFn)dlsym(x11, "XFlush".toStringz);
        if (xFlush is null) {
            debugLog(debugFn, "[input-pass] linux-x11: XFlush symbol unavailable");
            return;
        }

        if (enabled) {
            xshapeCombineRectangles(display,
                                    xwindow,
                                    ShapeInput,
                                    0,
                                    0,
                                    null,
                                    0,
                                    ShapeSet,
                                    YXBanded);
        } else {
            int windowW = 0;
            int windowH = 0;
            SDL_GetWindowSize(window, &windowW, &windowH);
            if (windowW <= 0 || windowH <= 0) return;
            XRectangle rect;
            rect.x = 0;
            rect.y = 0;
            rect.width = cast(uint16_t)windowW;
            rect.height = cast(uint16_t)windowH;
            xshapeCombineRectangles(display,
                                    xwindow,
                                    ShapeInput,
                                    0,
                                    0,
                                    &rect,
                                    1,
                                    ShapeSet,
                                    YXBanded);
        }

        xFlush(display);
        debugLog(debugFn, "[input-pass] linux-x11: mouse passthrough=" ~ enabled.to!string);
    }
}
