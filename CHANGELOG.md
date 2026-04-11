# Changelog

## [0.4.0]

### Added

- **`CacheEntry.ttl :: Union{Nothing,Period}`**: New field on [`CacheEntry`]
  for per-entry time-to-live. Pass `ttl = Dates.Hour(6)` to [`write!`] to
  record a TTL alongside the data. Stored in the cache index as `ttl_seconds`
  (integer seconds); backward-compatible — existing caches without `ttl_seconds`
  load with `ttl = nothing`.

- **`DataCache(...; default_ttl = Dates.Day(1))`**: Cache-level default TTL.
  When an entry has no per-entry `ttl`, `isstale` and autopurge fall back to the
  cache's `default_ttl`. The default TTL is persisted to `cache_index.toml`
  under `[cache_config]` so it survives across sessions.

- **`isstale(cache, entry) → Bool`** /
  **`isstale(cache, label) → Bool`** /
  **`isstale(entry) → Bool`** /
  **`isstale(label) → Bool`**:
  Check whether an entry has exceeded its effective TTL (per-entry or cache
  default). Returns `false` when no TTL is configured. `read` never blocks on
  staleness — callers decide whether to refresh, enabling stale-while-revalidate
  patterns.

- **`invalidate!(cache; kwargs...) → DataCache`** /
  **`invalidate!(; kwargs...) → DataCache`**:
  Bulk-remove entries matching a set of criteria in a single batched index
  rewrite. Filtering kwargs (same as `entries`/`CacheAssets.ls`):
  `pattern`, `filepath_pattern`, `filename_pattern`, `format`, `before`,
  `after`, `accessed_before_date`, `accessed_after_date`, `labeled`.
  Additional invalidation selectors: `stale = true` (entries past TTL),
  `predicate::Function` (arbitrary entry → Bool). `dry_run = true` prints
  candidates without deleting.

- **`DataCaches.CacheAssets.purge!(cache; kwargs...) → DataCache`** /
  **`CacheAssets.purge!(; kwargs...) → DataCache`**:
  Power-tool for bulk deletion with LRU and size-limit eviction. Accepts all
  `ls` filter kwargs to scope candidates, plus purge-specific criteria:
  `stale`, `max_age`, `max_idle`, `keep_count`, `max_size_bytes`, `keep_labeled`,
  `dry_run`. Multiple criteria are unioned (any match → delete).

- **`PurgePolicy`**: Immutable struct holding an autopurge configuration
  (`max_age`, `max_idle`, `keep_count`, `max_size_bytes`, `keep_labeled`).
  Created by `set_autopurge!`.

- **`set_autopurge!(cache; kwargs...) → DataCache`** /
  **`set_autopurge!(; kwargs...) → DataCache`**:
  Attach a `PurgePolicy` to a cache. After each `write!`, the policy is applied
  automatically. Pass `enabled = false` to remove the policy. Kwargs match
  `PurgePolicy` fields.

- **`write!` accepts `ttl::Union{Nothing,Period}` kwarg**: The per-entry TTL
  stored in the `CacheEntry`. Falls back to `cache.default_ttl` at staleness-
  check time (not at write time), so changing `default_ttl` retroactively
  affects all entries without a per-entry TTL.

- **`format` filter in `CacheAssets.ls` / `ls!` / `entries`**:
  New `format::Union{Nothing,String,Regex}` keyword argument for filtering
  entries by their serialization format tag (e.g. `format = "jls"`,
  `format = r"csv|json"`). Also available in `CacheAssets.purge!` and
  `invalidate!`.

- **`scratch_datacache!` accepts `default_ttl` kwarg**: Passes through to the
  underlying `DataCache` constructor.

### Changed

- **`DataCache` struct**: Two new fields added — `default_ttl` and
  `_autopurge_policy`. The `DataCache` positional constructor unchanged; the
  named-arg constructor gains optional `default_ttl` kwarg.

- **`CacheEntry` struct**: `ttl` field added as the 9th (last) field. All
  internal construction sites updated. Existing code that does not manually
  construct `CacheEntry` is unaffected.

---

## [0.3.1]

### Added

- **`CacheEntry` type**: `CacheKey` has been renamed to `CacheEntry` to better
  reflect its role as a full metadata descriptor for a cached dataset (id, seq,
  label, path, description, datecached, dateaccessed), not merely a lookup token.
  `CacheEntry` is now the primary exported name. The `show` output is updated
  accordingly: `CacheEntry("label")`.

- **`CacheKey` backward-compatible alias**: `CacheKey` remains as a silent
  `const` alias for `CacheEntry`. All existing code using `CacheKey` continues
  to work without modification. A deprecation warning will be added in a future
  release.

