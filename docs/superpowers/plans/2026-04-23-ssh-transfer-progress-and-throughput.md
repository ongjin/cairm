# SSH Transfer Progress + Throughput Implementation Plan

> **For Codex executor:** Each task is self-contained with exact file paths and code. Follow task order. Build/test after each task before moving on. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SSH uploads/downloads show live progress (%, speed, ETA) in the transfer HUD and make the transfers noticeably faster on high-latency links (paste image → remote, drag local → remote).

**Architecture:**
- The Rust crate **already exposes** `sftp_progress_poll(h)` that returns a running byte count (`crates/cairn-ffi/src/ssh.rs:418`, returns `UInt64` on the Swift side). `SftpHandle.upload` / `.download` update this atomic after every 256 KiB chunk (`crates/cairn-ssh/src/sftp.rs:309, 396`).
- Swift `SshFileSystemProvider.uploadFromLocal` / `.downloadToLocal` accept a `progress` callback but **never call it** (`apps/Sources/Services/SshFileSystemProvider.swift:110-140`). The FFI call is `try sftp_upload_sync(...)` which is synchronous and blocks the async caller until done.
- Both `upload` and `download` loops in `crates/cairn-ssh/src/sftp.rs` send one 256 KiB chunk at a time and await the server ack before the next — caps sustained throughput at ≈ 256 KiB/RTT on a high-latency SSH tunnel (~8.5 MB/s over 30ms).
- Fix path: (1) reset the per-handle counter to 0 at the start of each sync transfer; (2) run the blocking FFI on `Task.detached`, and concurrently poll `sftp_progress_poll` every 150 ms feeding the callback; (3) open the HUD popover automatically when a transfer starts so user sees feedback instantly; (4) throughput win: pipeline SFTP writes (Task 4). Downloads can be pipelined the same way in a follow-up.

**Tech Stack:** Rust (`russh-sftp`, `tokio`), swift-bridge FFI, Swift / SwiftUI, `TransferController` / `TransferJob` / `TransferHudChip`.

**Reference files (read first):**
- `crates/cairn-ssh/src/sftp.rs:259-403` — `download` and `upload` inner loops (serial 256 KiB chunks).
- `crates/cairn-ssh/src/transfer.rs` — `ProgressSink` type.
- `crates/cairn-ffi/src/ssh.rs:140-170,375-421` — `SftpHandleBridge` + `sftp_upload_sync` + `sftp_progress_poll`.
- `apps/Sources/Services/SshFileSystemProvider.swift:110-140` — the Swift side that currently ignores `progress`.
- `apps/Sources/Services/TransferController.swift:58-102` — how `progress(bytes)` flows into `job.bytesCompleted`.
- `apps/Sources/Services/TransferJob.swift` — derived `percent` / `speed` / `eta` (already computed from `bytesCompleted`).
- `apps/Sources/Views/Transfer/TransferJobRow.swift` — already renders bar / %, so once bytes flow in the UI lights up automatically.
- `apps/Sources/Views/Transfer/TransferHudChip.swift` — currently only shows when `hasActive`; no auto-popover.

---

## File Structure

- **Modify:** `crates/cairn-ffi/src/ssh.rs` — reset `progress` to 0 at start of `sftp_upload_sync` / `sftp_download_sync`.
- **Modify:** `apps/Sources/Services/SshFileSystemProvider.swift` — wrap sync FFI in `Task.detached`, poll `sftp_progress_poll` concurrently, feed `progress` callback.
- **Modify:** `apps/Sources/Views/Transfer/TransferHudChip.swift` — auto-open popover for 3 seconds whenever `activeCount` transitions from 0 → 1 (user sees a job starting without needing to notice the chip).
- **Modify:** `crates/cairn-ssh/src/sftp.rs` — pipeline SFTP writes in the upload loop (Task 4, throughput). Download pipelining is a follow-up.
- **Test:** `apps/CairnTests/SSH/SftpProgressPollingTests.swift` — verify polling calls `progress` callback.

---

## Task 1: Reset per-handle progress at start of each sync transfer (Rust)

**Files:**
- Modify: `crates/cairn-ffi/src/ssh.rs`

Each SSH target shares **one** `SftpHandleBridge` (cached in `SshPoolService.sftpHandles`). The `progress: Arc<AtomicU64>` lives on that bridge. If two transfers hit the same handle back-to-back and the Swift side polls in between, stale cumulative bytes could confuse the UI. Reset to 0 at the top of each sync call.

