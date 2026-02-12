module uilib.windows;

version (Windows) {
    import bindbc.sdl;
    import core.sys.windows.windows : HWND, BOOL, BYTE, DWORD, LONG, LONG_PTR, HRGN, HRESULT,
        GWL_EXSTYLE, WS_EX_LAYERED, LWA_COLORKEY,
        GetWindowLongPtrW, SetWindowLongPtrW, SetLayeredWindowAttributes;
    import std.string : toStringz;

    pragma(lib, "dwmapi");

    struct DWM_BLURBEHIND {
        DWORD dwFlags;
        BOOL fEnable;
        HRGN hRgnBlur;
        BOOL fTransitionOnMaximized;
    }

    struct MARGINS {
        LONG cxLeftWidth;
        LONG cxRightWidth;
        LONG cyTopHeight;
        LONG cyBottomHeight;
    }

    enum DWM_BB_ENABLE = 0x00000001;
    extern (Windows) HRESULT DwmExtendFrameIntoClientArea(HWND hWnd, const(MARGINS)* pMarInset);
    extern (Windows) HRESULT DwmEnableBlurBehindWindow(HWND hWnd, const(DWM_BLURBEHIND)* pBlurBehind);

    enum WindowsTransparencyMode {
        ColorKey,
        Dwm,
    }

    WindowsTransparencyMode windowsTransparencyMode() {
        version (EnableVulkanBackend) {
            return WindowsTransparencyMode.Dwm;
        } else {
            return WindowsTransparencyMode.ColorKey;
        }
    }

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

        auto mode = windowsTransparencyMode();
        bool defaultDwmBlurBehind = true;
        bool useDwmBlurBehind = (mode == WindowsTransparencyMode.Dwm) &&
            defaultDwmBlurBehind;

        auto props = SDL_GetWindowProperties(window);
        auto hwnd = cast(HWND)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
        if (hwnd !is null) {
            if (mode == WindowsTransparencyMode.ColorKey) {
                auto exStyle = cast(LONG_PTR)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
                auto nextStyle = exStyle | WS_EX_LAYERED;
                if (nextStyle != exStyle) {
                    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, nextStyle);
                }
                // RGB(255, 0, 255) becomes fully transparent. Use full-intensity key to avoid
                // colorspace/quantization mismatches (notably Vulkan + sRGB swapchains).
                DWORD colorKey = (cast(DWORD)255 << 16) | cast(DWORD)255;
                SetLayeredWindowAttributes(hwnd, colorKey, cast(BYTE)255, LWA_COLORKEY);
                debugLog(debugFn, "[transparent] windows: applied layered colorkey mode");
            } else {
                // DWM mode: avoid layered colorkey path, let compositor use swapchain alpha.
                auto exStyle = cast(LONG_PTR)GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
                auto nextStyle = exStyle & ~cast(LONG_PTR)WS_EX_LAYERED;
                if (nextStyle != exStyle) {
                    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, nextStyle);
                }
                // Extend frame over the whole client area so backbuffer alpha can be composed.
                MARGINS margins = MARGINS.init;
                margins.cxLeftWidth = -1;
                margins.cxRightWidth = -1;
                margins.cyTopHeight = -1;
                margins.cyBottomHeight = -1;
                DwmExtendFrameIntoClientArea(hwnd, &margins);
            }

            if (mode == WindowsTransparencyMode.Dwm && useDwmBlurBehind) {
                DWM_BLURBEHIND bb = DWM_BLURBEHIND.init;
                bb.dwFlags = DWM_BB_ENABLE;
                bb.fEnable = 1;
                DwmEnableBlurBehindWindow(hwnd, &bb);
                debugLog(debugFn, "[transparent] windows: applied layered + dwm blur-behind");
            } else if (mode == WindowsTransparencyMode.Dwm) {
                debugLog(debugFn, "[transparent] windows: applied layered alpha-only (no DWM blur)");
            }
        }
    }
}
