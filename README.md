# nijimi

`nijimi` is a desktop mascot viewer program that renders nijilive puppets through the **nijilive Unity DLL ABI (`njg*`)**.

This repository focuses on host-side integration:
- load `libnijilive-unity` and bind exported C ABI symbols
- create rendering context (SDL3 + OpenGL or Vulkan)
- receive command queue/shared buffers from DLL
- execute rendering on the host backend

In other words, `nijimi` is an application that displays an animated 2D character as a desktop mascot overlay.

## Backends

- OpenGL backend: `source/opengl/opengl_backend.d`
- Vulkan backend: `source/vulkan/vulkan_backend.d`
- DirectX backend (Windows): `source/directx/directx_backend.d`

All backends are selectable with DUB configurations.

## DUB Configurations

- `opengl`
  - target: `nijimi-opengl`
  - backend dependency: `bindbc-opengl`
  - excludes: `source/vulkan/**`
- `vulkan`
  - target: `nijimi-vulkan`
  - backend dependency: `erupted`
  - version flag: `EnableVulkanBackend`
  - excludes: `source/opengl/**`
- `directx` (Windows)
  - target: `nijimi-directx`
  - backend dependency: `aurora-directx`
  - version flag: `EnableDirectXBackend`
  - excludes: `source/opengl/**`, `source/vulkan/**`

Common dependencies are kept at package root (SDL, math/image/support libs).

## Requirements

- D toolchain (`ldc2` recommended)
- `dub`
- SDL3 runtime
- nijilive Unity library (`libnijilive-unity*`)
- puppet file (`.inp` or `.inx`)

Vulkan runtime requirements:
- Vulkan loader + ICD (MoltenVK on macOS)
- a valid Vulkan SDK/runtime environment when running `nijimi-vulkan`

## Build Order

1. Build nijilive Unity DLL (`libnijilive-unity*`)
2. Build `nijimi` backend (`opengl` or `vulkan`)
3. Run viewer

## Build nijilive Unity DLL

Expected layout:

```text
.../nijigenerate/
  nijimi/
  nijilive/
```

### macOS

In `../nijilive`:

```bash
./build-aux/osx/buildUnityDLL.sh
```

or:

```bash
dub build --config unity-dll-macos
```

### Windows

In `../nijilive`:

```bat
build-aux\\windows\\buildUnityDLL.bat
```

or:

```bat
dub build --config unity-dll
```

### Linux

If `nijilive` does not provide a Linux unity-dll config in your checkout, prepare an equivalent `.so` build path on the nijilive side first.

## Build nijimi

OpenGL:

```bash
dub build --config=opengl
```

Vulkan:

```bash
dub build --config=vulkan
```

DirectX (Windows):

```bash
dub build --config=directx
```

## Run

OpenGL:

```bash
./nijimi-opengl <puppet.inp|puppet.inx> [width height] [--test] [--frames N]
```

Vulkan:

```bash
./nijimi-vulkan <puppet.inp|puppet.inx> [width height] [--test] [--frames N]
```

DirectX (Windows):

```bash
./nijimi-directx <puppet.inp|puppet.inx> [width height] [--test] [--frames N]
```

Notes:
- If `.inxd` is passed by mistake, the app attempts fallback to `.inx` / `.inp` with the same stem.

## DLL Search

`source/app.d` resolves Unity library names per OS:

- Windows: `nijilive-unity.dll`, `libnijilive-unity.dll`
- Linux: `libnijilive-unity.so`, `nijilive-unity.so`
- macOS: `libnijilive-unity.dylib`, `nijilive-unity.dylib`

Search order:
1. current working directory
2. `../nijilive`
3. `../../nijilive`
4. relative `../nijilive`

## Runtime Options

CLI:
- `--test`
- `--frames N`
- `--transparent-window` / `--no-transparent-window`
- `--transparent-window-retry` / `--no-transparent-window-retry`
- `--transparent-debug` / `--no-transparent-debug`

Environment variables:
- `NJIV_TEST_FRAMES`
- `NJIV_TEST_TIMEOUT_MS`
- `NJIV_TRANSPARENT_WINDOW`
- `NJIV_TRANSPARENT_WINDOW_RETRY`
- `NJIV_TRANSPARENT_DEBUG`
- `NJIV_WINDOWS_BLUR_BEHIND` (Windows DWM mode)

## Windows Transparency Notes

- OpenGL/DirectX default to layered `colorkey` transparency.
- Vulkan defaults to DWM composition mode.

## Vulkan Status

Vulkan backend is actively being brought to parity with OpenGL.
Current implementation includes:
- command queue execution
- texture upload and draw batching
- blend mode table (including advanced equation path when extension is available)
- mask/stencil path under active refinement

If rendering differs from OpenGL on specific assets, treat Vulkan as work-in-progress and verify against `opengl` configuration.


## Windows DLL comparison (OpenGL)

Build `nijimi-opengl` with LDC, then run the same viewer with explicit DLL paths:

```powershell
./test/compare-dlls.ps1 -Model C:/models/model.inp -NijiliveDll ../nijilive/nijilive-unity.dll -NicxliveDll ../nijiexpose/build/nicxlive-shared/Release/nicxlive.dll
```

SDL3.dll must be accessible through PATH or next to the viewer. The script records
both screenshots, logs, and SHA-256 hashes of the model, viewer, and DLLs.
`--test` uses a fixed 1/60-second step, disables incoming tracking, and preserves
the requested window size. `--capture path.png` saves the final requested frame
before swapping buffers and fails on timeout or an OpenGL error. Capture currently
supports OpenGL only. Normal interactive use continues to support
`--unity-dll nijilive|nicxlive|PATH` and `NIJIMI_UNITY_DLL`.

A successful run is not a claim of rendering parity. The 2026-10-21 Kurone
`Kurone-20240212-1.4-wld7.1.inp` comparison at frame 3 produced 148 commands with
nijilive and 100 with nicxlive (both 5795 vertices, 17 parameters).
A subsequent audit preserved the outputs before three reruns using the same
hashed inputs. Each DLL reproduced its original PNG byte-for-byte in every run.
The available C++ PNGs show both arms, hands, and feet; the earlier missing-limb
report is unsupported and withdrawn. The raw first tool-presentation payload was
not retained, so the origin of that earlier visual discrepancy is unproven.
D/C++ images differ at 4,988 of 518,400 pixels. Neither full parity nor the cause
of those differences has been established.
