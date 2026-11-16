# Patched guest Venus ICD (Apple Silicon 16 KiB pages)

The iOS host uses 16 KiB VM pages, while the Arch Linux ARM guest normally
uses 4 KiB pages. Stock Venus allocations can therefore fail during ring
creation or later device-memory allocation, surfacing as
`VK_ERROR_OUT_OF_HOST_MEMORY` from `vkCreateInstance`.

This package rebuilds **only** Mesa's `vulkan-virtio` ICD with the four
16 KiB alignment changes required by the Apple Silicon workaround. It does
not replace the guest's OpenGL drivers or the rest of Mesa.

## Build and install inside the Arch Linux ARM guest

From a terminal in the guest:

```sh
sudo pacman -S --needed base-devel meson ninja pkgconf glslang libdrm libelf libxml2 python-mako python-packaging python-ply python-pycparser spirv-tools wayland-protocols
git clone https://github.com/ElequacityStudios/crate-ios.git
cd crate-ios/guest-mesa
makepkg -si
```

The package replaces the repository's `vulkan-virtio` package with a patched
26.2.7 build. It leaves `mesa`, `vulkan-icd-loader`, and all OpenGL drivers
untouched. The build needs several gigabytes of free space and can take a
while on a phone-hosted VM.

After installation, reboot the guest and run:

```sh
vulkaninfo --summary
```

The expected result is a `Virtio-GPU Venus` physical device, not
`ERROR_OUT_OF_HOST_MEMORY`.

If you need to revert, reinstall the repository package:

```sh
sudo pacman -S vulkan-virtio
```

The patch is based on slp/mesa commit
`761ef1ec5ff2aae1cc3dc8bbc22b3d06ef04b549`. All four alignment sites are
intentional: aligning only the ring can move the failure to device-memory
allocation.
