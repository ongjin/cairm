# Cairn SSH/SFTP — v1 Design · `phase-2-ssh-v1`

> **Status:** Brainstorm complete (2026-04-23). Ready for `superpowers:writing-plans`.

**Goal.** Cairn이 `~/.ssh/config`에 등록된 임의 호스트(또는 one-off `user@host:port`)에 SFTP로 연결해서 원격 디렉터리를 **기존 Tab 추상화 확장으로** 탐색하고, 기본 파일 조작(rename/delete/mkdir) + drag-drop 양방향 전송을 수행하게 한다. Cloudflare Tunnel / AWS SSM 같은 `ProxyCommand` 경유 호스트를 1급 시민으로 지원 — 유저가 터미널에서 `ssh myhost`로 붙는 모든 호스트가 Cairn에서도 그대로 동작.

**Scope 리스크 (명시).** 이 spec은 단일 마일스톤으로 M1.8에 비견되는 규모(예상 4-6주, 중간 tag 없음). `FileSystemProvider` 추상화 도입으로 기존 `Tab`/`FolderModel`/`FileListCoordinator` 경로가 refactor 대상이 되며, `cairn-ssh`라는 신규 Rust crate + russh/russh-sftp 도입으로 바이너리 크기 +3-5MB. Brainstorm 단계에서 풀 FileZilla-parity 대안 제시했으나 v1에서는 **"연결 + 단일 페인 + drag-drop + 기본 ops"** 로 좁힘 (Q1 결정). 듀얼 페인, 전송 큐 매니저, resume/retry, edit-in-place, content search 등은 M2로 명시적 연기 (Section 7 참조).

**Architecture pivot.** 로컬 전용 `CairnEngine.listDirectory(url)` 경로를 `FileSystemProvider` 프로토콜로 일반화. `Tab`이 `provider: FileSystemProvider`를 보유하고, `FileListCoordinator`의 파일 조작(rename/delete/mkdir/drag-drop)은 provider-dispatched. 로컬 동작은 `LocalFileSystemProvider`가 기존 `CairnEngine` 래퍼로 pass-through — 회귀 방지가 v1의 critical path.

**Tech Stack.** Swift 5.9 · SwiftUI · AppKit · macOS 14 · xcodegen | Rust 1.85 · swift-bridge 0.1.59 · **russh 0.44 (new)** · **russh-sftp 2.0 (new)** · **russh-keys 0.44 (new)** · **sha2 0.10 (new)** · tokio 1 · OpenSSH client (macOS 기본, `ssh -G` 호출용)

**바이너리 번들 영향.** 신규 OpenSSH 바이너리 번들 **없음** (macOS 기본 `/usr/bin/ssh` 사용). Rust static lib 크기 +3-5MB (lto=true + strip 후).

**Working directory:** `/Users/cyj/workspace/personal/cairn` (main, HEAD 시작 ≈ `bbf9505`)

**Predecessor:** M1.8 (`docs/superpowers/plans/2026-04-22-cairn-phase-1-m1.8-unified.md`, 완료)

**Deliverable verification:**
- `cargo fmt --check` / `cargo clippy -D warnings` / `cargo test --workspace` 전부 green (신규 `cairn-ssh` crate 포함)
- `xcodebuild test` PASS — 기존 60+ tests + 신규 ~15 tests (SSH provider / pool / config parse / TOFU resolver / transfer controller)
- `make build && make run` 후 수동 DoD checklist (Section 6.2) 전 항목 PASS
- `git tag phase-2-ssh-v1` + 다음 alpha 버전 tag

---

## 1. Brainstorm 결정 요약

Brainstorm 세션 (2026-04-23) 에서 아래 선택:

| # | 질문 | 선택 | 요지 |
|---|---|---|---|
| Q1 | 마일스톤 경계 | **C** | Hybrid — v1은 connect infra + single-pane + drag-drop, M2는 dual-pane + queue + advanced |
| Q2 | v1 usefulness 경계 | **B** | `~/.ssh/config` 완전 존중 (ProxyCommand / ProxyJump / Match / Include) |
| Q3 | 원격 탭 표현 | **B** | SSH 배지 + `ssh://` scheme 접두사 + 사이드바 "Remote Hosts" 섹션 |
| Q4 | 백엔드 | **C** | russh + `ssh -G`로 config 해석 + tokio subprocess로 ProxyCommand 실행 |
| Q5 | 인증 범위 | **C** | Agent + key file + passphrase 모달(Keychain 옵션). password/kbd-interactive 제외 |
| Q6 | 호스트 키 | **B** | TOFU 모달 + shared `~/.ssh/known_hosts`. Changed key는 accept 불가 |
| Q7 | 프로파일 source | **B** | ssh_config 읽기 + append-only writer + sidecar metadata JSON |
| Q8 | 원격 ops 범위 | **C** | Browse + transfer + rename/delete/mkdir/refresh + "Reveal on Host". chmod/trash 제외 |
| Q9 | 전송 UX | **B** | Toolbar HUD chip + popover per-transfer. Drop 시 pulse. |
| Q10 | 원격 검색 | **B** | Folder-scope 인메모리 필터만. subtree/content는 M2 |
| Q11 | preview/QL | **C** | 텍스트 head streaming + lazy QL 전체 다운로드 캐시 + read-only Open With |
| Q12 | 연결 수명 | **B** | 호스트 공유 풀 + 5분 idle timeout + 수동 Disconnect/Reconnect |

---

## 2. Architecture

### 2.1 Rust 레이어 — 신규 `crates/cairn-ssh/`

기존 7개 crate에 하나 추가: `cairn-core`, `cairn-walker`, `cairn-search`, `cairn-preview`, `cairn-index`, `cairn-git`, `cairn-ffi`, **`cairn-ssh`**.

**의존성** (`crates/cairn-ssh/Cargo.toml`):

