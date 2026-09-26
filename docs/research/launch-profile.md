# Cold-launch profile (L-002, local session, 2026-09-26)

Spec §27 NFR: interactive Dashboard in under 2 s on the reference device. CI (shared runner) measured 3.197 s.

## Setup
- Mac: macOS 27.0, Xcode 27.0 (27A266a). CI uses Xcode 26.6.
- Simulator: iPhone 17 Pro Max, iOS 26.5 (23F77). No iPhone was connected, so there are no device numbers yet.
- Build: the **Debug** build that `Scripts/verify.sh` produces (commit d097637). A Release build was not measured.

## Launch time
`LaunchPerformanceUITests.testLaunchPerformance` (`XCTApplicationLaunchMetric`), run by `Scripts/verify.sh`:

| Run | 1 | 2 | 3 | 4 | 5 | Average | RSD |
|---|---|---|---|---|---|---|---|
| Seconds | 1.126 | 1.185 | 1.339 | 1.176 | 1.229 | **1.211** | 5.9 % |

On this Mac the launch is **under the 2 s target**. The 3.2 s on CI comes from the slower shared runner, not from the
app. Setting this number as the baseline is still open (WALK-QUEUE); it needs an owner decision on the threshold.

## Where the main thread goes (Instruments, App Launch template)
Instruments records launch lifecycle phases only on a device; on the Simulator the `life-cycle-period` table is
empty. The costs below come from main-thread `time-profile` samples (1 ms each) in three traces taken with
`xcrun xctrace record --template "App Launch"`. The traces are 200–500 MB each, so they are not committed.

| # | Cost | Main-thread ms (3 traces) | Notes |
|---|---|---|---|
| 1 | `dyld_sim` prepare: loading and binding images before `main` | 704 / 618 / 168 | Simulator dyld runs without the device's prebuilt launch closures, and the Debug build adds `HouseholdHub.debug.dylib`. This is not app code; Release builds and devices are much cheaper here. It varies with the disk cache (warm run: 168 ms). |
| 2 | `HouseholdHubApp.init` → `HouseholdContainerFactory.makeContainer(configuration:)` | 120 / 108 / 60 | The SwiftData store opens synchronously before the first frame. Almost all of `init` is spent here. |
| 3 | The rest of `HouseholdHubApp.$main` (App/Scene setup outside `init`) | 36 / 42 / 27 | The system frames are unsymbolicated. |

After `$main`, the main thread is almost idle for the rest of the 2.2 s window: the first Dashboard frame does not
show up as a hot spot.

## Takeaways for the cloud session (no code changed here)
- The only cost in app code is #2, the synchronous `makeContainer` (60–120 ms). Moving the store open off the
  critical path, for example by showing the shell first and opening the store on a `ModelActor`, would save about
  0.1 s. That is not needed to meet 2 s on this Mac.
- Measure a Release build, and on the iPhone, before changing anything: #1 is mostly a Debug/Simulator artifact.
