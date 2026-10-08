# Moonfin 2.6.0 Linux EGL video-renderer experiment

Status: **experimental / NOT VERIFIED on the affected X11 machine**. Do not merge or ship as a fix until the video and gamepad UI have been tested.

## Reproduction (2026-10-08)

- Apple MacBook Pro A1707; Xubuntu X11, XFCE, external DisplayPort-2 at 1920×1080/120 Hz.
- Intel HD Graphics 630 (`i915`) and AMD Radeon Pro 555 (`amdgpu`), active OpenGL renderer AMD; `vainfo` confirms H.264 decode capability on both.
- Moonfin **AppImage 2.6.0**: Direct Play, H.264 High@L3.2, 1256×678, 24fps, visually severe frame skips.
- Same content in Moonfin Web on Firefox plays smoothly. Clone Hero plays smoothly on the external display.
- Changing XFCE compositing and testing mpv `video-sync=display-resample` with `interpolation=yes` did not resolve it. System display settings were restored.
- AppImage log repeatedly shows:

```text
[IMPORTANT:flutter/shell/platform/embedder/embedder_surface_gl_impeller.cc(126)] Using the Impeller rendering backend (OpenGLESSDF).
media_kit: VideoOutput: EGL display or context is invalid.
media_kit: VideoOutput: S/W rendering.
WARNING: glGetError 501 (.../fl_pixel_buffer_texture.cc:89)
```

## Root-cause hypothesis

Pinned `media_kit_video` source in [RadicalMuffinMan/media-kit at 43368ec](https://github.com/RadicalMuffinMan/media-kit/tree/43368ec394dcce7795707358b751a748c1fdc610/media_kit_video/linux) calls `eglGetCurrentDisplay()` and `eglGetCurrentContext()` on GTK's platform thread. Neither is guaranteed to be current there. The log matches [media-kit/media-kit#1404](https://github.com/media-kit/media-kit/issues/1404). This specifically establishes **software rendering output**; video codec hardware decode is a separate question.

## Changes

1. When there is no current Flutter EGL context, query the native X11 or Wayland display via GDK and `eglGetPlatformDisplayEXT` (resolved through `eglGetProcAddress` to avoid epoxy's EGL 1.5 dispatch bootstrap issue).
2. Initialize that display; select an OpenGL ES2-capable EGL config instead of trying to query an absent Flutter context. Keep the original config path if Flutter has a current EGL context.
3. Only restore Flutter's EGL context if one was initially current.
4. On Linux/X11, call `XInitThreads()` before initializing the GTK application because the independent EGL/mpv path can interact with the same X11 connection across threads.
5. Provide an opt-in build script that patches the **pinned** `media_kit_video` source in Dart's cache temporarily, restores it after compiling, and does **not** replace the existing Moonfin AppImage.

The app's `pubspec.yaml` is unchanged; it continues to use Moonfin's pinned media_kit fork and its prior changes.

## Important upstream risk

An upstream tester reports [GLX BadAccess on X11 after enabling independent EGL](https://github.com/media-kit/media-kit/issues/1404#issuecomment-5172792949). The `XInitThreads()` call is an **unverified mitigation**, not a demonstrated fix. Another tester confirmed the EGL fallback on Wayland. A crash, blank frame, or a texture sharing failure should be treated as a failed experiment and followed up in this PR; the original AppImage remains available as rollback.

## Test on Xubuntu

Prerequisites: Flutter **3.47.2** on PATH; desktop build prerequisites including GTK3 headers, CMake/Ninja, libmpv dev headers, libepoxy and X11 dev headers. Project's other native dependencies still apply.

```bash
mkdir -p ~/Applications/patched
cd ~/Applications/patched
# Download this PR branch ZIP from GitHub and extract it here as Moonfin.
cd Moonfin
bash scripts/build-linux-egl-test.sh
build/linux/x64/release/bundle/moonfin 2>&1 | tee /tmp/moonfin-patched-egl.log
```

Alternatively start from the checkout branch. The build script compiles a native Flutter Linux bundle, **not** an AppImage. If it succeeds and plays smoothly, the bundle can be copied to `~/Applications/Moonfin` while preserving `~/Applications/Moonfin.AppImage`.

### Acceptance checks

- Logs show `Native EGL display initialized` and `H/W rendering with isolated EGL context`, not `EGL display or context is invalid` and `S/W rendering`.
- Re-test the **same** 1256×678 H.264 24fps stream in Direct Play for several minutes. Check dropped/jittery frames and seeking, resizing/fullscreen, playback stop/restart, and controller navigation.
- Look for `GLX BadAccess`, `EGL_BAD_ACCESS`, `glGetError 501`, corrupt/black video, teardown crashes, or resource leaks.
- Leave Xubuntu display at 1920×1080/120 Hz and XFCE compositing enabled; **do not** alter Steam/Clone Hero settings.
- Confirm that closing Moonfin and returning to Steam works normally.
- Record build/SDK versions and attach sanitized startup/playback logs before upgrading PR from draft.

### Rollback

Close patched Moonfin and launch the existing `~/Applications/Moonfin.AppImage`. The script restores the cached dependency source on exit. If interrupted with SIGKILL/power loss, run `flutter pub cache repair` or re-fetch the pinned dependency before rebuilding.