```toml
[dependencies]
russh       = "0.44"
russh-sftp  = "2.0"
russh-keys  = "0.44"
tokio       = { version = "1", features = ["full"] }
sha2        = "0.10"
thiserror   = { workspace = true }
anyhow      = { workspace = true }
parking_lot = "0.12"
tracing     = "0.1"
```

**모듈 구성** (`crates/cairn-ssh/src/`):

- `lib.rs` — 공개 API (`SshPool`, `SshSession`, `SftpHandle`, `ConnectSpec`, `ResolvedConfig`, `HostKeyResolver`, `PassphraseResolver`)
- `config.rs` — `ssh -G <host>` subprocess 실행 + 출력 파싱 → `ResolvedConfig`. Shallow `~/.ssh/config` parser (호스트 이름 목록만 추출)
- `proxy.rs` — `ProxyCommand` subprocess + `AsyncRead + AsyncWrite` 어댑터 (`ChildIoStream`)
- `auth.rs` — Agent → unencrypted key → encrypted key(passphrase callback) 시퀀스
- `hostkey.rs` — SHA256 fingerprint 계산, `known_hosts` plain + `HashKnownHosts` 파싱/append, TOFU `HostKeyResolver` trait
- `pool.rs` — `HashMap<ConnKey, Arc<SshSessionInner>>` + idle reaper task (tokio interval)
- `sftp.rs` — `SftpHandle` 메서드 (list, stat, mkdir, rmdir, unlink, rename, open_read, open_write, readlink)
- `transfer.rs` — stream 기반 read/write 어댑터 + cancel flag 체크포인트
- `error.rs` — `SshError` enum (thiserror)
- `known_hosts_hash.rs` — `|1|salt|hash` HMAC-SHA1 match (russh-keys가 기본 지원 안 하면 자체 구현, 100줄 이내)

**비동기 모델.** 모든 I/O는 tokio async. FFI 경계에서 Rust runtime을 1개 유지(`tokio::runtime::Runtime` 싱글톤) + Swift에서 `Task.detached`로 호출하여 main thread 블록 회피.

### 2.2 Swift 레이어 — `FileSystemProvider` 추상화

**현 상태.** `FolderModel.load(_ url: URL)` → `engine.listDirectory(url)`가 로컬 전용. `FileListCoordinator`의 rename/delete/drag-drop은 `FileManager.default` + `URL(fileURLWithPath:)`에 직접 의존.

**목표.** provider 분기 하나로 로컬/원격 통합.

```swift
// apps/Sources/Services/FileSystemProvider.swift (신규)
protocol FileSystemProvider: AnyObject {
    var identifier: ProviderID { get }       // .local | .ssh(SshTarget)
    var displayScheme: String? { get }       // nil | "ssh://"
    var supportsServerSideCopy: Bool { get } // SFTP copy-data extension 유무

    func list(_ path: FSPath) async throws -> [FileEntry]
    func stat(_ path: FSPath) async throws -> FileStat
    func mkdir(_ path: FSPath) async throws
    func rename(from: FSPath, to: FSPath) async throws
    func delete(_ paths: [FSPath]) async throws

    func openRead(_ path: FSPath) async throws -> FSReadStream
    func openWrite(_ path: FSPath, truncate: Bool) async throws -> FSWriteStream

    // server-side copy (같은 remote 내 paste). 미지원이면 client-mediated fallback
    func copyInPlace(from: FSPath, to: FSPath) async throws

    // preview pane용 head read
    func readHead(_ path: FSPath, max: Int) async throws -> Data
    // Quick Look / Open With용 캐시 다운로드
    func downloadToCache(_ path: FSPath) async throws -> URL
}

struct FSPath: Hashable, Codable {
    let provider: ProviderID
    let path: String              // POSIX path, provider 내부에서 의미
}

enum ProviderID: Hashable, Codable {
    case local
    case ssh(SshTarget)           // SshTarget은 ConnKey의 Swift 미러
}
```

**구현체.**

- `LocalFileSystemProvider` — 기존 `CairnEngine` + `FileManager` 래퍼. 동작 변화 없음.
- `SshFileSystemProvider` — `cairn-ssh`의 `SftpHandle`을 FFI 경유로 호출. 모든 메서드는 pool에서 session 조회 → SFTP handle 보유 → op 실행.

**Tab 수정.**

```swift
// 현행
final class Tab {
    let folder: FolderModel           // load(url: URL)
    var history: NavigationHistory    // stack of URL
}

// v1
final class Tab {
    let folder: FolderModel           // load(path: FSPath)
    let provider: FileSystemProvider
    var history: NavigationHistory    // stack of FSPath
}
```

**breadcrumb / navigate / goUp**: 모두 `FSPath` scoped. Provider의 display 규칙(로컬은 `~` 축약, 원격은 `/` 루트) 존중.

**copy/paste 분기점.** `FileListCoordinator.pasteFromClipboard`는 source와 destination의 `ProviderID`를 비교해서:
- 같은 provider → provider.copyInPlace (서버사이드)
- 다른 provider → cross-provider transfer (`TransferController.enqueue`)

### 2.3 FFI 경계

`crates/cairn-ffi/src/ssh.rs` (새 모듈)에서 swift-bridge로 노출:

```rust
#[swift_bridge::bridge]
mod ssh_ffi {
    extern "Rust" {
        type SshPool;
        type SshSession;
        type SftpHandle;

        fn pool_new() -> SshPool;
        fn pool_list_configured_hosts(pool: &SshPool) -> Vec<String>;
        fn pool_resolve_config(pool: &SshPool, host: &str) -> Result<ResolvedConfigBridge, String>;
        fn pool_connect(
            pool: &SshPool,
            spec: ConnectSpecBridge,
            hostkey_cb: HostKeyCallback,    // Swift가 구현
            auth_cb: AuthCallback,          // Swift가 구현
        ) -> Result<SshSession, String>;
        fn session_sftp(session: &SshSession) -> Result<SftpHandle, String>;
        fn session_disconnect(session: SshSession);

        // SFTP ops
        fn sftp_list(h: &SftpHandle, path: &str) -> Result<Vec<FileEntryBridge>, String>;
        fn sftp_stat(h: &SftpHandle, path: &str) -> Result<FileStatBridge, String>;
        fn sftp_mkdir(h: &SftpHandle, path: &str) -> Result<(), String>;
        fn sftp_rename(h: &SftpHandle, from: &str, to: &str) -> Result<(), String>;
        fn sftp_delete(h: &SftpHandle, path: &str) -> Result<(), String>;
        fn sftp_read_head(h: &SftpHandle, path: &str, max: u32) -> Result<Vec<u8>, String>;

        // Stream ops — callback 기반 progress
        fn sftp_download(h: &SftpHandle, remote: &str, local: &str, progress_cb: ProgressCallback, cancel_flag: CancelFlag) -> Result<(), String>;
        fn sftp_upload(h: &SftpHandle, local: &str, remote: &str, progress_cb: ProgressCallback, cancel_flag: CancelFlag) -> Result<(), String>;
        fn sftp_server_side_copy(h: &SftpHandle, from: &str, to: &str) -> Result<(), String>;

        fn pool_idle_reap(pool: &SshPool);
        fn pool_close_all(pool: &SshPool);
    }
}
```

**콜백 패턴.** Rust → Swift 콜백은 swift-bridge가 지원 (`extern "Swift"` 블록). `hostkey_cb`(TOFU 결정) / `auth_cb`(passphrase 요청)는 Swift가 `@MainActor` NSAlert/Sheet 띄우고 tokio `oneshot::channel`로 응답 반환. 동시 여러 연결의 모달 충돌 방지 위해 Swift 쪽 `HostKeyAlertResolver` / `PassphraseResolver`를 `actor`로 직렬화.

**에러 타입.** FFI 경계에서는 `Result<T, String>`으로 단순화. Swift 쪽 어댑터에서 `SshErrorKind`로 재분류 (Section 5.1 매핑 테이블).

### 2.4 ProxyCommand 실행 경로

```rust
// proxy.rs
async fn dial_with_proxy(proxy_cmd: &str, host: &str, port: u16, user: &str) -> Result<ProxyStream, SshError> {
    // ssh_config의 %h / %p / %r 토큰 치환
    let expanded = expand_tokens(proxy_cmd, host, port, user);

    // /bin/sh -c 로 실행 (proxy_cmd는 shell 문법 포함 가능 — pipe, env, etc.)
    let mut child = Command::new("/bin/sh")
        .arg("-c").arg(&expanded)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| SshError::ProxyCommandSpawn { cmd: expanded.clone(), source: e })?;

    let stderr = child.stderr.take().unwrap();
    // stderr는 별도 task로 line-by-line 수집 (연결 실패 진단용, 앞 8KB까지)
    let stderr_buf = spawn_stderr_collector(stderr);

    let stdin = child.stdin.take().unwrap();
    let stdout = child.stdout.take().unwrap();

    // AsyncRead + AsyncWrite 어댑터
    Ok(ProxyStream::new(stdout, stdin, child, stderr_buf))
}
```

**russh와 연결.** `ProxyStream`이 `AsyncRead + AsyncWrite + Send + Unpin`을 구현하면 `russh::client::connect_stream(config, stream, handler)`에 그대로 투입 가능.

**ProxyJump 처리.** 현대 OpenSSH (8.x+)는 `ssh -G` 출력 시 `ProxyJump`가 설정되어 있으면 내부적으로 `ProxyCommand ssh -W %h:%p <jumphost>` 체인을 생성해 **`proxycommand` 필드에 함께 emit** 하는 경우가 많음. v1은 실용적으로:
1. `ResolvedConfig.proxy_command`가 non-empty면 그대로 사용 (ProxyJump도 이 경로로 자동 커버되는 경우)
2. `proxy_command`는 empty인데 `proxy_jump`가 set인 경우 → `SshError::ProxyJumpNotSupported` (actionable error: "Add `ProxyCommand ssh -W %h:%p <jumphost>` to ssh_config, or wait for M2 native support"). macOS 기본 OpenSSH는 대부분 1번 경로로 빠지므로 실제로는 거의 발생 안 함.

**Cloudflare Tunnel / AWS SSM.** 둘 다 ProxyCommand로 이미 동작. 유저 ssh_config:

```ssh_config
Host prod-via-cf
    HostName internal-host.example.com
    ProxyCommand cloudflared access ssh --hostname %h

Host ec2-via-ssm
    HostName i-0abc123456789
    User ec2-user
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters "portNumber=%p"
```

둘 다 v1에서 즉시 동작 — v1은 `ProxyCommand`를 2.4 로직대로 spawn하면 끝.

---

## 3. Data model + pool lifecycle

### 3.1 Connection profile

**Source of truth.** `~/.ssh/config` + Include 경로의 파일들. Cairn은 읽기만 적극적으로, 쓰기는 "Save to ssh_config" 액션에서만 append-only.

**사이드바 호스트 목록 추출** (`cairn-ssh::config::list_configured_hosts`):

```rust
pub fn list_configured_hosts() -> Vec<String> {
    parse_host_blocks(&read_config_with_includes())
        .into_iter()
        .filter(|h| !h.contains('*') && !h.contains('?'))   // wildcard skip
        .filter(|h| !h.starts_with("Match"))                // Match 블록 skip
        .collect()
}
```

와일드카드 / Match 블록은 사이드바에 안 나타나지만, 유저가 Connect sheet에서 명시적으로 `deploy@prod-web01`을 치면 Match 규칙은 `ssh -G`에 의해 여전히 적용됨.