Note: `TransferController.runningPerHost` already serializes transfers per host, so we won't get concurrent transfers on one handle — but resetting is still the clean contract.

- [ ] **Step 1: Edit `sftp_upload_sync` and `sftp_download_sync` to reset**

In `crates/cairn-ffi/src/ssh.rs`, find `sftp_download_sync` (around line 376) and `sftp_upload_sync` (around line 397). Replace both with:

```rust
fn sftp_download_sync(
    h: &SftpHandleBridge,
    remote: String,
    local: String,
    cancel: &CancelFlagBridge,
) -> Result<(), String> {
    use std::sync::atomic::Ordering;
    h.progress.store(0, Ordering::Relaxed);  // reset counter for this transfer
    let prog = h.progress.clone();
    let sink: ssh::ProgressSink = Arc::new(move |n| {
        prog.store(n, Ordering::Relaxed);
    });
    runtime()
        .block_on(h.inner.download(
            &remote,
            std::path::Path::new(&local),
            sink,
            cancel.inner.clone(),
        ))
        .map_err(|e| e.to_string())
}

fn sftp_upload_sync(
    h: &SftpHandleBridge,
    local: String,
    remote: String,
    cancel: &CancelFlagBridge,
) -> Result<(), String> {
    use std::sync::atomic::Ordering;
    h.progress.store(0, Ordering::Relaxed);  // reset counter for this transfer
    let prog = h.progress.clone();
    let sink: ssh::ProgressSink = Arc::new(move |n| {
        prog.store(n, Ordering::Relaxed);
    });
    runtime()
        .block_on(h.inner.upload(
            std::path::Path::new(&local),
            &remote,
            sink,
            cancel.inner.clone(),
        ))
        .map_err(|e| e.to_string())
}
```

The only change vs. the current code is the added `h.progress.store(0, Ordering::Relaxed)` line at the top of each function.

- [ ] **Step 2: Rust build**

Run:
```bash
./scripts/build-rust.sh
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add crates/cairn-ffi/src/ssh.rs
git commit -m "fix(ffi): reset per-handle progress counter at start of each sync sftp transfer"
```

---

## Task 2: Swift-side concurrent progress polling

**Files:**
- Modify: `apps/Sources/Services/SshFileSystemProvider.swift`
- Test: `apps/CairnTests/SSH/SftpProgressPollingTests.swift` (create; only covers the polling helper, not the real FFI)

Current code (line 123, 139) calls `try sftp_upload_sync(...)` synchronously from the async function. It blocks until done, so no progress updates can be delivered. Wrap the blocking call in `Task.detached` and run a parallel polling task that reads `sftp_progress_poll(h)` and invokes `progress(bytes)` until the transfer task finishes or cancels.

- [ ] **Step 1: Add a reusable polling helper**

Append to the bottom of `apps/Sources/Services/SshFileSystemProvider.swift` (after the `private extension FileEntryBridge` block, line 166):

```swift
// MARK: - Progress polling

/// Run `work` on a detached task while concurrently polling `poll` every
/// `interval` seconds and forwarding the returned value to `sink`. Stops
/// polling as soon as `work` completes (throws or returns). One extra `sink`
/// call at the end delivers the final byte count so a post-completion UI
/// read sees 100%.
///
/// Lives at file scope so it can be unit-tested without a real SSH session.
@MainActor
func runWithProgressPolling(
    interval: Duration = .milliseconds(150),
    poll: @escaping () -> Int64,
    sink: @escaping (Int64) -> Void,
    work: @escaping @Sendable () async throws -> Void
) async throws {
    let workTask = Task.detached(priority: .userInitiated) { try await work() }

    let pollTask = Task { @MainActor in
        while !Task.isCancelled {
            sink(poll())
            try? await Task.sleep(for: interval)
        }
    }

    defer {
        pollTask.cancel()
        sink(poll())  // final snapshot after work settled
    }

    // Propagate work result (including cancellation) to caller.
    _ = try await workTask.value
}
```

- [ ] **Step 2: Use the helper in `uploadFromLocal` and `downloadToLocal`**

Replace the `uploadFromLocal` implementation (lines 110-124) with:

```swift
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        let h = try await handle()
        let flag = cancel_flag_new()
        let cancelTask = Task {
            while !Task.isCancelled {
                if cancel.isCancelled { cancel_flag_cancel(flag); break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { cancelTask.cancel() }
        try await runWithProgressPolling(
            poll: { Int64(sftp_progress_poll(h)) },
            sink: progress,
            work: { try sftp_upload_sync(h, localURL.path, remotePath.path, flag) }
        )
    }
```

and `downloadToLocal` (lines 126-140) with:

```swift
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws {
        let h = try await handle()
        let flag = cancel_flag_new()
        let cancelTask = Task {
            while !Task.isCancelled {
                if cancel.isCancelled { cancel_flag_cancel(flag); break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        defer { cancelTask.cancel() }
        try await runWithProgressPolling(
            poll: { Int64(sftp_progress_poll(h)) },
            sink: progress,
            work: { try sftp_download_sync(h, remotePath.path, toLocalURL.path, flag) }
        )
    }
```

Also update the `FileSystemProvider` protocol in `apps/Sources/Services/FileSystemProvider.swift:36` so `progress` is `@escaping`:

```swift
    func uploadFromLocal(_ localURL: URL, to remotePath: FSPath, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws
    func downloadToLocal(_ remotePath: FSPath, toLocalURL: URL, progress: @escaping (Int64) -> Void, cancel: CancelToken) async throws
```

And the `LocalFileSystemProvider` stub versions (around line 62 of that file) — just add `@escaping` to the same two parameters so the protocol conformance compiles. The local provider likely ignores `progress`; that's fine.

- [ ] **Step 3: Write a polling-helper unit test**

Create `apps/CairnTests/SSH/SftpProgressPollingTests.swift`:

```swift
import XCTest
@testable import Cairn

@MainActor
final class SftpProgressPollingTests: XCTestCase {
    func test_pollingFiresSinkWhileWorkRuns() async throws {
        nonisolated(unsafe) var counter: Int64 = 0
        nonisolated(unsafe) var observed: [Int64] = []

        try await runWithProgressPolling(
            interval: .milliseconds(30),
            poll: { counter },
            sink: { observed.append($0) },
            work: {
                for i in 1...5 {
                    try await Task.sleep(for: .milliseconds(40))
                    counter = Int64(i) * 100
                }
            }
        )

        XCTAssertGreaterThanOrEqual(observed.count, 5)
        XCTAssertEqual(observed.last, 500)
    }

    func test_workErrorPropagates() async throws {
        struct BoomError: Error {}
        do {
            try await runWithProgressPolling(
                interval: .milliseconds(30),
                poll: { 0 },
                sink: { _ in },
                work: { throw BoomError() }
            )
            XCTFail("expected throw")
        } catch is BoomError {
            // expected
        }
    }
}
```

- [ ] **Step 4: Build + run the new test**

Run:
```bash
./scripts/build-rust.sh
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn -only-testing:CairnTests/SftpProgressPollingTests 2>&1 | tail -20
```
Expected: both tests pass.

- [ ] **Step 5: Manual smoke test**

1. Launch the app and connect to a remote host.
2. Copy a large local file (>10 MB) and paste it into the remote tab.
3. Observe the HUD chip in the toolbar. Click it to open the popover.
4. Expected: the progress bar fills live; `xx%` next to the filename updates; speed + ETA line updates after ~0.5s.

- [ ] **Step 6: Commit**

```bash
git add apps/Sources/Services/SshFileSystemProvider.swift \
        apps/Sources/Services/FileSystemProvider.swift \
        apps/Sources/Services/LocalFileSystemProvider.swift \
        apps/CairnTests/SSH/SftpProgressPollingTests.swift
git commit -m "feat(ssh): poll sftp_progress during sync transfers so HUD shows live %"
```

---

## Task 3: Auto-reveal the HUD popover when a transfer starts

**Files:**
- Modify: `apps/Sources/Views/Transfer/TransferHudChip.swift`

The chip only renders when `controller.hasActive`. Users paste an image and nothing visible happens — the chip appears but they don't look at the toolbar. Auto-open the popover for 2.5 seconds when `activeCount` goes 0 → 1+, so users see the progress bar start, then let it auto-close.

- [ ] **Step 1: Update TransferHudChip to auto-open**

Replace the body of `TransferHudChip.body` (lines 10-22) with:

