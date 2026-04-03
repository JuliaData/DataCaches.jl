
# Temporary migration helper: v0.1.0 → v0.2.0
# Remove this file and its include() in DataCaches.jl once v0.1.0 is no longer supported.

public migrate_legacy_defaultcache

"""
    DataCaches.migrate_legacy_defaultcache(; conflict::Symbol = :skip) → Bool

Migrate the default cache from its pre-Scratch.jl location to the current default store.

Before DataCaches.jl integrated with Scratch.jl (prior to v0.2.0), the no-argument
`DataCache()` constructor stored data at:

    ~/.cache/DataCaches/_DEFAULT/

After Scratch.jl integration the default moved to the managed scratchspace:

    ~/.julia/scratchspaces/<DataCaches-UUID>/default/

(or the path given by `DATACACHES_DEFAULT_STORE` if that environment variable is set).

Call this function once after upgrading to v0.2.0 to move any data accumulated under the
old location into the new one. It is safe to call multiple times (idempotent).

**Return value:**

  - `true`  — migration was performed; legacy directory existed and was processed.
  - `false` — nothing to migrate; legacy directory did not exist (or was already removed).

**Migration strategy:**

  - If the legacy directory does not exist, returns `false` immediately.
  - If the current default store does not yet exist, the legacy directory is moved
    wholesale via `Base.mv` — no re-indexing, no data copying.
  - If the current default store already exists (e.g. `DataCache()` was already used
    after upgrading), all entries from the legacy directory are imported via
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

    new_path = Depot.defaultstore()  # respects DATACACHES_DEFAULT_STORE

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
