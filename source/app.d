module app;

import core.time : MonoTime, Duration, seconds;
import std.conv : to;
import std.exception : enforce;
import std.file : exists, getcwd;
import std.path : buildPath, dirName;
import std.stdio : writeln, writefln, stderr;
import std.string : fromStringz, toStringz, endsWith, toLower;
import std.math : exp, sqrt, isNaN;
import std.algorithm : clamp;

version (Windows) {
    import uilib.windows : configureTransparentWindow, WindowsTransparencyMode, windowsTransparencyMode;
    import core.sys.windows.windows : HMODULE, GetLastError, GetProcAddress;
} else version (OSX) {
    import uilib.osx : configureTransparentWindow;
} else version (linux) {
    import uilib.linux : configureTransparentWindow;
} else {
    void configureTransparentWindow(SDL_Window* window, void function(string) debugFn = null) {
    }
}

version (Posix) {
    import core.sys.posix.dlfcn : dlsym, dlerror;
}

import bindbc.sdl;
import uilib.sdl : configureWindowAlwaysOnTop, configureWindowBorderlessDesktop, configureWindowInputPolicy, initializeSystemTray, updateSystemTray, consumeTrayQuitRequested,
    consumeTrayToggleRequested, setSystemTrayWindowVisible, shutdownSystemTray;

version (EnableVulkanBackend) {
    import gfx = vulkan_backend;
    enum backendName = "vulkan";
    alias BackendInit = gfx.VulkanBackendInit;
} else version (EnableDirectXBackend) {
    import gfx = directx.directx_backend;
    enum backendName = "directx";
    alias BackendInit = gfx.DirectXBackendInit;
} else {
    import bindbc.opengl;
    import gfx = opengl.opengl_backend;
    import opengl.opengl_backend : currentRenderBackend, inClearColor, useColorKeyTransparency;
    enum backendName = "opengl";
    alias BackendInit = gfx.OpenGLBackendInit;
}
import core.runtime : Runtime;
enum MaskDrawableKind : uint { Part, Mask }

extern(C) alias NjgLogFn = void function(const(char)* message, size_t length, void* userData);

alias FnCreateRenderer = extern(C) gfx.NjgResult function(const gfx.UnityRendererConfig*, const gfx.UnityResourceCallbacks*, gfx.RendererHandle*);
alias FnDestroyRenderer = extern(C) void function(gfx.RendererHandle);
alias FnLoadPuppet = extern(C) gfx.NjgResult function(gfx.RendererHandle, const char*, gfx.PuppetHandle*);
alias FnUnloadPuppet = extern(C) gfx.NjgResult function(gfx.RendererHandle, gfx.PuppetHandle);
alias FnBeginFrame = extern(C) gfx.NjgResult function(gfx.RendererHandle, const gfx.FrameConfig*);
alias FnTickPuppet = extern(C) gfx.NjgResult function(gfx.PuppetHandle, double);
alias FnEmitCommands = extern(C) gfx.NjgResult function(gfx.RendererHandle, gfx.CommandQueueView*);
alias FnFlushCommandBuffer = extern(C) void function(gfx.RendererHandle);
alias FnSetLogCallback = extern(C) void function(NjgLogFn, void*);
alias FnRtInit = extern(C) void function();
alias FnRtTerm = extern(C) void function();
alias FnGetSharedBuffers = extern(C) gfx.NjgResult function(gfx.RendererHandle, gfx.SharedBufferSnapshot*);
alias FnSetPuppetScale = extern(C) gfx.NjgResult function(gfx.PuppetHandle, float, float);
alias FnSetPuppetTranslation = extern(C) gfx.NjgResult function(gfx.PuppetHandle, float, float);

struct UnityApi {
    void* lib;
    FnCreateRenderer createRenderer;
    FnDestroyRenderer destroyRenderer;
    FnLoadPuppet loadPuppet;
    FnUnloadPuppet unloadPuppet;
    FnBeginFrame beginFrame;
    FnTickPuppet tickPuppet;
    FnEmitCommands emitCommands;
    FnFlushCommandBuffer flushCommands;
    FnSetLogCallback setLogCallback;
    FnGetSharedBuffers getSharedBuffers;
    FnRtInit rtInit;
    FnRtTerm rtTerm;
    FnSetPuppetScale setPuppetScale;
    FnSetPuppetTranslation setPuppetTranslation;
}

string dynamicLookupError() {
    version (Windows) {
        return "GetProcAddress failed (GetLastError=" ~ to!string(GetLastError()) ~ ")";
    } else version (Posix) {
        auto err = dlerror();
        return err is null ? "dlsym failed" : fromStringz(err).idup;
    } else {
        return "symbol lookup failed";
    }
}

T loadSymbol(T)(void* lib, string name) {
    version (Windows) {
        auto sym = cast(T)GetProcAddress(cast(HMODULE)lib, name.toStringz);
        enforce(sym !is null,
            "Failed to load symbol "~name~
            " from libnijilive-unity: " ~ dynamicLookupError());
        return sym;
    } else version (Posix) {
        auto sym = cast(T)dlsym(lib, name.toStringz);
        enforce(sym !is null,
            "Failed to load symbol "~name~" from libnijilive-unity: " ~ dynamicLookupError());
        return sym;
    } else {
        static assert(false, "Unsupported platform for dynamic symbol loading");
    }
}