**Include 추적.** v1은 `~/.ssh/config`의 top-level `Include` 지시자만 따라감 (흔한 `Include config.d/*` 패턴 대응). 재귀 Include는 depth 5까지.

**Sidecar metadata** — 호스트 이름 키, Cairn-전용 추가 정보:

위치: `~/Library/Application Support/Cairn/host-metadata.json` (**구현 첫날 `BookmarkStore`/`SettingsStore`와 경로 컨벤션 맞추기**).

```json
{
  "prod-api": {
    "lastConnectedAt": "2026-04-23T10:15:00Z",
    "pinned": true,
    "hiddenFromSidebar": false,
    "lastKnownState": "ok"
  },
  "staging-db": {
    "lastConnectedAt": null,
    "pinned": false,
    "hiddenFromSidebar": false
  }
}
```

ssh_config과 완전 직교. 호스트 이름이 변경되면 엔트리는 고아 상태로 남음 — v1엔 관리 UI 없음(`Clear Remote Cache`와 같이 `Clean Host Metadata` 메뉴 아이템으로 prune 가능).

**File watcher.** `FSEventsStream`으로 `~/.ssh/config` + 추적된 Include 파일들 watch. 변경 시 `SidebarModel` 의 `hosts` 섹션 reload. 기존 `FolderWatcher` 패턴 재사용.

### 3.2 ResolvedConfig — `ssh -G` 매핑

```rust
#[derive(Debug, Clone)]
pub struct ResolvedConfig {
    pub hostname: String,
    pub port: u16,
    pub user: String,
    pub identity_files: Vec<PathBuf>,
    pub identity_agent: Option<PathBuf>,            // "SSH_AUTH_SOCK" literal은 env로 해석됨
    pub proxy_command: Option<String>,              // 미치환 상태 (%h/%p/%r 포함)
    pub proxy_jump: Option<String>,
    pub server_alive_interval: Duration,            // 0이면 30s 강제 (russh 측 keepalive)
    pub server_alive_count_max: u32,
    pub strict_host_key_checking: StrictMode,       // Yes | AcceptNew | Ask | No
    pub user_known_hosts_file: Vec<PathBuf>,
    pub global_known_hosts_file: Vec<PathBuf>,
    pub host_key_algorithms: Vec<String>,
    pub preferred_authentications: Vec<String>,
    pub compression: bool,
    pub hash_known_hosts: bool,
}
```

**파싱.** `ssh -G <host>`는 lowercase-key `value` 라인. 간단 `HashMap<String, Vec<String>>` → typed struct.

**ConnKey (풀 dedup 키):**

```rust
#[derive(Debug, Clone, Hash, PartialEq, Eq)]
pub struct ConnKey {
    pub user: String,
    pub hostname: String,                           // resolved
    pub port: u16,
    pub config_hash: [u8; 16],                      // sha256(proxy_command + identity_files + host_key_algorithms + ...)[..16]
}
```

ssh_config 편집으로 resolution 달라지면 새 Key → pool miss → 새 연결. 의도대로.

### 3.3 Pool lifecycle

**상태 전이:**

```
  [no session]
        │
        ▼  connect()
    Connecting
        │
   auth success
        │
        ▼                    sftp_op() → lastActivity 갱신
     Active ──────────────────────────────────┐
        │                                      │
        │   5min no activity                   │
        ▼                                      │
      Idle ── sftp_op() / connect() ───────────┘
        │
        │   disconnect() / app quit / keepalive fail
        ▼
   Terminated
```

**Swift 소유.**

```swift
@Observable
final class AppModel {
    // … existing (engine, bookmarks, lastFolder, settings, mountObserver, sidebar)
    let ssh: SshPoolService                         // NEW
}

@Observable
final class SshPoolService {
    private let ffiPool: SshPool                    // Rust
    private(set) var sessions: [ConnKey: SshSessionState]

    func connect(host: String,
                 hostkeyResolver: HostKeyResolver,
                 passphraseResolver: PassphraseResolver) async throws -> SshSessionRef
    func sessionFor(_ key: ConnKey) -> SshSessionRef?
    func disconnect(_ key: ConnKey)
    func refreshIdleReaper()                        // Timer (60s) → FFI pool_idle_reap
}

struct SshSessionState {
    var status: Status                              // .connecting | .active | .idle | .error(String)
    var lastActivity: Date
    var resolvedConfig: ResolvedConfig              // 사이드바 tooltip용
}
```

**Tab의 참조.** 원격 Tab이 session을 직접 hold하지 않음 — 매 op마다 `pool.sessionFor(key)` 조회. 탭 닫아도 pool은 유지(5분 grace). 마지막 tab이 닫혀도 즉시 disconnect 안 함.

**App quit.** `NSApplicationWillTerminate` notification → `pool.close_all()` (gracefully).

### 3.4 Transfer 모델

```swift
struct TransferJob: Identifiable {
    let id: UUID
    let source: FSPath
    let destination: FSPath
    let sizeHint: Int64?
    var bytesCompleted: Int64
    var state: State                                // .queued | .running | .completed | .cancelled | .failed(String)
    var startedAt: Date?
    var finishedAt: Date?
    let cancelFlag: CancelFlag                      // atomic bool (FFI 경유로 Rust에도 전달)
}

@Observable
final class TransferController {
    private(set) var jobs: [TransferJob]            // 최근 100개 유지
    var activeCount: Int { jobs.filter { $0.state == .queued || $0.state == .running }.count }

    func enqueue(_ job: TransferJob)
    func cancel(_ id: UUID)
    func retry(_ id: UUID)                          // failed/cancelled → re-enqueue (새 job id)
    func cancelAll()
}
```

**실행 모델.**

