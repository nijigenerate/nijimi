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

