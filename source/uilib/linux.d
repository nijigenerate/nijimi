module uilib.linux;

version (linux) {
    import bindbc.sdl;
    import core.stdc.stdint : uint32_t;
    import core.sys.posix.dlfcn : dlopen, dlsym, RTLD_NOW, RTLD_LOCAL;
    import std.string : toStringz;

    alias XDisplay = void;
    alias XWindow = ulong;
    alias XAtom = ulong;
    alias XBool = int;

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

    enum PropModeReplace = 0;

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
}