- **호스트당 serial (동시 1개)** — 같은 remote host에 대해 Transfer는 직렬 실행. 다른 호스트 / 로컬 transfer는 병렬 OK. 서버 부하 보호 + 큐 매니저 없는 v1의 단순화.
- **Progress** — `sftp_download` / `sftp_upload`의 `ProgressCallback`이 1초 주기로 bytes 누적 값을 Swift에 전달 → `TransferJob.bytesCompleted` 갱신.
- **Cancel** — `CancelFlag`의 atomic bool을 check-point마다 확인. 부분적으로 쓰인 파일은 **삭제하지 않음** (유저 파악 가능).
- **Directory drop** — 폴더를 drop하면 provider traversal 후 개별 TransferJob들로 expand + mkdir sequence. Preserve 구조.

**소유자.** `AppModel.transfers: TransferController` (single instance, all windows/tabs share). Multi-window면 popover는 window별로 같은 controller를 바인딩.

### 3.5 Host key 신뢰 데이터 흐름

```rust
#[async_trait]
pub trait HostKeyResolver: Send + Sync {
    async fn resolve(
        &self,
        host: &str,
        port: u16,
        offered_key: &PublicKey,
        known: KnownResult,
    ) -> TofuDecision;
}

pub enum KnownResult {
    Match,
    NotFound,
    Mismatch { stored: PublicKey },
}

pub enum TofuDecision {
    Accept,
    AcceptAndSave,
    Reject,
}
```

**Swift 구현** — `HostKeyAlertResolver: HostKeyResolver` actor:

```swift
actor HostKeyAlertResolver: HostKeyResolver {
    func resolve(host: String, port: UInt16, offeredKey: PublicKey, known: KnownResult) async -> TofuDecision {
        switch known {
        case .match:     return .accept
        case .mismatch:  return await presentChangedKeyAlert(...)    // [Cancel] only
        case .notFound:  return await presentTofuAlert(...)          // [Cancel / Accept Once / Accept & Save]
        }
    }
}
```

**Known_hosts 접근:**

- **읽기**: `resolved.user_known_hosts_file` 순서대로 → `global_known_hosts_file`. Plain + hashed (`|1|salt|hash`) 둘 다 match.
- **쓰기** (`AcceptAndSave`): 첫 번째 `user_known_hosts_file`에 append. `HashKnownHosts yes`면 해시 포맷:
  ```
  |1|<base64 salt>|<base64 hash>  ssh-ed25519 AAAAC3Nz...
  ```
- 파일 없으면 `0600` 퍼미션으로 신규 생성.

**Changed key.** `Mismatch` → `[Cancel]`만 있는 빨간 alert + 메시지: "Cannot accept — manually verify and edit `~/.ssh/known_hosts`. In terminal: `ssh-keygen -R <host>`". `Reject` 반환 → 연결 abort.

---

## 4. UI 표면

### 4.1 사이드바 — "Remote Hosts" 섹션

기존 섹션(Pinned / Home / Recent) **아래**에 신규 섹션. `SidebarModel`에 `hosts: [RemoteHostItem]`.

```
┌──────────────────┐
│ Pinned           │
│   📌 Projects    │
│   📌 Downloads   │
│                  │
│ Remote Hosts     │
│   🟢 prod-api    │   ← 활성 세션
│   🟡 staging-db  │   ← idle grace
│   ⚪ dev-tunnel  │   ← 미연결
│   + Connect…     │   ← Connect sheet 열기
└──────────────────┘
```

**정렬.** `lastConnectedAt` 최근순 → `pinned: true` 우선.

**Row 구성.** dot indicator + 호스트 이름 + (pinned면 📌 아이콘 suffix).

**Hover tooltip.** `user@hostname:port · last connected 5m ago · via cloudflared` (ProxyCommand 요약).

**우클릭 메뉴:**
- `Connect` (✓ 새 탭, 기존 세션 재사용)
- `Disconnect` (해당 키의 session 종료)
- `Reveal ssh_config entry` (Finder에서 `~/.ssh/config` 선택 + 해당 Host 블록 라인 점프는 v1엔 skip, 파일만 reveal)
- `Copy ssh command` (`ssh user@host -p port` clipboard 복사)
- `Hide from sidebar` (sidecar metadata `hiddenFromSidebar: true`)

**선택 동작.** 단일 클릭 → 해당 호스트로 새 탭 열고 home 디렉터리(`.`) 이동. 이미 active session 있으면 재사용.

**Dot 색상.** Glass Blue 테마 톤에 맞춘 파스텔 팔레트 — **디자인 폴리시 단계에서 확정**:
- 활성 `#6ad99b` 계열 (teal-green)
- idle `#d9c56a` 계열 (muted amber)
- 미연결 `#555c6b` 계열 (neutral gray)
- 에러 `#ff8888` 계열 (pastel red)

### 4.2 Connect sheet

**진입**:
- 사이드바 `+ Connect…` 클릭
- File 메뉴 → `Connect to Server…` (⇧⌘K — 기존 ⌘K palette와 충돌 안 하는 mod key)
- `⌘K` palette에서 "Connect to Server…" 커맨드

```
┌─────────────────────────────────────┐
│ Connect to Server                   │
├─────────────────────────────────────┤
│ Server:   [deploy@prod-api]  :[22] │
│ Path:     [/var/log/nginx]          │
│                                     │
│ Auth:     (•) Agent                 │
│           ( ) Key file              │
│               [~/.ssh/id_ed25519] 📁│
│                                     │
│ Advanced ▾                          │
│   Custom ProxyCommand:              │
│   [cloudflared access ssh ...]      │
│                                     │
│ □ Save to ~/.ssh/config as:         │
│   [prod-api]                        │
│                                     │
│           [Cancel]      [Connect]   │
└─────────────────────────────────────┘
```

