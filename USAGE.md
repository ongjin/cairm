# Cairn 사용 가이드 (v0.1.0-alpha)

## 첫 실행

- 앱 시작 시 폴더 선택 창 (`NSOpenPanel`) 이 뜬다. 원하는 폴더 선택 → 해당 폴더가 자동으로 Pinned 에 추가됨
- 이후 실행부터는 마지막으로 열었던 폴더로 복귀

## 사이드바

- **Pinned** — `⌘D` 로 추가/해제. 우클릭 → Unpin / Reveal in Finder
- **Recent** — 최근 방문. 자동 갱신
- **iCloud** — iCloud Drive (활성 상태일 때만 표시)
- **Locations** — 로컬 드라이브 / 외장 USB (mount/unmount 즉시 반영)

현재 폴더와 일치하는 사이드바 row 는 파란 accent pill 로 하이라이트.

## 네비게이션

- 폴더 더블클릭 / `⏎` → 진입
- 파일 더블클릭 / `⏎` → 기본 앱으로 열림
- 브레드크럼 세그먼트 클릭 → 해당 경로로 이동 (히스토리 push)
- `⌘↑` 상위, `⌘←` / `⌘→` 히스토리 (끝에서 비활성)
- 컬럼 헤더 클릭 → Name / Size / Modified 기준 정렬 토글 (asc/desc)

## 프리뷰 패널

- 파일 선택 → 우측 프리뷰 패널에 자동 표시
  - 텍스트: 첫 64 KB 디코드 (바이너리 감지 시 meta-only 로 fallback)
  - 이미지: PNG/JPG/GIF/BMP/TIFF/HEIC/WEBP 썸네일
  - 디렉터리: 자식 항목 수
  - 기타 파일: meta only (경로, 크기, mtime)
- `Space` → 전체 Quick Look 패널 (`Esc` 또는 `Space` 로 닫기)
- `⌘R` → 현재 폴더 리로드 (Quick Look 열려 있을 때는 패널이 key responder 라 `⌘R` 무반응 — 의도된 동작)

## 컨텍스트 메뉴 (우클릭)

- **Add to Pinned / Unpin** (폴더만)
- **Reveal in Finder**
- **Copy Path** (`⌥⌘C`) — pasteboard 에 절대경로 복사
- **Open With ▸** (파일만) — 기본 앱 맨 위 `(default)` 표시 + 대체 앱 목록
- **Move to Trash** (`⌘⌫`) — 실패 시 경고 다이얼로그

## 검색 (`⌘F`)

툴바 오른쪽의 검색 필드에 타이핑하면 결과 실시간 표시. 두 가지 scope:

- **This Folder** (기본) — 현재 폴더 바로 안의 파일만 즉시 substring 필터. 인덱스 없음, in-memory
- **Subtree** — 현재 폴더 이하 전체 재귀 walk (Rust `ignore::WalkBuilder`). 결과가 live 하게 populate. Folder 컬럼에 search root 기준 상대경로 표시

**규칙**
- 대소문자 무시 substring 매칭
- `.gitignore` 기본 존중 (`⌘⇧.` 로 숨김 파일 ON 하면 해제)
- 최대 5,000 결과 — 초과 시 상단 배너 "Showing first 5,000 — refine your query"
- `Esc` 또는 쿼리 clear → 정상 폴더 뷰로 복귀
- 검색 중 폴더 이동 → 쿼리 유지된 채 새 root 에서 재검색

검색 결과에서도 `Space` (QL), 더블클릭 (Open), 우클릭 (컨텍스트 메뉴), 컬럼 헤더 정렬 모두 정상 동작.

## 알려진 제약 (v0.1.0-alpha)

- 내용 검색 / 퍼지 / regex 없음 (Phase 2 예정)
- 드래그 앤 드롭 없음 (Phase 2)
- 다중 선택 + `⏎` 는 focused row 하나만 열림
- 파일이 `.git` 없는 폴더의 `.gitignore` 규칙에도 걸러짐 (Phase 2 에서 독립 토글 예정)
- 샌드박스 외부 폴더는 첫 접근마다 권한 재프롬프트