```swift
    var body: some View {
        if controller.hasActive {
            chip
                .onTapGesture { popoverOpen.toggle() }
                .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                    TransferPopoverView(controller: controller)
                }
                .onChange(of: controller.activeCount) { oldValue, newValue in
                    if newValue > oldValue {
                        pulseToken = UUID()
                        // First transfer kicked off: surface the popover
                        // briefly so the user notices. Subsequent jobs only
                        // re-pulse (no nested auto-open) unless the chip was
                        // previously idle.
                        if oldValue == 0 {
                            popoverOpen = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2.5))
                                // Only auto-dismiss if the user hasn't
                                // interacted; if they manually opened it or
                                // it's still open because they're watching,
                                // leave it.
                                if popoverOpen && userDidNotInteract {
                                    popoverOpen = false
                                }
                            }
                        }
                    }
                }
                .modifier(PulseOnToken(token: pulseToken))
        }
    }
```

And add a state flag just below the existing `@State` decls (line 8-9):

```swift
    @State private var userDidNotInteract: Bool = true
```

Then, inside `.onTapGesture`, flip it:

```swift
                .onTapGesture {
                    userDidNotInteract = false
                    popoverOpen.toggle()
                }
```

Full replacement for the `if controller.hasActive { ... }` block:

```swift
        if controller.hasActive {
            chip
                .onTapGesture {
                    userDidNotInteract = false
                    popoverOpen.toggle()
                }
                .popover(isPresented: $popoverOpen, arrowEdge: .top) {
                    TransferPopoverView(controller: controller)
                }
                .onChange(of: controller.activeCount) { oldValue, newValue in
                    if newValue > oldValue {
                        pulseToken = UUID()
                        if oldValue == 0 {
                            popoverOpen = true
                            userDidNotInteract = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2.5))
                                if popoverOpen && userDidNotInteract {
                                    popoverOpen = false
                                }
                            }
                        }
                    }
                }
                .modifier(PulseOnToken(token: pulseToken))
        }
```

- [ ] **Step 2: Build + manual smoke**

Run:
```bash
xcodebuild -project apps/Cairn.xcodeproj -scheme Cairn -configuration Debug build -quiet
```

Manually: paste a clipboard image or a large local file into a remote tab. Expected: toolbar popover auto-opens for ~2.5s showing the live progress bar, then auto-dismisses. If the user clicks during that window, the popover stays open until they click away.

- [ ] **Step 3: Commit**

```bash
git add apps/Sources/Views/Transfer/TransferHudChip.swift
git commit -m "feat(transfer): auto-open HUD popover on first active transfer"
```

---

## Task 4 (throughput): Pipeline SFTP writes

**Files:**
- Modify: `crates/cairn-ssh/src/sftp.rs`
- Modify: `crates/cairn-ssh/Cargo.toml` (add `futures` workspace dep if missing)

Current upload loop (`crates/cairn-ssh/src/sftp.rs:373-397`) is strictly serial: read chunk → write chunk → await ack → repeat. On a 30ms-RTT SSH tunnel, serial 256 KiB writes cap throughput at ~8.5 MB/s regardless of link bandwidth. Pipelining N outstanding writes raises the ceiling roughly N×.

