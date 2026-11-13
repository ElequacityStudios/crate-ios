# crate

An iOS app that runs Linux VMs on the crate engine. JIT is real; VMs and
installs are still sample data and stubs (search the code for `STUB`,
`SAMPLE DATA` and `PLACEHOLDER`).

Three tabs:

- **Home**: the installed VMs, one large card each, with Start. The starred VM
  boots at launch when JIT is on.
- **Install Vms**: the downloadable images, a memory limit, and Install.
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

## Build

Both libraries are fetched or built into `Frameworks/`, which isn't committed:

    ./Scripts/fetch-stikjit.sh     # StikJIT 2.0.1, checked against its SHA-256
    ./Scripts/build-idevice.sh     # idevice v0.1.68 from source; needs Rust
    xcodegen generate
    open Crate.xcodeproj

or for the Simulator:

    xcodebuild -project Crate.xcodeproj -scheme Crate \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build build

Launch arguments show one state without tapping to it:

    xcrun simctl launch booted com.amendez.crate --tab=install --jit=on
    # --tab=home|install|settings  --jit=on|off  --empty  --samples
    # --rail: the open Duo's tab column, on any device