- **`entries(cache; kwargs...) → Vector{CacheEntry}`**: New exported function
  for bulk inspection of a cache's contents. Supports the full set of filter
  and sort keyword arguments previously only available via `CacheAssets.ls`.
  Zero-argument form `entries()` uses `default_filecache()`. This is now the
  primary API for getting all entries; `keys()` is maintained as a backward-compat
  alias.

- **`entry(cache, label) → CacheEntry`** /
  **`entry(cache, n::Integer) → CacheEntry`**: New exported function for
  targeted single-entry lookup. Throws `KeyError` if the entry is absent.
  Fills a gap in the prior API where there was no direct public way to retrieve
  a `CacheEntry` by label or index without scanning all entries. Single-argument
  form `entry(spec)` uses `default_filecache()`.

- **`labels(cache) → Vector{String}`**: New exported function returning only
  the user-assigned labels in a cache (no empty strings for unlabeled entries).
  Equivalent to `filter(!isempty, keylabels(cache))` but more efficient and
  more clearly named. Zero-argument form `labels()` uses `default_filecache()`.
  `keylabels()` is maintained as a backward-compat alias.

### Changed

- **`CacheAssets.ls` docstring** updated to note that `entries()` exposes the
  same data-retrieval functionality at the top level without a submodule import.

- **`keys(cache)` docstring** updated to note that `entries()` is preferred for
  new code; `keys()` is maintained for backward compatibility.

---

## [0.3.0]

### Added

- **`DataCaches.CacheAssets`** to provide a filesystem-like interface to managing 
  cache assets within a single cache: `CacheAssets.ls`, `CacheAssets.rm`, etc.

- **`DataCaches.Caches`** to provide a filesystem-like interface to managing 
  different caches within the package depot scratchspace: `Caches.ls`, `Caches.rm`, etc.

- **Library Integration guide** (`docs/src/integration.md`): New documentation page
  covering three standard integration patterns with complete working module examples:
  - **Pattern A** — package-private data store (`scratch_datacache!`, no user-visible
    autocaching)
  - **Pattern B** — instrumented functions, user controls which cache is used
  - **Pattern C** — instrumented functions with a package-owned default store
    (`package_cache` kwarg), overridable by the user

- **`package_cache` kwarg on `autocache`**: Library authors can now pass a
  `package_cache::Union{DataCache,Nothing}` to `autocache` to specify a package-owned
  default store. When autocaching is enabled but the user did **not** pass an explicit
  `cache` to `set_autocaching!`, results go to `package_cache` instead of
  `default_filecache()`. An explicit user-supplied cache always overrides
  `package_cache`. This enables Pattern C integration (see Library Integration guide):
  packages that want namespace-isolated default storage while fully respecting user
  override.

- **`_autocache_cache_explicit` internal flag**: `set_autocaching!` now tracks whether
  the active cache was user-supplied or defaulted. This is the mechanism that gives
  `package_cache` its correct priority without changing the return value or public
  behaviour of `set_autocaching!`.

- **`migrate_v020_defaultcache(; conflict=:skip)`**: Migrates the default cache from
  its v0.2.0 location (`<depot>/caches/defaultcache/`) to the new user silo location
  (`<depot>/caches/user/_DEFAULT/`). Same wholesale-move / merge-import semantics as
  `migrate_legacy_defaultcache`. Idempotent — safe to call multiple times.

### Changed

- **`Depot` submodule renamed to `Caches`**: `DataCaches.Depot` is now `DataCaches.Caches`.
  All functions (`pwd`, `ls`, `defaultstore`, `rm`, `mv`, `cp`) are unchanged; only the
  module name differs. Update call sites from `DataCaches.Depot.*` to `DataCaches.Caches.*`.

- **`Caches.ls()` default changed to `:root`**: `DataCaches.Caches.ls()` (no argument)
  now returns the raw root subdirectory listing (e.g. `[:caches]`) instead of user store
  names. Use `DataCaches.Caches.ls(:user)` for named user stores.

- **`caches/local/` renamed to `caches/user/`**: Named user stores (`DataCache(:name)`)
  now live under `<depot>/caches/user/<name>/` instead of `<depot>/caches/local/<name>/`.
  `Depot.ls()` default storetype changed from `:local` to `:user`.
  `Depot._local_dir()` renamed to `Depot._user_dir()` (internal).

- **Default cache relocated to `caches/user/_DEFAULT`**: The no-argument `DataCache()`
  constructor now stores data at `<depot>/caches/user/_DEFAULT/` instead of
  `<depot>/caches/defaultcache/`. `DataCache()`, `DataCache(:_DEFAULT)`, and
  `default_filecache()` all resolve to the same store. Existing v0.2.0 users should
  call `migrate_v020_defaultcache()` to transfer cached data to the new location.