Use `futures::stream::FuturesOrdered` with `MAX_IN_FLIGHT = 16`. Keep chunks ordered (SFTP WRITE is offset-addressed so ordering isn't strictly required, but ordered drain keeps progress monotonic and simplifies error handling). `self.session` is `Arc<RawSftpSession>` (`sftp.rs:45`) so `Arc::clone(&self.session)` is cheap.

- [ ] **Step 1: Add the `futures` import**

Ensure `crates/cairn-ssh/Cargo.toml` has:
```toml
futures = { workspace = true }
```
And the workspace root `Cargo.toml` has under `[workspace.dependencies]`:
```toml
futures = "0.3"
```

At the top of `crates/cairn-ssh/src/sftp.rs` add:
```rust
use futures::stream::{FuturesOrdered, StreamExt};
```

- [ ] **Step 2: Replace the upload loop with a pipelined variant**

In `crates/cairn-ssh/src/sftp.rs::upload`, replace the serial `loop { … }` body (currently starting at line ~378 with `let n = src.read(&mut buf)…`) with:

```rust
        const CHUNK: usize = 256 * 1024;
        const MAX_IN_FLIGHT: usize = 16;

        let mut in_flight: FuturesOrdered<_> = FuturesOrdered::new();
        let mut offset: u64 = 0;
        let mut total: u64 = 0;
        let mut eof_reached = false;

        loop {
            if cancel.is_cancelled() {
                let _ = self.session.close(handle.as_str()).await;
                return Err(SshError::Cancelled);
            }

            while !eof_reached && in_flight.len() < MAX_IN_FLIGHT {
                let mut buf = vec![0u8; CHUNK];
                let n = src.read(&mut buf).await.map_err(SshError::Io)?;
                if n == 0 {
                    eof_reached = true;
                    break;
                }

                buf.truncate(n);
                let chunk_offset = offset;
                let n_u64 = n as u64;
                offset += n_u64;

                let write_fut = {
                    let handle = handle.clone();
                    let session = Arc::clone(&self.session);
                    async move {
                        session
                            .write(handle.as_str(), chunk_offset, buf)
                            .await
                            .map(|_| n_u64)
                    }
                };

                in_flight.push_back(write_fut);
            }

            if in_flight.is_empty() {
                break;
            }

            match in_flight.next().await {
                Some(Ok(n)) => {
                    total += n;
                    progress(total);
                }
                Some(Err(e)) => {
                    let _ = self.session.close(handle.as_str()).await;
                    return Err(map_sftp_err(e));
                }
                None => break,
            }
        }
```

- [ ] **Step 3: Build and run Rust tests**

Run:
```bash
cargo test -p cairn-ssh 2>&1 | tail -30
./scripts/build-rust.sh
```
Expected: compiles + existing tests pass.

- [ ] **Step 4: Manual throughput test**

1. Prepare a 100 MB local file: `dd if=/dev/urandom of=/tmp/testfile bs=1M count=100`.
2. Paste into a remote tab. Observe the speed in the HUD popover.
3. Expected: sustained speed substantially higher than pre-change (target: >20 MB/s on LAN, >5 MB/s on 30ms-RTT link).

- [ ] **Step 5: Commit**

```bash
git add crates/cairn-ssh/src/sftp.rs crates/cairn-ssh/Cargo.toml Cargo.toml
git commit -m "perf(ssh): pipeline SFTP writes up to 16 outstanding chunks"
```

---

## Final integration test

- [ ] **Step 1: Run all tests**

```bash
./scripts/build-rust.sh
xcodebuild test -project apps/Cairn.xcodeproj -scheme Cairn 2>&1 | tail -40
cargo test --workspace 2>&1 | tail -20
```

- [ ] **Step 2: Manual end-to-end scenario**

1. Connect to a remote host.
2. Take a screenshot (⌘⇧4 area selection to clipboard).
3. Switch to the remote tab and press ⌘V.
4. Expected:
   - HUD popover auto-opens almost immediately.
   - Progress bar advances from 0% to 100% smoothly.
   - Speed and ETA display after the first ~0.5s.
   - Popover auto-dismisses ~2.5s after transfer start.
5. Drag a 50 MB file from Finder onto the remote tab.
6. Expected: same live progress, faster sustained throughput than before.

## Self-review checklist

- [ ] Task 1: `h.progress.store(0, ...)` at the top of both `sftp_upload_sync` and `sftp_download_sync`.
- [ ] Task 2: `runWithProgressPolling` helper exists + used in both `uploadFromLocal` and `downloadToLocal`; `@escaping` added to protocol signatures.
- [ ] Task 2: unit tests pass.
- [ ] Task 3: HUD popover auto-opens on 0→1+ transition; user-tap flag preserves open state.
- [ ] Task 4: upload loop now pipelines (MAX_IN_FLIGHT=16 via FuturesOrdered); Rust tests pass.
- [ ] Manual screenshot-paste → progress visible, speed reasonable.

## Out of scope (track as follow-ups)

- **Download pipelining.** Same technique as Task 4 applies to `download` (issue N reads at increasing offsets via `FuturesOrdered`). Defer unless download-heavy flows (preview fetch, SSH-to-SSH `copyInPlace` through the temp-file path, download-to-local drag) become a pain point.
- **Multi-file batch progress.** Current `TransferController` displays one row per file; a batch drag of 100 files shows 100 rows. Add a batch summary header in a follow-up.
- **In-line progress indicator on the file row.** Currently only the toolbar HUD shows progress. A placeholder row in the remote listing with its own spinner (while upload is in flight) would make the location+progress obvious. Track separately.
- **Resume partial uploads.** Right now an error leaves a partial remote file and the retry re-uploads from scratch. Implement SFTP fstat → seek → resume in a future pass.
