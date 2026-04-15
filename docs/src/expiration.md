```@meta
CurrentModule = DataCaches
```

# Cache expiration and invalidation

DataCaches provides first-class support for cache invalidation: time-to-live
(TTL), stale detection, bulk invalidation, fine-grained purging, and automatic
post-write purge policies.

## TTL and staleness

### Per-entry TTL

Pass a `ttl` keyword to [`write!`](@ref) to record a time-to-live for an entry.
The value must be a `Dates.Period` (e.g. `Dates.Hour(6)`, `Dates.Day(30)`).

```julia
using DataCaches, Dates

dc = DataCache(:myproject)

# Cache a result with a 6-hour TTL
write!(dc, result; label = "query1", ttl = Hour(6))

# Check staleness before re-using
if isstale(dc, "query1")
    result = fetch_live()
    write!(dc, result; label = "query1", ttl = Hour(6))
end
data = read(dc, "query1")
```

`read` does **not** enforce staleness — stale entries are readable until
explicitly removed. This enables a *stale-while-revalidate* pattern: serve
from the cache while refreshing in the background.

### Cache-level default TTL

Set a default TTL on the cache itself so every `write!` inherits it
automatically:

```julia
# All writes to this cache expire after 24 hours unless overridden per-entry
dc = DataCache(:myproject; default_ttl = Day(1))

write!(dc, result; label = "query1")          # inherits Day(1)
write!(dc, result; label = "query2", ttl = Hour(1))  # overrides to Hour(1)
```

The `default_ttl` is persisted in the cache's TOML index, so it is remembered
when the cache is reloaded in a future session.

### `isstale`

[`isstale`](@ref) checks whether an entry has exceeded its TTL:

```julia
isstale(dc, "query1")           # by label
isstale(dc, entry)              # by CacheEntry
isstale("query1")               # uses active_autocache()
isstale(entry)                  # uses active_autocache()
```

Returns `false` when no TTL applies (neither per-entry nor cache default).
Legacy entries whose `datecached` is unknown are never considered stale.

### Stale-while-revalidate pattern

```julia
function get_data(dc, label, fetch_fn; ttl = Hour(6))
    # Return cached value even if stale; trigger background refresh when stale
    if haskey(dc, label) && isstale(dc, label)
        @async begin
            result = fetch_fn()
            write!(dc, result; label = label, ttl = ttl)
        end
    elseif !haskey(dc, label)
        result = fetch_fn()
        write!(dc, result; label = label, ttl = ttl)
    end
    return read(dc, label)
end
```

## `invalidate!` — bulk invalidation

[`invalidate!`](@ref) removes entries matching a set of criteria in a single
batched index rewrite. When called without a `cache` argument, uses
[`active_autocache()`](@ref).

### By staleness

```julia
# Remove all entries that have exceeded their TTL
invalidate!(dc; stale = true)
invalidate!(; stale = true)    # default cache
```

### By label pattern

```julia
# Remove entries whose label/description matches a pattern
invalidate!(dc; pattern = r"^temp_")
invalidate!(dc; pattern = "old_run_")          # String is converted to Regex
```

### By date

```julia
# Remove entries cached more than 30 days ago
invalidate!(dc; before = now() - Day(30))

# Remove entries from a specific window
invalidate!(dc; after  = DateTime("2026-01-01T00:00:00"),
                before = DateTime("2026-02-01T00:00:00"))
```

### By file format

```julia
# Remove all JLS (binary serialization) entries
invalidate!(dc; format = "jls")
invalidate!(dc; format = r"jls|json")   # multiple formats via Regex
```

### By predicate function

A `predicate` function receives a [`CacheEntry`](@ref) and returns `true` if
the entry should be removed:

```julia
# Remove entries whose description starts with a particular function name
invalidate!(dc; predicate = e -> startswith(e.description, "my_func("))

# Remove large files
invalidate!(dc; predicate = e -> isfile(e.path) && stat(e.path).size > 50_000_000)
```

### Combining criteria

All filter kwargs (same as [`entries`](@ref) / [`CacheAssets.ls`](@ref)) are
accepted first to scope the candidate set, then `stale` and `predicate` are
applied as additional restrictions:

```julia
# Remove stale, labeled-only entries cached before a date
invalidate!(dc; labeled = true, before = now() - Day(7), stale = true)
```

### Dry-run preview

```julia
invalidate!(dc; stale = true, dry_run = true)
# Prints: "invalidate! (dry run): N entries would be removed: …"
# No entries are deleted.
```

## `CacheAssets.purge!` — power tool

[`DataCaches.CacheAssets.purge!`](@ref) is the full-featured purge function
with LRU eviction, size limits, and all the filter kwargs accepted by
[`CacheAssets.ls`](@ref).

### Remove by age

```julia
using DataCaches.CacheAssets

# Remove entries older than 30 days
purge!(dc; max_age = Day(30))
```

### Remove by idle time (LRU)

```julia
# Remove entries not accessed in the last 7 days
purge!(dc; max_idle = Day(7))
```

!!! note
    `max_idle` requires `track_access = true` (the default) on the cache.
    Entries that have never been accessed are treated as most-idle.

### Keep only the N most recently accessed

```julia
# Keep the 20 most recently accessed entries; delete the rest
purge!(dc; keep_count = 20)
```

### Limit total cache size

```julia
# Purge LRU entries until total cache size is under 500 MiB
purge!(dc; max_size_bytes = 500 * 1024 * 1024)
```

### Protect labeled entries

```julia
# Purge only unlabeled entries older than a week; leave labeled entries alone
purge!(dc; max_age = Day(7), keep_labeled = true)
```

### Combine with format or pattern filters

```julia
# Delete JLS entries not accessed in the last 30 days
purge!(dc; format = "jls", max_idle = Day(30))

# Delete entries matching a label pattern that are older than a month
purge!(dc; pattern = r"^temp_", max_age = Day(30))
```

### Dry-run

```julia
purge!(dc; max_age = Day(7), dry_run = true)
# Prints: "purge! (dry run): N entries would be removed: …"
# No entries are deleted.
```

### Remove all stale entries via purge!

```julia
purge!(dc; stale = true)
```

## Auto-purge policies

[`set_autopurge!`](@ref) attaches a [`PurgePolicy`](@ref) to a cache. The
policy runs automatically at the end of every [`write!`](@ref), keeping the
cache within configured limits without manual intervention.

### LRU eviction

```julia
# Keep only the 50 most recently accessed entries
set_autopurge!(dc; keep_count = 50)

# Write a new result — oldest entries are pruned automatically
write!(dc, new_result; label = "latest")
```

### Age-based cleanup

```julia
# Entries older than 14 days are automatically removed on each write
set_autopurge!(dc; max_age = Day(14))
```

### Size-based cleanup

```julia
# Cache stays under 1 GiB; LRU entries are pruned when the limit is exceeded
set_autopurge!(dc; max_size_bytes = 1024^3)
```

### Combined policy

```julia
# Remove entries older than 30 days OR keep only the last 100,
# but never delete labeled entries
set_autopurge!(dc; max_age = Day(30), keep_count = 100, keep_labeled = true)
```

### Disabling auto-purge

```julia
set_autopurge!(dc; enabled = false)
```

### Using the autocache store

All functions accept a zero-argument form that operates on
[`active_autocache()`](@ref):

```julia
set_autopurge!(; keep_count = 20)
invalidate!(; stale = true)
CacheAssets.purge!(; max_age = Day(30))
```

## Quick-reference table

| Function | Description |
|---|---|
| `write!(dc, data; ttl = Hour(6))` | Write with per-entry TTL |
| `DataCache(store; default_ttl = Day(1))` | Cache-level default TTL |
| `isstale(dc, label)` / `isstale(entry)` | Check if entry is past TTL |
| `invalidate!(dc; stale, pattern, format, before, after, labeled, predicate, dry_run)` | Bulk removal by criteria |
| `CacheAssets.purge!(dc; max_age, max_idle, keep_count, max_size_bytes, stale, keep_labeled, dry_run, …ls filters…)` | Power tool with LRU/size limits |
| `set_autopurge!(dc; max_age, max_idle, keep_count, max_size_bytes, keep_labeled, enabled)` | Configure automatic post-write purging |

## API reference

```@docs
isstale
invalidate!
set_autopurge!
DataCaches.CacheAssets.purge!
```