- `autocache` docstring updated to document `package_cache` and the three-level store
  resolution priority (user-explicit → `package_cache` → `default_filecache()`).
- `set_autocaching!` docstring clarified: when `cache` is omitted, store selection is
  deferred to the `autocache` call site (a library-supplied `package_cache` takes
  priority over `default_filecache()`).
- README: new "Package-owned default cache" subsection in the Integration API section.

### Removed

- `Depot.test_datacache!` and `Depot.cleanuptests`: removed as a public API. The Depot
  test suite now redirects `Base.DEPOT_PATH` to a temporary directory for the duration
  of each run, so all depot operations are fully isolated without needing a dedicated
  test-area subdirectory.

## [0.2.0]

### Added

- **Scratch.jl-backed default cache store**: The default `DataCache()` now stores data in the Julia depot scratchspace (`~/.julia/scratchspaces/<UUID>/caches/defaultcache/`) instead of `~/.cache/DataCaches/_DEFAULT/`. Cache data is automatically cleaned up when the package is uninstalled. The storage location can be overridden via the `DATACACHES_DEFAULT_STORE` environment variable.

- **Named local stores** (`DataCache(:symbol)`): Named caches can be created and accessed by symbol, stored under the depot at `~/.julia/scratchspaces/<UUID>/caches/local/<name>/`. (Renamed to "user stores" in v0.3.0 with path `caches/user/<name>/`.)

- **Module-scoped caches** (`scratch_datacache!(uuid, key)`): UUID-namespaced cache stores for use by other packages, providing isolation between modules.

- **`Depot` submodule**: A filesystem-style interface for managing the cache depot, providing the following functions:
  - `Depot.pwd()` / `Depot.pwd(:name)` — return depot root path or path to a named store
  - `Depot.defaultstore()` — return the default cache path (respects `DATACACHES_DEFAULT_STORE`)
  - `Depot.ls(storetype)` — list stores filtered by type (`:local`, `:module`, `:root`)
  - `Depot.rm(name; force=false)` — remove a named store from the depot
  - `Depot.mv(src, dst)` — move, rename, import, or export caches (three dispatch forms: Symbol→Symbol, String→Symbol, Symbol→String)
  - `Depot.cp(src, dst)` — copy caches (same three dispatch forms as `mv`)
- **Sequence indexing**: Cache entries now have stable integer sequence numbers. Entries can be read and deleted by sequence index in addition to label or UUID. `reindexcache!()` compacts sequence gaps left by deletions.

- **Relative path storage in index**: The `cache_index.toml` now stores relative paths for portability across filesystems and directory moves. Absolute paths from v0.1.0 are still read correctly.

- **`migrate_legacy_defaultcache(; conflict=:skip)`**: Migrates a v0.1.0 default cache from `~/.cache/DataCaches/_DEFAULT/` to the v0.2.0 depot location. Performs a wholesale directory move if the new location is empty, or a merge import if both exist. Conflict resolution options: `:skip`, `:overwrite`, `:error`. Idempotent — safe to call multiple times.

- **Expanded test suite**: Comprehensive test coverage across 45+ test sets, including depot management, sequence indexing, Scratch.jl integration, import/export (file, ZIP, HTTP), memoization, autocaching, and legacy migration.

- **API reference documentation**: Full Documenter.jl-based API reference at `docs/src/index.md`.

### Changed

- **Default cache location** (breaking): The default `DataCache()` store has moved from `~/.cache/DataCaches/_DEFAULT/` to the Julia depot scratchspace. Existing v0.1.0 users should call `migrate_legacy_defaultcache()` to transfer cached data to the new location.

- **Index path storage**: The cache index now stores paths relative to the cache directory rather than absolute paths, making caches portable when moved between systems.

### Fixed

- Documenter.jl build issue caused by functions lacking explicit docstrings.

## [0.1.0]

Initial release.

- `DataCache` struct for persistent, file-backed key-value caching
- Write and read arbitrary Julia objects (serialized as `.jls`) and `DataFrame`s (stored as `.csv`)
- Cache entries addressable by label (string) or UUID
- `write!`, `read`, `delete!`, `clear!`, `relabel!`, `haskey`, `keys`, `keylabels`, `keypaths`, `showcache`
- `movecache!` and `importcache!` for relocating and merging caches (file, ZIP archive, HTTP URL)
- `@filecache` and `@memcache` memoization macros for automatic function-result caching
- `set_autocaching!` / `autocache` for transparent library-level caching integration
- TOML-based index (`cache_index.toml`) for human-readable, inspectable metadata
