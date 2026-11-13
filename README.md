# crate

An iOS app that runs Linux VMs on the crate engine. This is the UI only, so
far: VMs, installs and JIT are sample data and stubs (search the code for
`STUB`, `SAMPLE DATA` and `PLACEHOLDER`).

Three tabs:

- **Home**: the installed VMs, one large card each, with Start. The starred VM
  boots at launch when JIT is on.
- **Install Vms**: the downloadable images, a memory limit, and Install.
- **Settings**: JIT, memory, logs, and a UI Preview section that flips the
  stubs.

## Build

    xcodegen generate
    open Crate.xcodeproj

or for the Simulator:

    xcodebuild -project Crate.xcodeproj -scheme Crate \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build build

Launch arguments show one state without tapping to it:

    xcrun simctl launch booted com.amendez.crate --tab=install --jit=on
    # --tab=home|install|settings  --jit=on|off  --empty  --samples
    # --rail: the open Duo's tab column, on any device
