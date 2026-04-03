# Changelog

## [0.2.0]

### Added

- **Scratch.jl-backed default cache store**: The default `DataCache()` now stores data in the Julia depot scratchspace (`~/.julia/scratchspaces/<UUID>/caches/defaultcache/`) instead of `~/.cache/DataCaches/_DEFAULT/`. Cache data is automatically cleaned up when the package is uninstalled. The storage location can be overridden via the `DATACACHES_DEFAULT_STORE` environment variable.

- **Named local stores** (`DataCache(:symbol)`): Named caches can be created and accessed by symbol, stored under the depot at `~/.julia/scratchspaces/<UUID>/caches/local/<name>/`.

- **Module-scoped caches** (`scratch_datacache!(uuid, key)`): UUID-namespaced cache stores for use by other packages, providing isolation between modules.

- **`Depot` submodule**: A filesystem-style interface for managing the cache depot, providing the following functions:
  - `Depot.pwd()` / `Depot.pwd(:name)` — return depot root path or path to a named store
  - `Depot.defaultstore()` — return the default cache path (respects `DATACACHES_DEFAULT_STORE`)
  - `Depot.ls(storetype)` — list stores filtered by type (`:local`, `:module`, `:root`)
  - `Depot.rm(name; force=false)` — remove a named store from the depot
  - `Depot.mv(src, dst)` — move, rename, import, or export caches (three dispatch forms: Symbol→Symbol, String→Symbol, Symbol→String)
  - `Depot.cp(src, dst)` — copy caches (same three dispatch forms as `mv`)
  - `Depot.test_datacache!(key)` / `Depot.cleanuptests()` — create and clean up test caches

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