**동작:**
1. `Connect` → (Save checked면 먼저 ssh_config append) → `ssh -G <name>` 해석 → `pool.connect()` 흐름
2. URL bar에 `ssh://user@host:port/path` 붙여넣기 지원 — 필드 자동 채움
3. `Save to ssh_config` unchecked면 ephemeral 연결 (ConnKey는 메모리에만, pool에 존재)
4. `Advanced` 영역은 기본 collapsed. Custom ProxyCommand 입력하면 Save 시에도 ssh_config에 `ProxyCommand` 지시자 포함

### 4.3 Tab chrome

- **Tab chip:** 좌측 teal `SSH` 배지 + `<host>:<path-tail>` (middle-truncate)
- **Breadcrumb:** 첫 segment `ssh://<user>@<host>` (teal) + 경로 segments
- **Window title:** `<host> · <foldername>`
- **빈 디렉터리:** 기존 `EmptyStateView` 재사용 + "This folder is empty on `<host>`"

### 4.4 TOFU / Passphrase / Changed-key 모달

**TOFU (unknown host key):**

```
┌─────────────────────────────────────────┐
│ New host key for "prod-api"             │
│                                         │
│   SHA256: AbCd1234EfGh5678…             │
│   ed25519 (256-bit)                     │
│                                         │
│   ╭─────────╮                           │
│   │ ASCII   │   (ssh-keygen -l -f 스타일 │
│   │  art    │    fingerprint visual)    │
│   ╰─────────╯                           │
│                                         │
│ First connection to this host. Verify   │
│ the fingerprint matches the server.     │
│                                         │
│  [Cancel]  [Accept Once]  [Accept&Save] │
└─────────────────────────────────────────┘
```

**Changed key (빨간 스타일, accept 불가):**

```
┌─────────────────────────────────────────┐
│ ⚠︎ Host key CHANGED for "prod-api"      │
│                                         │
│ Stored:  SHA256: OldXy…                 │
│ Offered: SHA256: NewAb…                 │
│                                         │
│ Possible man-in-the-middle attack, or   │
│ the host was reinstalled. If legitimate,│
│ remove the old key in terminal:         │
│   ssh-keygen -R prod-api                │
│                                         │
│                          [Cancel]       │
└─────────────────────────────────────────┘
```

**Passphrase (encrypted key file):**

```
┌──────────────────────────────────────┐
│ Unlock ~/.ssh/id_ed25519             │
│                                      │
│ Passphrase: [••••••••••••]           │
│                                      │
│ □ Remember in Keychain               │
│                                      │
│         [Cancel]         [Unlock]    │
└──────────────────────────────────────┘
```

**Keychain 저장.** `kSecClassGenericPassword` / `account = "ssh-key:<absolute-path>"`. 다음 연결 시 먼저 Keychain lookup → hit면 prompt 생략.

### 4.5 Toolbar HUD chip + Transfer popover

**Chip** (`activeCount > 0`일 때만 등장):

- 컨텐츠: spinner(teal) + `↕ <count>`
- 위치: toolbar primaryAction 영역, 우측
- Drop 직후 1초 pulse 애니메이션 (scale 1.0 → 1.15 → 1.0, opacity 펄스)
- 클릭 → popover 토글

**Popover** (NSPopover, chip 아래 attached):

```
Active Transfers
─────────────────────────────────
⬆ build.tar.gz                43%
▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░
to prod-api:/srv/app · 512 KB/s
ETA 1m 20s · [Cancel]
─────────────────────────────────
⬆ dist.tar.gz          [Queued]
queued after build · [Cancel]

Recent
─────────────────────────────────
✓ config.yaml → prod-api (2s ago)
✗ schema.sql (connection lost) [Retry]
```

**Recent.** 성공한 건 3초 후 popover에서 fade (jobs 배열엔 남음). 실패/취소는 명시적 dismiss 전까지 남음.

### 4.6 Delete 확인 모달

원격 delete 는 undo 없음 → 확인 강제:

```
┌─────────────────────────────────────┐
│ Delete 3 items permanently?         │
│                                     │
│ From prod-api:/var/log/nginx/       │
│  • access.log                       │
│  • error.log                        │
│  • archive/  (folder)               │
│                                     │
│ □ Don't ask again for this session  │
│                                     │
│       [Cancel]        [Delete]      │
└─────────────────────────────────────┘
```

"Don't ask" 상태는 `Tab` scoped (앱 restart시 reset).

### 4.7 FileList 변경

- **Name 컬럼.** 기존 유지. 원격이면 icon이 확장자 기반 generic (SFTP로는 UTI 추론 불가).
- **Progress row.** Drop 직후 2초간 리스트 상단에 인라인 배너 "3 uploads running — see ↕ in toolbar". 이후 배너 사라짐, 모든 진행은 toolbar popover에서. (Q9 B 선택 반영.)
- **Modified 컬럼.** SFTP `stat` mtime — 클라이언트 로컬 타임존으로 변환 표시.
- **Size 컬럼.** 기존. Directory는 "—".
- **Git 컬럼.** 원격 탭에선 hide (v1 로컬 전용).
- **Name cell 편집.** 로컬과 동일한 ⏎ rename 경로 재사용 — provider.rename(from:to:) 분기만 변경.
- **drag-drop.** `tableView(_:pasteboardWriterForRow:)` + `tableView(_:acceptDrop:row:dropOperation:)` 경로에서 cross-provider 판정 → TransferController.enqueue OR provider.rename (local intra-tab move).

### 4.8 에러 인라인 상태

| 상황 | UI |
|---|---|
| 연결 중 | ProgressView + "Connecting to `<host>`…" (ProxyCommand 있으면 "Opening tunnel via `cloudflared`…") |
| Auth 실패 | 빨간 에러 카드 + "Authentication failed. [Retry] [Edit ssh_config] [Open Terminal]" |
| ProxyCommand 실패 (exit ≠ 0) | 에러 카드 + proxy stderr 앞 500자 + [Copy Error] 버튼 |
| Listing permission 실패 | `EmptyStateView` + "Permission denied on `<path>`. [Reveal on Host] [Go Up]" |
| 전송 실패 | Transfer popover row: `.failed` + "Retry" 링크 |
| Keepalive 실패 | 탭 오버레이 "Connection lost. [Reconnect] [Close Tab]" |

