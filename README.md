# crate

An iOS app that runs Linux VMs on the crate engine: JIT, installing a VM,
and booting it to its desktop. A few UI stand-ins remain (search the code for
`STUB`, `SAMPLE DATA` and `PLACEHOLDER`).

Three tabs:

- **Home**: the installed VMs, one large card each, with the screen each was
  showing when last stopped (`preview.jpg` in its folder) and Start. A card's
  menu has the VM's settings (on iPhone Duo) and Delete.
- **Install Vms**: the images the catalog lists, a memory limit, and Install,
  which asks for the account to make in the VM.
- **Settings**: JIT, memory, logs, and a UI Preview section that flips the
  stubs.

## JIT

crate claims its code region at launch, or once a debugger arrives: mapped
executable, authorized by the debugger on `brk #0x69` (StikDebug's legacy.js
convention), then mapped again for writing, and test-run. Two ways to get the
debugger, picked in Settings:

- **StikDebug**: crate opens `stikdebug://enable-jit` with its pid and
  legacy.js; StikDebug attaches and comes back.
- **Built-in StikJIT**: a helper extension (`Sources/JITHelper`) runs
  [StikJIT](https://github.com/StikDebug/StikJIT) (MPL-2.0) through
  LocalDevVPN's tunnel. Set Up JIT pairs the iPhone with crate itself on iOS 27
  (or takes a pairing file), with [idevice](https://github.com/jkcoxson/idevice)
  (MIT), built from source with one patch (`Scripts/patches`).

Each launch logs its JIT steps to `Library/Caches/crate.log`, and pairing's
messages to `Library/Caches/idevice.log`.

## The engine

[crate](https://github.com/oneamendez/crate) runs the VM in this process, on the
code region JIT claimed. The VM screen switches between its display (a virtio
GPU, frames handed straight to the app, touch and keys as a virtio tablet and
keyboard) and its serial console in a terminal
([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT). On an iPhone the
GPU does 3D: the guest's OpenGL runs on the iPhone's GPU through virglrenderer,
ANGLE and MoltenVK, each built from upstream source (see
[docs/PROVENANCE.md](docs/PROVENANCE.md)); in the Simulator the guest draws in
software. The network is
user-mode, through [libslirp](https://gitlab.freedesktop.org/slirp/libslirp)
(BSD-3-Clause) and [GLib](https://gitlab.gnome.org/GNOME/glib) (LGPL-2.1-or-later),
built from source as dynamic frameworks the app embeds.

Above the display's keyboard is a row of the keys an iPhone keyboard lacks:
Esc, Ctrl, Super, Tab, function keys and arrows, sent as Linux key codes; Ctrl
and Super hold for the next key, from the row or either keyboard. Take
Screenshot, in the toolbar's overflow menu, saves the VM's frame at its own
size to Photos and offers it to share.

On iPhone Duo the VM screen's toolbar goes down the side, where iOS puts bars
there, and drops the title, which would take a strip of height. When the
keyboard leaves the bar short of room, the display/console switch goes into its
overflow menu before the keyboard button does. Folded like a laptop, the display or
console moves above the fold, and the console brings the keyboard up below it.
Folded like a book, both span the fold. The Simulator can't fold, so crate logs
the hinge and the fold to `crate.log` for checking on the device.

## Installs

The images come from
[arm64-desktop-images](https://github.com/oneamendez/arm64-desktop-images),
whose GitHub workflow builds and attests them: Debian with KDE Plasma, Ubuntu
with GNOME, Arch Linux ARM with KDE Plasma. Each release has a `catalog.json`
listing every image's kernel, initrd and disk (xz, in parts under 2 GiB) with
their SHA-256s, its kernel command line, and its cloud-init vendor-data.

Install reads the latest catalog, downloads an image (crate must stay open
meanwhile), checks every file, unpacks the disk through Apple's xz decoder as
its parts arrive (sparsely: empty space takes no room) and grows it to 32 GB.
The account comes from a seed disk crate writes beside it (`seed.img`, FAT,
labelled CIDATA): cloud-init's NoCloud user-data with the user, a SHA-512
crypt of the password, the hostname and time zone, plus the image's
vendor-data (its desktop's autologin). The seed stays attached read-only, so
cloud-init sets the VM up once. A VM's files are in
`Library/Application Support/VMs/<its ID>/`.

A VM can still be put on the iPhone by hand: copy `vmlinuz`, `initrd.img` and
`disk.img` into its folder with `devicectl device copy to ... --user mobile`
(without it crate can't write to the disk; never add
`--remove-existing-content`, which empties the app's whole container). It
boots with aTerm's command line.

Debug builds can be driven from a Mac the same way: while a VM runs, an empty
`Library/Caches/debug/screen` gets its display saved as `screen.png` there,
`debug/command.txt` is typed into its console, and `debug/size.txt` ("WxH" in
points) resizes its desktop as rotating or folding the iPhone would. Launched with
`CRATE_GL_DEBUG=1` (`devicectl device process launch -e`), crate logs ANGLE's
own GL messages; with `CRATE_LOG=debug`, its debug lines.

## Build

The libraries are fetched or built into `Frameworks/`, which isn't committed:

    ./Scripts/fetch-stikjit.sh     # StikJIT 2.0.1, checked against its SHA-256
    ./Scripts/build-idevice.sh     # idevice v0.1.68 from source; needs Rust
    ./Scripts/build-crate.sh       # crate from ~/Repos/crate; needs Rust
    ./Scripts/build-slirp.sh       # libslirp 4.9.7 and GLib 2.90.1; needs meson
    ./Scripts/build-moltenvk.sh    # MoltenVK 1.4.2; about 15 minutes
    ./Scripts/build-angle.sh       # ANGLE; a 4 GB checkout, ANGLE_SRC reuses one
    ./Scripts/build-virgl.sh       # libepoxy 1.5.10 and virglrenderer 1.3.0
    xcodegen generate
    open Crate.xcodeproj

or for the Simulator:

    xcodebuild -project Crate.xcodeproj -scheme Crate \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build build

Launch arguments show one state without tapping to it:

    xcrun simctl launch booted com.amendez.crate --tab=install --jit=on
    # --tab=home|install|settings  --jit=on|off  --empty  --samples
    # --rail: the open Duo's tab column, on any device

With `--jit=on` the Simulator has no code region, so starting a VM pretends: its
screenshot becomes the display, and the console shows a login prompt that
echoes typing.

## Known issues

- **A guest can't update its own kernel.** crate boots a VM's kernel and
  initrd from outside its disk, so the images hold their kernel packages at
  the version they shipped with. A kernel the guest installs anyway is never
  booted, and an upgrade can remove the modules the booted kernel needs.
- **Xfce doesn't follow a new screen size.** On rotate or fold, labwc takes
  the new size but the Xfce panel and desktop don't (see crate's docs/PLAN.md).
