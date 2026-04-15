# Migration helpers for legacy default-cache locations.
# migrate_legacy_defaultcache : v0.1.0 → v0.2.0  (remove once v0.1.0 unsupported)
# migrate_v020_defaultcache   : v0.2.0 → v0.3.0+

public migrate_legacy_defaultcache
public migrate_v020_defaultcache

"""
    DataCaches.migrate_legacy_defaultcache(; conflict::Symbol = :skip) → Bool

Migrate the default cache from its pre-Scratch.jl location to the current default store.

Before DataCaches.jl integrated with Scratch.jl (prior to v0.2.0), autocached data
was stored at:

    ~/.cache/DataCaches/_DEFAULT/

After Scratch.jl integration (v0.2.0+) the autocache store moved to the managed
scratchspace:

    ~/.julia/scratchspaces/<DataCaches-UUID>/caches/user/_AUTOCACHE/

(or the path given by `DATACACHES_AUTOCACHE_STORE` if that environment variable is set).

Call this function once after upgrading from pre-v0.2.0 to move any data accumulated
under the old location into the current autocache store. It is safe to call multiple
times (idempotent).

**Return value:**

  - `true`  — migration was performed; legacy directory existed and was processed.
  - `false` — nothing to migrate; legacy directory did not exist (or was already removed).

**Migration strategy:**

  - If the legacy directory does not exist, returns `false` immediately.
  - If the current autocache store does not yet exist, the legacy directory is moved
    wholesale via `Base.mv` — no re-indexing, no data copying.
  - If the current autocache store already exists (e.g. `active_autocache()` was
    already called after upgrading), all entries from the legacy directory are imported via
    [`importcache!`](@ref) and then the legacy directory is removed. The `conflict`
    keyword controls label collisions between the two stores.

**`conflict` keyword** (applies only when both stores already contain data):

  - `:skip` (default) — keep the entry already in the current store; discard the legacy one.
  - `:overwrite` — replace the current store's entry with the legacy one.
  - `:error` — raise an `ErrorException` immediately on any label collision.

# Examples
```julia
# Migrate once after upgrading:
DataCaches.migrate_legacy_defaultcache()

# Prefer legacy data when labels collide:
DataCaches.migrate_legacy_defaultcache(; conflict = :overwrite)
```
"""
function migrate_legacy_defaultcache(; conflict::Symbol = :skip)
    legacy_path = joinpath(homedir(), ".cache", "DataCaches", "_DEFAULT")
    isdir(legacy_path) || return false

    new_path = Caches.autocachestore()  # respects DATACACHES_AUTOCACHE_STORE

    if !isdir(new_path)
        # New store does not exist yet — move the whole directory wholesale.
        mkpath(dirname(new_path))
        Base.mv(legacy_path, new_path)
    else
        # New store already has data — import entries, then remove the legacy dir.
        dest = DataCache(new_path)
        importcache!(dest, legacy_path; conflict = conflict)
        Base.rm(legacy_path; recursive = true)
    end

    return true
end

"""
    DataCaches.migrate_v020_defaultcache(; conflict::Symbol = :skip) → Bool

Migrate the default cache from its v0.2.0 location to the current default store.

In DataCaches.jl v0.2.0, autocached data was stored at:

    <depot>/caches/defaultcache/

In v0.3.0+ the autocache store moved into the user silo:

    <depot>/caches/user/_AUTOCACHE/

(or the path given by `DATACACHES_AUTOCACHE_STORE` if that environment variable is set).

Call this function once after upgrading from v0.2.0 to move any data accumulated under
the old location into the current autocache store. It is safe to call multiple times
(idempotent).

**Return value:**

  - `true`  — migration was performed; v0.2.0 directory existed and was processed.
  - `false` — nothing to migrate; v0.2.0 directory did not exist (or was already removed).

**Migration strategy:**

  - If the v0.2.0 directory does not exist, returns `false` immediately.
  - If the new location does not yet exist, the v0.2.0 directory is moved wholesale
    via `Base.mv` — no re-indexing, no data copying.
  - If the new location already has data (e.g. `active_autocache()` was already called
    after upgrading), all entries are imported via [`importcache!`](@ref) and then the v0.2.0
    directory is removed. The `conflict` keyword controls label collisions.

**`conflict` keyword** (applies only when both stores already contain data):

  - `:skip` (default) — keep the entry already in the new store; discard the v0.2.0 one.
  - `:overwrite` — replace the new store's entry with the v0.2.0 one.
  - `:error` — raise an `ErrorException` immediately on any label collision.

# Examples
```julia
# Migrate once after upgrading:
DataCaches.migrate_v020_defaultcache()

# Prefer v0.2.0 data when labels collide:
DataCaches.migrate_v020_defaultcache(; conflict = :overwrite)
```
"""
function migrate_v020_defaultcache(; conflict::Symbol = :skip)
    # The v0.2.0 path is always <depot>/caches/defaultcache/,
    # regardless of DATACACHES_AUTOCACHE_STORE.
    old_path = joinpath(Caches._caches_dir(), "defaultcache")
    isdir(old_path) || return false

    new_path = Caches.autocachestore()  # respects DATACACHES_AUTOCACHE_STORE

    if !isdir(new_path)
        # New store does not exist yet — move the whole directory wholesale.
        mkpath(dirname(new_path))
        Base.mv(old_path, new_path)
    else
        # New store already has data — import entries, then remove the v0.2.0 dir.
        dest = DataCache(new_path)
        importcache!(dest, old_path; conflict = conflict)
        Base.rm(old_path; recursive = true)
    end

    return true
end