---

## 5. Error taxonomy + logging

### 5.1 에러 매핑

```rust
// cairn-ssh::error::SshError
#[derive(Debug, thiserror::Error)]
pub enum SshError {
    #[error("Couldn't resolve ssh_config for {host}: {msg}")]
    ConfigResolution { host: String, msg: String },

    #[error("Proxy command failed (exit {exit_code}): {stderr_preview}")]
    ProxyCommandFailed { exit_code: i32, stderr_preview: String },

    #[error("Couldn't spawn proxy command: {source}")]
    ProxyCommandSpawn { cmd: String, source: std::io::Error },

    #[error("ProxyJump without ProxyCommand is not supported in v1")]
    ProxyJumpNotSupported,

    #[error("Network unreachable: {host}:{port}")]
    NetworkUnreachable { host: String, port: u16 },

    #[error("Host key mismatch for {host} — possible MITM")]
    HostKeyMismatch { host: String },

    #[error("Host key not accepted")]
    HostKeyRejected,

    #[error("No authentication method succeeded (tried: {tried})")]
    AuthNoMethods { tried: String },

    #[error("Server requires {kind} authentication — not supported in v1")]
    AuthKindNotSupported { kind: &'static str },       // "password" | "keyboard-interactive"

    #[error("SFTP: {0}")]
    SftpProtocol(String),

    #[error("Permission denied: {0}")]
    SftpPermissionDenied(String),

    #[error("Not found: {0}")]
    SftpNotFound(String),

    #[error("No space left on remote")]
    SftpNoSpace,

    #[error("Connection to {host} lost")]
    ConnectionLost { host: String },

    #[error("Cancelled")]
    Cancelled,

    #[error(transparent)]
    Io(#[from] std::io::Error),
}
```

Swift 쪽 `SshErrorKind`로 재매핑 — 각 variant가 userMessage + technicalMessage (로깅 전용) 보유.

### 5.2 로깅 정책

- 기술 로그: `tracing::` (Rust) + `os_log` (Swift). Subsystem `com.cairn.ssh`.
- **민감 정보 절대 로깅 X:** passphrase, key file 내용, password, kbd-interactive 응답.
- `ProxyCommand` stderr는 **앞 8KB까지만** 메모리 보관 (연결 실패 진단용). 8KB 초과분은 drop. unified log에 전체 저장하지 않음 — ProxyCommand이 다른 민감 정보를 stderr에 뱉을 수 있음.

### 5.3 실패 복구 정책 (v1)

- 전송 실패 → popover에 row 남기고 `Retry` 수동. **auto-retry 없음.**
- Keepalive 실패 → session 상태 `.error` 전환 + tab 오버레이. 유저 `Reconnect` 클릭 필요. **auto 없음.**
- Passphrase 3회 연속 실패 → `AuthNoMethods` 로 승격, 모달 닫힘.

---

## 6. Test strategy + DoD

### 6.1 테스트

**Rust** (`crates/cairn-ssh/tests/`):
- `config_parse_test.rs` — `ssh -G` 출력 15+ 샘플 (plain, proxy, proxy-jump, wildcards, Match host, Include 체인)
- `known_hosts_test.rs` — plain + hashed (HMAC-SHA1) match + append writer
- `hostkey_fingerprint_test.rs` — SHA256 fingerprint = `ssh-keygen -l` 출력 일치
- `pool_test.rs` — dedupe by ConnKey, idle reap (fake clock), concurrent connect 중복 방지
- `proxy_command_test.rs` — ChildIoStream I/O 어댑터 + stderr 수집기
- `ssh_config_writer_test.rs` — append-only, 퍼미션 600 보존, round-trip parse

**Integration** (`crates/cairn-ssh/tests/integration/`): `docker run openssh-server` spawn해서 real handshake + SFTP round-trip 검증. `CAIRN_SSH_IT=1` 환경변수 required. CI에선 기본 skip, 로컬 + release 전에만 실행.

**Swift** (`apps/CairnTests/SSH/`):
- `FileSystemProviderTests.swift` — LocalFileSystemProvider round-trip
- `SshFileSystemProviderTests.swift` — FFI mock으로 provider 호출 검증
- `TransferControllerTests.swift` — enqueue / cancel / per-host serial
- `HostKeyAlertResolverTests.swift` — TOFU decision state machine
- `ConnectSheetModelTests.swift` — URL parse / save-to-config toggle
- `SshConfigWriterTests.swift` — append writer Swift fallback
- `HostMetadataStoreTests.swift` — sidecar JSON read/write/clean

**UI smoke.** XCUITest 추가 없음 (Cairn 기존 패턴). 대신 수동 DoD checklist (6.2).

### 6.2 DoD (마일스톤 완료 조건)

- [ ] `cargo fmt --check` / `cargo clippy -D warnings` / `cargo test --workspace` green (cairn-ssh 포함)
- [ ] `xcodebuild test` PASS — 기존 60+ tests + 신규 ~15 tests
- [ ] `make build && make run` 실행 시 수동 시나리오:
  1. `~/.ssh/config`에 `Host prod-api` 추가 → 사이드바 즉시 반영 (파일 watcher)
  2. 사이드바 클릭 → TOFU 모달 → `Accept & Save` → 탭 열림 → `~` 홈 디렉터리 listing
  3. 파일 drag local → remote → toolbar chip pulse → popover에 진행률 + 취소 가능
  4. 원격 파일 rename (⏎) / delete (⌘⌫ + 확인 모달) / mkdir (우클릭 메뉴)
  5. 원격 text 파일 선택 → preview pane에 head streaming 표시
  6. Space → lazy download → QuickLook 뜸
  7. Cloudflare Tunnel (`ProxyCommand cloudflared …`) host 연결 성공
  8. AWS SSM (`ProxyCommand aws ssm start-session …`) host 연결 성공
  9. Idle 5분 후 자동 disconnect → 사이드바 dot → gray
  10. 우클릭 Disconnect → 즉시 gray. Reconnect → 녹색
  11. Changed-key alert 방어 (테스트용 known_hosts mutate 후 재연결)
  12. `Clear Remote Cache` 메뉴 동작
  13. 앱 quit 시 모든 세션 gracefully close