T loadOptionalSymbol(T)(void* lib, string name) {
    version (Windows) {
        auto sym = cast(T)GetProcAddress(cast(HMODULE)lib, name.toStringz);
        if (sym is null) {
            writeln("Optional symbol missing: ", name, " (", dynamicLookupError(), ")");
        }
        return sym;
    } else version (Posix) {
        auto sym = cast(T)dlsym(lib, name.toStringz);
        if (sym is null) {
            writeln("Optional symbol missing: ", name, " (", dynamicLookupError(), ")");
        }
        return sym;
    } else {
        static assert(false, "Unsupported platform for dynamic symbol loading");
    }
}

UnityApi loadUnityApi(string libPath) {
    // Load via druntime to share the runtime instance with the DLL.
    auto lib = Runtime.loadLibrary(libPath);
    enforce(lib !is null, "Failed to load libnijilive-unity via Runtime.loadLibrary: "~libPath);
    UnityApi api;
    api.lib = lib;
    api.createRenderer = loadSymbol!FnCreateRenderer(lib, "njgCreateRenderer");
    api.destroyRenderer = loadSymbol!FnDestroyRenderer(lib, "njgDestroyRenderer");
    api.loadPuppet = loadSymbol!FnLoadPuppet(lib, "njgLoadPuppet");
    api.unloadPuppet = loadSymbol!FnUnloadPuppet(lib, "njgUnloadPuppet");
    api.beginFrame = loadSymbol!FnBeginFrame(lib, "njgBeginFrame");
    api.tickPuppet = loadSymbol!FnTickPuppet(lib, "njgTickPuppet");
    api.emitCommands = loadSymbol!FnEmitCommands(lib, "njgEmitCommands");
    api.flushCommands = loadSymbol!FnFlushCommandBuffer(lib, "njgFlushCommandBuffer");
    api.setLogCallback = loadOptionalSymbol!FnSetLogCallback(lib, "njgSetLogCallback");
    api.getSharedBuffers = loadSymbol!FnGetSharedBuffers(lib, "njgGetSharedBuffers");
    api.setPuppetScale = loadOptionalSymbol!FnSetPuppetScale(lib, "njgSetPuppetScale");
    api.setPuppetTranslation = loadOptionalSymbol!FnSetPuppetTranslation(lib, "njgSetPuppetTranslation");
    // Explicit runtime init/term provided by DLL.
    api.rtInit = loadOptionalSymbol!FnRtInit(lib, "njgRuntimeInit");
    api.rtTerm = loadOptionalSymbol!FnRtTerm(lib, "njgRuntimeTerm");
    return api;
}

extern(C) void logCallback(const(char)* msg, size_t len, void* userData) {
    if (msg is null || len == 0) return;
    writeln("[nijilive-unity] "~msg[0 .. len].idup);
}

string[] unityLibraryNames() {
    version (Windows) {
        return ["nijilive-unity.dll", "libnijilive-unity.dll"];
    } else version (linux) {
        return ["libnijilive-unity.so", "nijilive-unity.so"];
    } else version (OSX) {
        return ["libnijilive-unity.dylib", "nijilive-unity.dylib"];
    } else {
        return ["libnijilive-unity"];
    }
}

string resolvePuppetPath(string rawPath) {
    if (exists(rawPath)) return rawPath;

    string[] candidates;
    // Common typo: .inxd (directory-like typo) for .inx
    if (rawPath.endsWith(".inxd")) {
        candidates ~= rawPath[0 .. $ - 1]; // -> .inx
    }
    // Also try sibling package formats with same stem.
    if (rawPath.endsWith(".inx") || rawPath.endsWith(".inxd") || rawPath.endsWith(".inp")) {
        auto dot = rawPath.length - 1;
        while (dot > 0 && rawPath[dot] != '.') dot--;
        if (dot > 0) {
            auto stem = rawPath[0 .. dot];
            candidates ~= stem ~ ".inx";
            candidates ~= stem ~ ".inp";
        }
    }

    foreach (c; candidates) {
        if (exists(c)) return c;
    }
    enforce(false, "Puppet file not found: " ~ rawPath ~ " (tried: " ~ candidates.to!string ~ ")");
    return rawPath;
}

enum ToggleOption {
    Unspecified,
    Enabled,
    Disabled,
}

struct CliOptions {
    bool isTest = false;
    int framesFlag = -1;
    ToggleOption transparentWindow = ToggleOption.Unspecified;
    ToggleOption transparentRetry = ToggleOption.Unspecified;
    ToggleOption transparentDebug = ToggleOption.Unspecified;
    float dragSensitivity = 1.0f;
    string[] positional;
}

private __gshared bool gTransparentDebugLog = false;

private void transparentDebug(string message) {
    if (!gTransparentDebugLog) return;
    stderr.writeln(message);
    stderr.flush();
}


private bool resolveToggle(ToggleOption cliValue, bool defaultValue) {
    final switch (cliValue) {
        case ToggleOption.Enabled:
            return true;
        case ToggleOption.Disabled:
            return false;
        case ToggleOption.Unspecified:
            return defaultValue;
    }
}

private struct Vec4f {
    float x;
    float y;
    float z;
    float w;
}

