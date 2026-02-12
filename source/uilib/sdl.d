module uilib.sdl;

import bindbc.sdl;
import std.conv : to;
import std.string : fromStringz;
import std.string : toStringz;

private __gshared SDL_Tray* gTray = null;
private __gshared SDL_TrayEntry* gToggleEntry = null;
private __gshared SDL_TrayEntry* gQuitEntry = null;
private __gshared SDL_Surface* gTrayIcon = null;
private __gshared bool gTrayQuitRequested = false;
private __gshared bool gTrayToggleRequested = false;

private void debugLog(void function(string) debugFn, string message) {
    if (debugFn !is null) {
        debugFn(message);
    }
}

void configureOverlayWindow(SDL_Window* window, void function(string) debugFn = null) {
    if (window is null) return;

    configureWindowBorderlessDesktop(window, debugFn);
    configureWindowAlwaysOnTop(window, true);
}

void configureWindowAlwaysOnTop(SDL_Window* window, bool onTop) {
    if (window is null) return;
    SDL_SetWindowAlwaysOnTop(window, onTop);
}

void configureWindowInputPolicy(SDL_Window* window, bool focusable, void function(string) debugFn = null) {
    if (window is null) return;
    SDL_SetWindowKeyboardGrab(window, false);
    SDL_SetWindowMouseGrab(window, false);
    SDL_SetWindowFocusable(window, focusable);
    if (debugFn !is null) {
        debugFn("[overlay] input policy: focusable=" ~ (focusable ? "true" : "false"));
    }
}

void configureWindowBorderlessDesktop(SDL_Window* window, void function(string) debugFn = null) {
    if (window is null) return;

    SDL_SetWindowBordered(window, false);
    auto displayId = SDL_GetDisplayForWindow(window);
    if (displayId == 0) {
        debugLog(debugFn, "[overlay] SDL_GetDisplayForWindow failed");
        return;
    }

    SDL_Rect usable = SDL_Rect.init;
    if (!SDL_GetDisplayUsableBounds(displayId, &usable)) {
        debugLog(debugFn, "[overlay] SDL_GetDisplayUsableBounds failed");
        return;
    }
    if (usable.w <= 0 || usable.h <= 0) {
        debugLog(debugFn, "[overlay] invalid usable bounds");
        return;
    }

    SDL_SetWindowPosition(window, usable.x, usable.y);
    SDL_SetWindowSize(window, usable.w, usable.h);
    debugLog(debugFn, "[overlay] applied usable bounds " ~ usable.w.to!string ~ "x" ~ usable.h.to!string ~
        " at " ~ usable.x.to!string ~ "," ~ usable.y.to!string);
}

private uint mapRgba(SDL_Surface* surface, ubyte r, ubyte g, ubyte b, ubyte a) {
    if (surface is null) return 0;
    auto details = SDL_GetPixelFormatDetails(surface.format);
    if (details is null) return 0;
    return SDL_MapRGBA(details, null, r, g, b, a);
}

private SDL_Surface* createTrayIconSurface() {
    auto icon = SDL_CreateSurface(16, 16, SDL_PixelFormat.rgba32);
    if (icon is null) return null;

    auto base = mapRgba(icon, 18, 22, 30, 255);
    auto accent = mapRgba(icon, 66, 175, 255, 255);
    auto white = mapRgba(icon, 240, 245, 255, 255);

    SDL_FillSurfaceRect(icon, null, base);

    SDL_Rect rect = SDL_Rect.init;
    rect.x = 2;
    rect.y = 2;
    rect.w = 12;
    rect.h = 12;
    SDL_FillSurfaceRect(icon, &rect, accent);

    rect.x = 5;
    rect.y = 5;
    rect.w = 6;
    rect.h = 6;
    SDL_FillSurfaceRect(icon, &rect, white);

    return icon;
}

extern(C) nothrow private void trayToggleCallback(void* userData, SDL_TrayEntry* entry) {
    gTrayToggleRequested = true;
}

extern(C) nothrow private void trayQuitCallback(void* userData, SDL_TrayEntry* entry) {
    gTrayQuitRequested = true;
}

void setSystemTrayWindowVisible(bool visible) {
    if (gToggleEntry is null) return;
    SDL_SetTrayEntryLabel(gToggleEntry, visible ? "Hide".toStringz : "Show".toStringz);
}

bool initializeSystemTray(SDL_Window* window, void function(string) debugFn = null) {
    if (gTray !is null) return true;
    if (window is null) return false;

    gTrayIcon = createTrayIconSurface();
    gTray = SDL_CreateTray(gTrayIcon, "nijimi".toStringz);
    if (gTray is null) {
        if (debugFn !is null) {
            auto err = SDL_GetError();
            debugFn("[tray] SDL_CreateTray failed: " ~ (err is null ? "" : fromStringz(err).idup));
        }
        if (gTrayIcon !is null) {
            SDL_DestroySurface(gTrayIcon);
            gTrayIcon = null;
        }
        return false;
    }

    auto menu = SDL_CreateTrayMenu(gTray);
    if (menu is null) return true;

    gToggleEntry = SDL_InsertTrayEntryAt(menu, 0, "Hide".toStringz, SDL_TrayEntryFlags.button);
    gQuitEntry = SDL_InsertTrayEntryAt(menu, 1, "Quit".toStringz, SDL_TrayEntryFlags.button);

    if (gToggleEntry !is null) {
        SDL_SetTrayEntryCallback(gToggleEntry, &trayToggleCallback, null);
    }
    if (gQuitEntry !is null) {
        SDL_SetTrayEntryCallback(gQuitEntry, &trayQuitCallback, null);
    }

    return true;
}

void updateSystemTray() {
    SDL_UpdateTrays();
}

bool consumeTrayQuitRequested() {
    auto v = gTrayQuitRequested;
    gTrayQuitRequested = false;
    return v;
}

bool consumeTrayToggleRequested() {
    auto v = gTrayToggleRequested;
    gTrayToggleRequested = false;
    return v;
}

void shutdownSystemTray() {
    gToggleEntry = null;
    gQuitEntry = null;
    if (gTray !is null) {
        SDL_DestroyTray(gTray);
        gTray = null;
    }
    if (gTrayIcon !is null) {
        SDL_DestroySurface(gTrayIcon);
        gTrayIcon = null;
    }
    gTrayQuitRequested = false;
    gTrayToggleRequested = false;
}