- [ ] `git tag phase-2-ssh-v1` + `git tag v0.2.0-alpha.1` (같은 HEAD)

---

## 7. Non-goals (v1 exclusions)

다음은 **의식적으로 v1에서 제외**. scope creep 방지:

| 항목 | 이유 / 배치 |
|---|---|
| 듀얼 페인 / split view | M2 |
| 전송 큐 매니저 / resume / pause | M2 — 현재 popover는 M2에서 full panel로 확장 |
| Auto-retry on transient failure | M2 (transfer queue와 세트) |
| Edit-in-place (download→edit→upload sync) | M2 |
| Content 검색 on remote (ripgrep) | M2 |
| Subtree 검색 on remote (find) | M2 |
| chmod / permissions 패널 | M2 |
| Symlink 생성 (SFTP symlink op) | M2 |
| Remote trash | 개념 자체가 없음 — 영구 |
| Password / keyboard-interactive auth | M2 |
| ProxyJump 네이티브 (ProxyCommand 자동 derive 없이) | M2 |
| FTP / S3 / WebDAV | post-M2 |
| OpenSSH ControlMaster 소켓 재사용 | out of scope |
| ssh_config 기존 엔트리 편집 UI | v1은 append-only |
| Git 컬럼 on 원격 | 영구 (로컬 전용) |
| ssh-agent forwarding 토글 UI | ssh_config `ForwardAgent` 존중만, UI 없음 |
| multi-host batch ops | post-M2 |

---

## 8. 리스크 + 미결 아이템

### 8.1 리스크 매트릭스

| 리스크 | 영향 | 완화 |
|---|---|---|
| russh의 SFTP `copy-data` extension 미지원 서버 | Remote→Remote copy가 client-mediated fallback → 2× 네트워크 | Capability 조회 후 자동 fallback + warning toast 1회 |
| Hashed known_hosts 매칭 버그 | 이미 수락한 호스트에 TOFU 재요청 → UX 짜증 | Rust tests에 OpenSSH 실제 known_hosts fixture로 회귀 방지 |
| ProxyCommand stderr 버퍼링 / 유실 | 연결 실패 시 원인 불명 | 앞 8KB까지 capture + [Copy Error] 버튼 + 로그 |
| Cloudflare Tunnel warm-up 지연 (3s+) | 첫 연결이 unresponsive처럼 느껴짐 | Connecting overlay에 단계 텍스트 ("Opening tunnel via cloudflared…") |
| 1Password ssh-agent socket 경로 비표준 | `IdentityAgent` 해석 필요 | `ssh -G`가 절대경로로 알려줌 → 그대로 사용 |
| russh 버전 bump 시 API 변경 | 유지보수 부담 | `Cargo.lock` commit + russh를 workspace 의존성으로 고정 |
| FileSystemProvider refactor로 인한 로컬 회귀 | 로컬 파일 동작 breakage | LocalFileSystemProvider pass-through를 XCTest로 검증 (existing 기능 전수 확인) |
| `cairn-ssh` 빌드가 Rust 1.85 미만에서 실패 | onboarding friction | `rust-toolchain.toml` 이미 1.85 고정 — OK |
| Sidecar JSON 경로가 기존 컨벤션과 불일치 | 설정 파일 산재 | **구현 첫날**: `BookmarkStore`/`SettingsStore` 위치 조사 후 통일 |

### 8.2 구현 단계 결정 대기 항목

- **Host metadata JSON 경로**: `~/Library/Application Support/Cairn/` vs `~/Library/Preferences/*.plist`. 구현 첫날 기존 저장 위치 조사 후 확정.
- **ssh_config Include 추적 범위**: top-level `Include` 지시자만 vs `~/.ssh/config.d/*` 관례까지. 구현 중 결정 (관례까지 지원하는 게 유저 친화).
- **Connect sheet "Custom ProxyCommand" 필드**: 항상 노출 vs "Advanced" expandable. UX 재평가 — 일단 Advanced collapsed 기본.
- **Sidebar dot 색상 팔레트**: Glass Blue 톤과 맞춘 파스텔 4색 — 디자인 폴리시 단계에서 확정.
- **`TransferController` 소유자**: `AppModel` (multi-window 공유) vs `WindowSceneModel`. AppModel이 합리적 (pool과 동일 스코프) — 구현 첫날 확정.
- **`preferred_authentications` 중 password/kbd-interactive가 필요하면**: v1은 명시적 error 후 M2 대기. 하지만 러프하게 "지원 안 함" 메시지보다 actionable한 "Open Terminal to authenticate first"를 제공할지 결정.

### 8.3 브레인스토밍 미포함(=구현 단계 재량) 항목

- 에러 메시지 UX copy (빨간 카드 문구, tooltip 문구 등) — 디자인 폴리시에서 일괄
- Dot color palette 파스텔 매핑 — 디자인 폴리시
- Passphrase modal에서 `[Remember in Keychain]` 체크박스 default 값 (on 추천)
- Transfer popover의 recent section retention 정책 (10개? 20개?) — 일단 10개
- Idle timeout 숫자 (5분) — 추후 Settings 노출 여부 결정