private Vec4f mulMat4Vec4(ref const(float[16]) m, float x, float y, float z, float w) {
    // Njg packet matrices are laid out column-major (OpenGL convention).
    Vec4f r;
    r.x = m[0] * x + m[4] * y + m[8]  * z + m[12] * w;
    r.y = m[1] * x + m[5] * y + m[9]  * z + m[13] * w;
    r.z = m[2] * x + m[6] * y + m[10] * z + m[14] * w;
    r.w = m[3] * x + m[7] * y + m[11] * z + m[15] * w;
    return r;
}

private struct PuppetScreenBounds {
    bool valid;
    float minX;
    float minY;
    float maxX;
    float maxY;

    void clear() {
        valid = false;
        minX = minY = maxX = maxY = 0;
    }

    void include(float x, float y) {
        if (!valid) {
            minX = maxX = x;
            minY = maxY = y;
            valid = true;
            return;
        }
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
    }

    bool contains(float x, float y) const {
        if (!valid) return false;
        return x >= minX && x <= maxX && y >= minY && y <= maxY;
    }
}

private struct DragLinearMap {
    bool valid;
    float m00;
    float m01;
    float m10;
    float m11;
    float c0;
    float c1;
}

private bool clipDeltaToPuppetDelta(in DragLinearMap map, float clipDx, float clipDy, out float tx, out float ty) {
    tx = 0;
    ty = 0;
    if (!map.valid) return false;
    float det = map.m00 * map.m11 - map.m01 * map.m10;
    if (det > -1e-7f && det < 1e-7f) return false;
    float invDet = 1.0f / det;
    tx = ( map.m11 * clipDx - map.m01 * clipDy) * invDet;
    ty = (-map.m10 * clipDx + map.m00 * clipDy) * invDet;
    return !(isNaN(tx) || isNaN(ty));
}

private bool clipPointToPuppetPoint(in DragLinearMap map, float clipX, float clipY, out float px, out float py) {
    px = 0;
    py = 0;
    if (!map.valid) return false;
    float det = map.m00 * map.m11 - map.m01 * map.m10;
    if (det > -1e-7f && det < 1e-7f) return false;
    float rhsX = clipX - map.c0;
    float rhsY = clipY - map.c1;
    float invDet = 1.0f / det;
    px = ( map.m11 * rhsX - map.m01 * rhsY) * invDet;
    py = (-map.m10 * rhsX + map.m00 * rhsY) * invDet;
    return !(isNaN(px) || isNaN(py));
}

private bool screenToPuppetPoint(in DragLinearMap map,
                                 float mouseX,
                                 float mouseY,
                                 int windowW,
                                 int windowH,
                                 int drawableW,
                                 int drawableH,
                                 out float px,
                                 out float py) {
    px = 0;
    py = 0;
    if (!map.valid) return false;
    if (windowW <= 0 || windowH <= 0 || drawableW <= 0 || drawableH <= 0) return false;

    float sx = mouseX * (cast(float)drawableW / cast(float)windowW);
    float sy = mouseY * (cast(float)drawableH / cast(float)windowH);
    float clipX = 2.0f * (sx / cast(float)drawableW) - 1.0f;
    float clipY = 1.0f - 2.0f * (sy / cast(float)drawableH);
    return clipPointToPuppetPoint(map, clipX, clipY, px, py);
}

private void includePartPacketBounds(ref PuppetScreenBounds bounds,
                                     ref DragLinearMap dragMap,
                                     ref bool dragMapSet,
                                     ref const(gfx.NjgPartDrawPacket) packet,
                                     ref const(gfx.SharedBufferSnapshot) snapshot,
                                     int windowW,
                                     int windowH) {
    if (!packet.renderable || packet.indices is null || packet.indexCount == 0 || packet.vertexCount == 0) {
        return;
    }
    if (windowW <= 0 || windowH <= 0) return;
    if (snapshot.vertices.data is null || snapshot.vertices.length == 0) return;

    if (!dragMapSet) {
        dragMap.valid = true;
        dragMap.m00 = packet.renderMatrix[0];
        dragMap.m01 = packet.renderMatrix[4];
        dragMap.m10 = packet.renderMatrix[1];
        dragMap.m11 = packet.renderMatrix[5];
        dragMap.c0 = packet.renderMatrix[12];
        dragMap.c1 = packet.renderMatrix[13];
        dragMapSet = true;
    }

    foreach (i; 0 .. packet.indexCount) {
        auto vi = cast(size_t)packet.indices[i];
        if (vi >= packet.vertexCount) continue;

        auto vxBase = packet.vertexOffset + vi * packet.vertexAtlasStride;
        if (vxBase + 1 >= snapshot.vertices.length) continue;
        float vx = snapshot.vertices.data[vxBase];
        float vy = snapshot.vertices.data[vxBase + 1];

        float dx = 0;
        float dy = 0;
        auto dBase = packet.deformOffset + vi * packet.deformAtlasStride;
        if (snapshot.deform.data !is null && dBase + 1 < snapshot.deform.length) {
            dx = snapshot.deform.data[dBase];
            dy = snapshot.deform.data[dBase + 1];
        }

        float px = vx - packet.origin.x + dx;
        float py = vy - packet.origin.y + dy;
        auto clip = mulMat4Vec4(packet.renderMatrix, px, py, 0, 1);
        if (clip.w == 0 || isNaN(clip.w)) continue;
        float invW = 1.0f / clip.w;
        float ndcX = clip.x * invW;
        float ndcY = clip.y * invW;

        float sx = (ndcX * 0.5f + 0.5f) * cast(float)windowW;
        float sy = (1.0f - (ndcY * 0.5f + 0.5f)) * cast(float)windowH;
        bounds.include(sx, sy);
    }
}

