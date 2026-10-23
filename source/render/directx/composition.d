module render.directx.composition;
version (EnableDirectXBackend):
import core.sys.windows.com : IUnknown;
import core.sys.windows.windows : HRESULT, HWND, BOOL;
import core.sys.windows.basetyps : GUID;
pragma(lib, "dcomp");
// Windows SDK dcomp.h interface prefixes, through the methods used here.
extern(Windows) interface CompositionDevice : IUnknown {
    HRESULT Commit();
    HRESULT WaitForCommitCompletion();
    HRESULT GetFrameStatistics(void* statistics);
    HRESULT CreateTargetForHwnd(HWND hwnd, BOOL topmost, CompositionTarget* target);
    HRESULT CreateVisual(CompositionVisual* visual);
}
extern(Windows) interface CompositionTarget : IUnknown {
    HRESULT SetRoot(CompositionVisual visual);
}
extern(Windows) interface CompositionVisual : IUnknown {
    HRESULT SetOffsetX(float offset);
    HRESULT SetOffsetX(IUnknown animation);
    HRESULT SetOffsetY(float offset);
    HRESULT SetOffsetY(IUnknown animation);
    HRESULT SetTransform(const(float)* matrix);
    HRESULT SetTransform(IUnknown transform);
    HRESULT SetTransformParent(CompositionVisual visual);
    HRESULT SetEffect(IUnknown effect);
    HRESULT SetBitmapInterpolationMode(int mode);
    HRESULT SetBorderMode(int mode);
    HRESULT SetClip(const(float)* rect);
    HRESULT SetClip(IUnknown clip);
    HRESULT SetContent(IUnknown content);
}
immutable GUID compositionDeviceIID = {0xc37ea93a, 0xe7aa, 0x450d,
    [0xb1, 0x6f, 0x97, 0x46, 0xcb, 0x04, 0x07, 0xf3]};
extern(Windows) HRESULT DCompositionCreateDevice(IUnknown dxgiDevice, const(GUID)* iid, void** device);
