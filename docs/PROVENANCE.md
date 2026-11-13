# Where crate's code comes from

Everything the app ships besides its own code, where each piece comes from, and
how it gets into `Frameworks/`. Nothing there is committed: the scripts in
`Scripts/` fetch or build it, pinned to a version and checked against a SHA-256
or a commit.

| Piece | Version | License | From | How |
| --- | --- | --- | --- | --- |
| [crate](https://github.com/oneamendez/crate) | main | MPL-2.0 | its repository | `build-crate.sh`, from `~/Repos/crate` |
| [StikJIT](https://github.com/StikDebug/StikJIT) | 2.0.1 | MPL-2.0 | its release's framework | `fetch-stikjit.sh` |
| [idevice](https://github.com/jkcoxson/idevice) | 0.1.68 | MIT | its source | `build-idevice.sh`, one patch |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.18.0 | MIT | Swift package | Xcode |
| [libslirp](https://gitlab.freedesktop.org/slirp/libslirp) | 4.9.7 | BSD-3-Clause | its release's source | `build-slirp.sh` |
| [GLib](https://gitlab.gnome.org/GNOME/glib) | 2.90.1 | LGPL-2.1-or-later | its release's source | `build-slirp.sh` |
| [MoltenVK](https://github.com/KhronosGroup/MoltenVK) | 1.4.2 | Apache-2.0 | its release tag's source | `build-moltenvk.sh` |
| [ANGLE](https://chromium.googlesource.com/angle/angle) | 9addc29 | BSD-3-Clause | its source | `build-angle.sh`, one patch |
| [libepoxy](https://github.com/anholt/libepoxy) | 1.5.10 | MIT | its release's source | `build-virgl.sh`, one patch |
| [virglrenderer](https://gitlab.freedesktop.org/virgl/virglrenderer) | 1.3.0 | MIT | its release's source | `build-virgl.sh`, three patches |

MoltenVK's build fetches its own dependencies (SPIRV-Cross, SPIRV-Tools,
glslang, the Vulkan headers, all Apache-2.0 or MIT) at the revisions its
release names, and links them into MoltenVK. ANGLE's gclient checkout does the
same for what ANGLE links.

## The patches

In `Scripts/patches/`, each with a header saying what it changes and why:

- `idevice-pairable-host.patch`: lets crate advertise itself as a computer the
  iPhone pairs with, for Set Up JIT's on-device pairing.
- `angle-vulkan.patch`: ANGLE's Vulkan backend inside an iOS app, on MoltenVK.
  Written for aTerm, the app crate succeeds, and carried over unchanged.
- `libepoxy-ios-angle.patch`: libepoxy's EGL support on an iPhone, opening
  ANGLE's frameworks.
- `virglrenderer-angle-integer-attribs.patch`: integer vertex attributes
  declared as integers on ANGLE, which Vulkan holds to their declared type.
  Without it every glyph and image Chrome draws on the GPU samples the wrong
  place.
- `virglrenderer-border-clamp.patch`: clamp to the edge where ANGLE on MoltenVK
  has no border clamp, rather than a call ANGLE refuses.
- `virglrenderer-cursor-rows.patch`: the cursor's rows top first, as crate shows
  them; upstream turns every cursor upside down.

## The 3D stack

The guest's Mesa draws through virtio-gpu; crate hands those commands to
virglrenderer, which turns them into OpenGL ES calls (through libepoxy) on ANGLE,
which runs on Vulkan, which is MoltenVK, on Metal. Guest images need nothing of
their own for it: Mesa's virgl driver and the kernel's virtio-gpu driver, both
standard in Debian and Arch.

aTerm had the same stack, but only ANGLE was its own build from upstream: it
took virglrenderer, libepoxy and MoltenVK prebuilt from another project, with
that project's changes to virglrenderer. None of that is used here. Each piece
is built from its upstream release. virglrenderer's three patches above are
crate's own, each found by comparing upstream's behaviour with that build's on
the same guest, never from its source. The sample-count override aTerm had to
patch around isn't in upstream. virglrenderer is built with its
`check-gl-errors` option off, so a GL call ANGLE refuses costs that call rather
than the guest's whole GL context.
