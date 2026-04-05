# Changelog

## [Unreleased]

### Added

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

- **Library Integration guide** (`docs/src/integration.md`): New documentation page
  covering three standard integration patterns with complete working module examples:
  - **Pattern A** — package-private data store (`scratch_datacache!`, no user-visible
    autocaching)
  - **Pattern B** — instrumented functions, user controls which cache is used
  - **Pattern C** — instrumented functions with a package-owned default store
    (`package_cache` kwarg), overridable by the user

### Removed

- `Depot.test_datacache!` and `Depot.cleanuptests`: removed as a public API. The Depot
  test suite now redirects `Base.DEPOT_PATH` to a temporary directory for the duration
  of each run, so all depot operations are fully isolated without needing a dedicated
  test-area subdirectory.

### Added

- **`migrate_v020_defaultcache(; conflict=:skip)`**: Migrates the default cache from
  its v0.2.0 location (`<depot>/caches/defaultcache/`) to the new user silo location
  (`<depot>/caches/user/_GLOBAL/`). Same wholesale-move / merge-import semantics as
  `migrate_legacy_defaultcache`. Idempotent — safe to call multiple times.

### Changed

- **`caches/local/` renamed to `caches/user/`**: Named user stores (`DataCache(:name)`)
  now live under `<depot>/caches/user/<name>/` instead of `<depot>/caches/local/<name>/`.
  `Depot.ls()` default storetype changed from `:local` to `:user`.
  `Depot._local_dir()` renamed to `Depot._user_dir()` (internal).

- **Default cache relocated to `caches/user/_GLOBAL`**: The no-argument `DataCache()`
  constructor now stores data at `<depot>/caches/user/_GLOBAL/` instead of
  `<depot>/caches/defaultcache/`. `DataCache()`, `DataCache(:_GLOBAL)`, and
  `default_filecache()` all resolve to the same store. Existing v0.2.0 users should
  call `migrate_v020_defaultcache()` to transfer cached data to the new location.

- `autocache` docstring updated to document `package_cache` and the three-level store
  resolution priority (user-explicit → `package_cache` → `default_filecache()`).
- `set_autocaching!` docstring clarified: when `cache` is omitted, store selection is
  deferred to the `autocache` call site (a library-supplied `package_cache` takes
  priority over `default_filecache()`).
- README: new "Package-owned default cache" subsection in the Integration API section.

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