private void updatePuppetScreenBounds(ref PuppetScreenBounds bounds,
                                      ref DragLinearMap dragMap,
                                      ref const(gfx.CommandQueueView) view,
                                      ref const(gfx.SharedBufferSnapshot) snapshot,
                                      int windowW,
                                      int windowH) {
    bounds.clear();
    dragMap.valid = false;
    bool dragMapSet = false;
    if (view.commands is null || view.count == 0) return;

    auto commands = view.commands[0 .. view.count];
    foreach (cmd; commands) {
        switch (cmd.kind) {
            case gfx.NjgRenderCommandKind.DrawPart:
                includePartPacketBounds(bounds, dragMap, dragMapSet, cmd.partPacket, snapshot, windowW, windowH);
                break;
            case gfx.NjgRenderCommandKind.ApplyMask:
                if (cmd.maskApplyPacket.kind == gfx.MaskDrawableKind.Part) {
                    includePartPacketBounds(bounds, dragMap, dragMapSet, cmd.maskApplyPacket.partPacket, snapshot, windowW, windowH);
                }
                break;
            default:
                break;
        }
    }
}

private CliOptions parseCliOptions(string[] args) {
    CliOptions out_;
    for (size_t i = 1; i < args.length; ++i) {
        auto arg = args[i];
        if (arg == "--test") {
            out_.isTest = true;
            continue;
        }
        if (arg == "--frames") {
            if (i + 1 < args.length) {
                import std.ascii : isDigit;
                import std.algorithm : all;
                auto maybe = args[i + 1];
                if (maybe.all!isDigit) {
                    out_.framesFlag = maybe.to!int;
                }
                ++i;
            }
            continue;
        }
        if (arg == "--transparent-window") {
            out_.transparentWindow = ToggleOption.Enabled;
            continue;
        }
        if (arg == "--no-transparent-window") {
            out_.transparentWindow = ToggleOption.Disabled;
            continue;
        }
        if (arg == "--transparent-window-retry") {
            out_.transparentRetry = ToggleOption.Enabled;
            continue;
        }
        if (arg == "--no-transparent-window-retry") {
            out_.transparentRetry = ToggleOption.Disabled;
            continue;
        }
        if (arg == "--transparent-debug") {
            out_.transparentDebug = ToggleOption.Enabled;
            continue;
        }
        if (arg == "--no-transparent-debug") {
            out_.transparentDebug = ToggleOption.Disabled;
            continue;
        }
        if (arg == "--drag-sensitivity") {
            if (i + 1 < args.length) {
                try {
                    out_.dragSensitivity = args[i + 1].to!float;
                } catch (Exception) {}
                ++i;
            }
            continue;
        }
        out_.positional ~= arg;
    }
    return out_;
}

void main(string[] args) {
    auto cli = parseCliOptions(args);
    bool isTest = cli.isTest;
    string[] positional = cli.positional;
    int framesFlag = cli.framesFlag;
    // Defaults for test mode
    int testMaxFrames = 5;
    auto testTimeout = 5.seconds;
    if (positional.length < 1) {
        writeln("Usage: nijimi <puppet.inp|puppet.inx> [width height] [--test] [--transparent-window|--no-transparent-window] [--transparent-window-retry|--no-transparent-window-retry] [--transparent-debug] [--drag-sensitivity <value>]");
        return;
    }
    string puppetPath = resolvePuppetPath(positional[0]);
    import std.algorithm : all;
    import std.ascii : isDigit;
    bool hasWidth = positional.length > 1 && positional[1].all!isDigit;
    bool hasHeight = positional.length > 2 && positional[2].all!isDigit;
    int width = hasWidth ? positional[1].to!int : 1280;
    int height = hasHeight ? positional[2].to!int : 720;
    if (framesFlag > 0) testMaxFrames = framesFlag;
    gTransparentDebugLog = resolveToggle(cli.transparentDebug, false);
    bool transparentWindowEnabled = resolveToggle(cli.transparentWindow, true);
    bool transparentWindowRetry = resolveToggle(cli.transparentRetry, true);
    version (Windows) {
        version (EnableDirectXBackend) {
        } else {
            version (EnableVulkanBackend) {
                if (windowsTransparencyMode() == WindowsTransparencyMode.ColorKey) {
                    // Match Windows colorkey (RGB 255,0,255) so background pixels become fully transparent.
                    gfx.inClearColor = typeof(gfx.inClearColor)(1.0f, 0.0f, 1.0f, 1.0f);
                } else {
                    // DWM composition path expects transparent background in swapchain.
                    gfx.inClearColor = typeof(gfx.inClearColor)(0.0f, 0.0f, 0.0f, 0.0f);
                }
            } else {
                // OpenGL colorkey path: keep offscreen transparent; convert to colorkey only at present pass.
                inClearColor = typeof(inClearColor)(0.0f, 0.0f, 0.0f, 0.0f);
                useColorKeyTransparency = (windowsTransparencyMode() == WindowsTransparencyMode.ColorKey);
            }
        }
    }

    writefln("nijimi (%s DLL) start: file=%s, size=%sx%s (test=%s frames=%s timeout=%s)",
        backendName, puppetPath, width, height, isTest, testMaxFrames, testTimeout);
    version (Windows) {
        auto mode = windowsTransparencyMode();
        writefln("Windows transparency mode: %s", mode == WindowsTransparencyMode.ColorKey ? "colorkey" : "dwm");
    }
    transparentDebug("[transparent] option enabled=" ~ transparentWindowEnabled.to!string ~ " retry=" ~ transparentWindowRetry.to!string);

    import bindbc.loader : LoadMsg;
    auto sdlSupport = loadSDL();
    if (sdlSupport == LoadMsg.noLibrary || sdlSupport == LoadMsg.badLibrary) {
        version (OSX) {
            sdlSupport = loadSDL("/opt/homebrew/lib/libSDL3.0.dylib");
        }
    }
    enforce(sdlSupport == LoadMsg.success, "Failed to load SDL3");
    SDL_SetMainReady();
    enforce(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS),
        "SDL_Init failed: " ~ (SDL_GetError() is null ? "" : fromStringz(SDL_GetError()).idup));

    SDL_Window* hostWindow = null;
    void* hostGlContext = null;
    BackendInit backendInit = void;
    scope (exit) {
        shutdownSystemTray();
        version (EnableDirectXBackend) {
            gfx.shutdownDirectXBackend(backendInit);
        } else version (EnableVulkanBackend) {
            if (backendInit.backend !is null) backendInit.backend.dispose();
        }
        if (hostGlContext !is null) {
            SDL_GL_DestroyContext(cast(SDL_GLContext)hostGlContext);
            hostGlContext = null;
        }
        if (hostWindow !is null) {
            SDL_DestroyWindow(hostWindow);
            hostWindow = null;
        }
        SDL_Quit();
    }

    version (EnableVulkanBackend) {
        import erupted : VkInstance, VkSurfaceKHR;

        hostWindow = SDL_CreateWindow("nijimi",
            width, height,
            SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
        enforce(hostWindow !is null, "SDL_CreateWindow failed (vulkan)");
        configureWindowBorderlessDesktop(hostWindow, &transparentDebug);
        configureWindowAlwaysOnTop(hostWindow, true);
        configureWindowInputPolicy(hostWindow, false, &transparentDebug);

        int drawableW = width;
        int drawableH = height;
        SDL_GetWindowSizeInPixels(hostWindow, &drawableW, &drawableH);

        uint extCount = 0;
        auto extPtrs = SDL_Vulkan_GetInstanceExtensions(&extCount);
        enforce(extPtrs !is null && extCount > 0, "SDL_Vulkan_GetInstanceExtensions failed");
        string[] instExts;
        instExts.length = extCount;
        foreach (i; 0 .. extCount) {
            instExts[i] = fromStringz(extPtrs[i]).idup;
        }

        gfx.VulkanInitOptions opts;
        opts.windowHandle = cast(void*)hostWindow;
        opts.drawableW = drawableW;
        opts.drawableH = drawableH;
        opts.instanceExtensions = instExts;
        opts.ownsSurface = true;
        opts.surfaceFactory = (VkInstance instance, void* userData) {
            auto w = cast(SDL_Window*)userData;
            ulong outSurface = 0;
            auto ok = SDL_Vulkan_CreateSurface(w, instance, null, &outSurface);
            return ok ? cast(VkSurfaceKHR)outSurface : VkSurfaceKHR.init;
        };
        opts.surfaceFactoryUserData = cast(void*)hostWindow;
        backendInit = gfx.initVulkanBackend(width, height, isTest, opts);
        backendInit.drawableW = drawableW;
        backendInit.drawableH = drawableH;
    } else version (EnableDirectXBackend) {
        import core.sys.windows.windows : HWND;

        hostWindow = SDL_CreateWindow("nijimi",
            width, height,
            SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
        enforce(hostWindow !is null, "SDL_CreateWindow failed (directx)");
        configureWindowBorderlessDesktop(hostWindow, &transparentDebug);
        configureWindowAlwaysOnTop(hostWindow, true);
        configureWindowInputPolicy(hostWindow, false, &transparentDebug);

        auto props = SDL_GetWindowProperties(hostWindow);
        auto hwnd = cast(HWND)SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
        enforce(hwnd !is null, "Failed to get HWND from SDL window properties");

        int drawableW = width;
        int drawableH = height;
        SDL_GetWindowSizeInPixels(hostWindow, &drawableW, &drawableH);

        gfx.DirectXInitOptions opts;
        opts.windowHandle = cast(void*)hostWindow;
        opts.hwnd = hwnd;
        opts.drawableW = drawableW;
        opts.drawableH = drawableH;
        opts.userData = cast(void*)hostWindow;
        backendInit = gfx.initDirectXBackend(width, height, isTest, opts);
        backendInit.drawableW = drawableW;
        backendInit.drawableH = drawableH;
    } else {
        hostWindow = SDL_CreateWindow("nijimi",
            width, height,
            SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
        enforce(hostWindow !is null, "SDL_CreateWindow failed (opengl)");
        configureWindowBorderlessDesktop(hostWindow, &transparentDebug);
        configureWindowAlwaysOnTop(hostWindow, true);
        configureWindowInputPolicy(hostWindow, false, &transparentDebug);

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
        SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
        hostGlContext = cast(void*)SDL_GL_CreateContext(hostWindow);
        enforce(hostGlContext !is null, "SDL_GL_CreateContext failed");
        SDL_GL_MakeCurrent(hostWindow, cast(SDL_GLContext)hostGlContext);
        SDL_GL_SetSwapInterval(1);

        int drawableW = width;
        int drawableH = height;
        SDL_GetWindowSizeInPixels(hostWindow, &drawableW, &drawableH);

        gfx.OpenGLInitOptions opts;
        opts.windowHandle = cast(void*)hostWindow;
        opts.glContextHandle = hostGlContext;
        opts.drawableW = drawableW;
        opts.drawableH = drawableH;
        opts.userData = cast(void*)hostWindow;
        backendInit = gfx.initOpenGLBackend(width, height, isTest, opts);
        backendInit.drawableW = drawableW;
        backendInit.drawableH = drawableH;
    }

    bool canApplyTransparentWindow = transparentWindowEnabled;
    version (Windows) {
        version (EnableVulkanBackend) {
            if (transparentWindowEnabled && !backendInit.backend.supportsPerPixelTransparency()) {
                writeln("[transparent] windows+vulkan: swapchain composite alpha is OPAQUE; skip transparent window setup.");
                canApplyTransparentWindow = false;
            }
        }
    }
    if (canApplyTransparentWindow) {
        configureTransparentWindow(hostWindow, &transparentDebug);
    }
    initializeSystemTray(hostWindow, &transparentDebug);
    bool trayWindowVisible = true;
    setSystemTrayWindowVisible(trayWindowVisible);
    bool transparencyRetryPending = canApplyTransparentWindow && transparentWindowRetry;

    // Load the Unity-facing DLL from a nearby nijilive build.
    string exeDir = getcwd();
    auto libNames = unityLibraryNames();
    string[] libCandidates;
    foreach (name; libNames) {
        libCandidates ~= buildPath(exeDir, name);
        libCandidates ~= buildPath(exeDir, "..", "nijilive", name);
        libCandidates ~= buildPath(exeDir, "..", "..", "nijilive", name);
        libCandidates ~= buildPath("..", "nijilive", name);
    }
    string libPath;
    foreach (c; libCandidates) {
        if (exists(c)) {
            libPath = c;
            break;
        }
    }
    enforce(libPath.length > 0, "Could not find nijilive unity library (searched: "~libCandidates.to!string~")");
    auto api = loadUnityApi(libPath);
    // Do not unload the shared runtime-bound DLL during process lifetime.
    if (api.rtInit !is null) api.rtInit();
    if (api.setLogCallback !is null) {
        api.setLogCallback(&logCallback, null);
    }

    gfx.UnityRendererConfig rendererCfg;
    rendererCfg.viewportWidth = backendInit.drawableW;
    rendererCfg.viewportHeight = backendInit.drawableH;
    gfx.RendererHandle renderer;
    auto createRendererRes = api.createRenderer(&rendererCfg, &backendInit.callbacks, &renderer);
    enforce(createRendererRes == gfx.NjgResult.Ok,
        "njgCreateRenderer failed: " ~ createRendererRes.to!string);

    gfx.PuppetHandle puppet;
    auto loadPuppetRes = api.loadPuppet(renderer, puppetPath.toStringz, &puppet);
    enforce(loadPuppetRes == gfx.NjgResult.Ok,
        "njgLoadPuppet failed: " ~ loadPuppetRes.to!string ~ " path=" ~ puppetPath);
    gfx.FrameConfig frameCfg;
    frameCfg.viewportWidth = backendInit.drawableW;
    frameCfg.viewportHeight = backendInit.drawableH;
    version (EnableVulkanBackend) {
        backendInit.backend.setViewport(backendInit.drawableW, backendInit.drawableH);
    } else version (EnableDirectXBackend) {
        backendInit.backend.setViewport(backendInit.drawableW, backendInit.drawableH);
    } else {
        currentRenderBackend().setViewport(backendInit.drawableW, backendInit.drawableH);
    }
    float puppetScale = 0.12f;
    float puppetTranslateX = 0.0f;
    float puppetTranslateY = 0.0f;
    bool dragMoveActive = false;
    bool dragAnchorValid = false;
    float dragLastX = 0.0f;
    float dragLastY = 0.0f;
    float dragAnchorScreenX = 0.0f;
    float dragAnchorScreenY = 0.0f;
    float dragAnchorTranslationX = 0.0f;
    float dragAnchorTranslationY = 0.0f;
    PuppetScreenBounds puppetBounds = PuppetScreenBounds.init;
    DragLinearMap dragMap = DragLinearMap.init;

    // Apply initial scale (default 0.25) so that the view starts zoomed out.
    if (api.setPuppetScale !is null) {
        auto initScaleRes = api.setPuppetScale(puppet, puppetScale, puppetScale);
        if (initScaleRes != gfx.NjgResult.Ok) {
            writeln("njgSetPuppetScale initial apply failed: ", initScaleRes);
        }
    }

    bool autoWheel = false;
    int autoWheelInterval = 3;
    if (autoWheelInterval <= 0) autoWheelInterval = 3;
    int autoWheelPhaseTicks = 18;
    if (autoWheelPhaseTicks <= 0) autoWheelPhaseTicks = 18;
    int autoWheelY = 1;
    int autoWheelPhaseCount = 0;
    if (autoWheel) {
        writefln("Auto wheel enabled: interval=%s phaseTicks=%s startY=%s",
            autoWheelInterval, autoWheelPhaseTicks, autoWheelY);
    }
    float dragSensitivity = cli.dragSensitivity;
    if (dragSensitivity <= 0.0f) dragSensitivity = 1.0f;

    bool running = true;
    int frameCount = 0;
    MonoTime startTime = MonoTime.currTime;
    MonoTime prev = startTime;
    SDL_Event ev;

    while (running) {
        updateSystemTray();
        while (SDL_PollEvent(&ev) != 0) {
            switch (cast(uint)ev.type) {
                case SDL_EVENT_QUIT:
                    running = false;
                    break;
                case SDL_EVENT_KEY_DOWN:
                    if (ev.key.scancode == SDL_SCANCODE_ESCAPE) running = false;
                    break;
                case SDL_EVENT_WINDOW_RESIZED:
                case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
                    {
                        version (EnableVulkanBackend) {
                            SDL_GetWindowSizeInPixels(hostWindow, &backendInit.drawableW, &backendInit.drawableH);
                            frameCfg.viewportWidth = backendInit.drawableW;
                            frameCfg.viewportHeight = backendInit.drawableH;
                            backendInit.backend.setViewport(backendInit.drawableW, backendInit.drawableH);
                        } else version (EnableDirectXBackend) {
                            SDL_GetWindowSizeInPixels(hostWindow, &backendInit.drawableW, &backendInit.drawableH);
                            frameCfg.viewportWidth = backendInit.drawableW;
                            frameCfg.viewportHeight = backendInit.drawableH;
                            backendInit.backend.setViewport(backendInit.drawableW, backendInit.drawableH);
                        } else {
                            SDL_GetWindowSizeInPixels(hostWindow, &backendInit.drawableW, &backendInit.drawableH);
                            frameCfg.viewportWidth = backendInit.drawableW;
                            frameCfg.viewportHeight = backendInit.drawableH;
                            currentRenderBackend().setViewport(backendInit.drawableW, backendInit.drawableH);
                        }
                        if (canApplyTransparentWindow) {
                            // SDL may recreate native view/layer objects on resize.
                            // Re-apply transparency settings to keep alpha compositing active.
                            configureTransparentWindow(hostWindow, &transparentDebug);
                        }
                    }
                    break;
                case SDL_EVENT_WINDOW_SHOWN:
                    trayWindowVisible = true;
                    setSystemTrayWindowVisible(true);
                    break;
                case SDL_EVENT_WINDOW_HIDDEN:
                    trayWindowVisible = false;
                    setSystemTrayWindowVisible(false);
                    break;
                case SDL_EVENT_MOUSE_WHEEL:
                    // Scroll up to zoom in, down to zoom out. Use exponential step.
                    {
                        float step = 0.1f; // ~10% per notch
                        float factor = cast(float)exp(step * -ev.wheel.y);
                        puppetScale = clamp(puppetScale * factor, 0.1f, 10.0f);
                        if (api.setPuppetScale !is null) {
                            auto res = api.setPuppetScale(puppet, puppetScale, puppetScale);
                            if (res != gfx.NjgResult.Ok) {
                                writeln("njgSetPuppetScale failed: ", res);
                            }
                            if (dragMoveActive) {
                                // Scale changed while dragging: re-anchor on next motion with fresh transform.
                                dragAnchorValid = false;
                            }
                        }
                    }
                    break;
                case SDL_EVENT_MOUSE_BUTTON_DOWN:
                    if (ev.button.button == SDL_MouseButton.left) {
                        // Colorkey transparency on Windows generally forwards clicks only on visible pixels.
                        // Start drag unconditionally on left click so translation always responds.
                        dragMoveActive = true;
                        dragLastX = ev.button.x;
                        dragLastY = ev.button.y;
                        SDL_CaptureMouse(true);
                        dragAnchorValid = true;
                        dragAnchorScreenX = ev.button.x;
                        dragAnchorScreenY = ev.button.y;
                        dragAnchorTranslationX = puppetTranslateX;
                        dragAnchorTranslationY = puppetTranslateY;
                    }
                    break;
                case SDL_EVENT_MOUSE_BUTTON_UP:
                    if (ev.button.button == SDL_MouseButton.left) {
                        dragMoveActive = false;
                        dragAnchorValid = false;
                        SDL_CaptureMouse(false);
                    }
                    break;
                case SDL_EVENT_MOUSE_MOTION:
                    if (dragMoveActive && api.setPuppetTranslation !is null) {
                        if (!dragAnchorValid && dragMap.valid) {
                            dragAnchorValid = true;
                            dragAnchorScreenX = ev.motion.x;
                            dragAnchorScreenY = ev.motion.y;
                            dragAnchorTranslationX = puppetTranslateX;
                            dragAnchorTranslationY = puppetTranslateY;
                            dragLastX = ev.motion.x;
                            dragLastY = ev.motion.y;
                            break;
                        }

                        float dx = ev.motion.x - dragLastX;
                        float dy = ev.motion.y - dragLastY;
                        dragLastX = ev.motion.x;
                        dragLastY = ev.motion.y;

                        float tdx = dx * dragSensitivity;
                        float tdy = dy * dragSensitivity;
                        if (dragAnchorValid && dragMap.valid) {
                            int windowW = 0;
                            int windowH = 0;
                            int winDrawableW = 0;
                            int winDrawableH = 0;
                            SDL_GetWindowSize(hostWindow, &windowW, &windowH);
                            SDL_GetWindowSizeInPixels(hostWindow, &winDrawableW, &winDrawableH);
                            float anchorPx, anchorPy;
                            float nowPx, nowPy;
                            bool okAnchor = screenToPuppetPoint(dragMap, dragAnchorScreenX, dragAnchorScreenY,
                                windowW, windowH, winDrawableW, winDrawableH, anchorPx, anchorPy);
                            bool okNow = screenToPuppetPoint(dragMap, ev.motion.x, ev.motion.y,
                                windowW, windowH, winDrawableW, winDrawableH, nowPx, nowPy);
                            if (okAnchor && okNow) {
                                tdx = (nowPx - anchorPx) * dragSensitivity;
                                tdy = (nowPy - anchorPy) * dragSensitivity;
                                puppetTranslateX = dragAnchorTranslationX + tdx;
                                puppetTranslateY = dragAnchorTranslationY + tdy;
                            } else {
                                puppetTranslateX += tdx;
                                puppetTranslateY += tdy;
                            }
                        } else {
                            puppetTranslateX += tdx;
                            puppetTranslateY += tdy;
                        }
                        auto res = api.setPuppetTranslation(puppet, puppetTranslateX, puppetTranslateY);
                        if (res != gfx.NjgResult.Ok) {
                            writeln("njgSetPuppetTranslation failed: ", res);
                        }
                    }
                    break;
                default:
                    break;
            }
        }
        if (consumeTrayQuitRequested()) {
            running = false;
        }
        if (consumeTrayToggleRequested()) {
            if (trayWindowVisible) {
                SDL_HideWindow(hostWindow);
                trayWindowVisible = false;
                setSystemTrayWindowVisible(false);
            } else {
                SDL_ShowWindow(hostWindow);
                SDL_RaiseWindow(hostWindow);
                trayWindowVisible = true;
                setSystemTrayWindowVisible(true);
            }
        }
        if (!running) {
            break;
        }

        if (autoWheel && api.setPuppetScale !is null && frameCount > 0 &&
            (frameCount % autoWheelInterval) == 0) {
            int wheelY = autoWheelY;
            autoWheelPhaseCount++;
            if (autoWheelPhaseCount >= autoWheelPhaseTicks) {
                autoWheelPhaseCount = 0;
                autoWheelY = -autoWheelY;
            }
            // Match SDL_MOUSEWHEEL handling path exactly.
            float step = 0.1f;
            float factor = cast(float)exp(step * -wheelY);
            puppetScale = clamp(puppetScale * factor, 0.1f, 10.0f);
            auto res = api.setPuppetScale(puppet, puppetScale, puppetScale);
            if (dragMoveActive) {
                dragAnchorValid = false;
            }
            writefln("Auto wheel frame=%s -> wheelY=%s scale=%s res=%s",
                frameCount, wheelY, puppetScale, res);
        }

        MonoTime now = MonoTime.currTime;
        Duration delta = now - prev;
        prev = now;
        double deltaSec = delta.total!"nsecs" / 1_000_000_000.0;

        enforce(api.beginFrame(renderer, &frameCfg) == gfx.NjgResult.Ok, "njgBeginFrame failed");
        enforce(api.tickPuppet(puppet, deltaSec) == gfx.NjgResult.Ok, "njgTickPuppet failed");

        gfx.CommandQueueView view;
        enforce(api.emitCommands(renderer, &view) == gfx.NjgResult.Ok, "njgEmitCommands failed");
        gfx.SharedBufferSnapshot snapshot;
        enforce(api.getSharedBuffers(renderer, &snapshot) == gfx.NjgResult.Ok, "njgGetSharedBuffers failed");
        int windowW = 0;
        int windowH = 0;
        SDL_GetWindowSize(hostWindow, &windowW, &windowH);
        updatePuppetScreenBounds(puppetBounds, dragMap, view, snapshot, windowW, windowH);

        gfx.renderCommands(&backendInit, &snapshot, &view);

        // Some SDL backends create/replace native subviews lazily after first render.
        // Re-apply transparency once to catch late-created view/layer objects.
        if (transparencyRetryPending) {
            configureTransparentWindow(hostWindow, &transparentDebug);
            transparencyRetryPending = false;
        }

        api.flushCommands(renderer);
        version (EnableVulkanBackend) {
        } else version (EnableDirectXBackend) {
        } else {
            SDL_GL_SwapWindow(hostWindow);
        }

        frameCount++;
        if (isTest && frameCount >= testMaxFrames) {
            writefln("Exit after %s frames (test)", frameCount);
            break;
        }
        auto elapsed = now - startTime;
        if (isTest && elapsed > testTimeout) {
            writefln("Exit: elapsed %s > test-timeout %s", elapsed.total!"seconds", testTimeout.total!"seconds");
            break;
        }
    }

    api.unloadPuppet(renderer, puppet);
    api.destroyRenderer(renderer);
    // Keep DLL runtime alive until process exit to avoid shutdown-order crashes.

    version (EnableDirectXBackend) {
        import core.stdc.stdlib : _Exit;
        _Exit(0);
    } else version (EnableVulkanBackend) {
        import core.stdc.stdlib : _Exit;
        _Exit(0);
    }
}
