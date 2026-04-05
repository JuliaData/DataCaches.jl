## Usage Patterns

### Pattern 1 — Memoized function calls

`@filecache` and `@memcache` wrap a single function call expression and cache
its result automatically, keyed on the runtime values of all arguments. If the
same call appears again (even in a new session, for `@filecache`), the cached
result is returned immediately without re-executing the function.

These macros work with **any function from any library** — no integration or
instrumentation required.

#### `@filecache` — persist across Julia sessions

```julia
using DataCaches, PaleobiologDB

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

dc = DataCache(:project1)
set_default_filecache!(dc)

# First call: runs the query and stores the result
occs = @filecache pbdb_occurrences(base_name = "Canidae", show = "full")

# Subsequent calls (same or new session): returns from disk immediately
occs = @filecache pbdb_occurrences(base_name = "Canidae", show = "full")
```

Pass an explicit cache as the first argument to target a specific store
without changing the global default:

```julia
project_cache = DataCache("/data/research/pbdb_cache")
occs = @filecache project_cache pbdb_occurrences(base_name = "Canidae")
taxa = @filecache project_cache pbdb_taxa(name = "Dinosauria")
```

Since `@filecache` is generic, it works equally well with any third-party library:

```julia
using DataCaches, GBIF2

dc = DataCache(:biodiversity)
set_default_filecache!(dc)

occs = @filecache GBIF2.occurrence_search(taxonKey = 212, limit = 300)
# Next session: same call with `@filecache` returns from disk, no network request
```

#### `@filecache!` — force cache refresh

`@filecache!` is the unconditional counterpart to `@filecache`. It always
re-executes the function and overwrites any existing cached entry, then returns
the fresh result. Use it when you know the upstream data has changed and want
to refresh a specific call without clearing the entire cache.

```julia
# Force-refresh a stale entry
occs = @filecache! pbdb_occurrences(base_name = "Canidae", show = "full")

# Force-refresh into a specific cache
project_cache = DataCache("/data/research/pbdb_cache")
occs = @filecache! project_cache pbdb_occurrences(base_name = "Canidae")
```

After a `@filecache!` call the updated entry is immediately available to
subsequent `@filecache` calls with the same arguments.

Enable debug logging to see when updates occur:

```julia
ENV["JULIA_DEBUG"] = "DataCaches"
occs = @filecache! pbdb_occurrences(base_name = "Canidae", show = "full")
# @filecache!: updating cache — pbdb_occurrences(base_name = "Canidae", show = "full")
```

#### `@memcache` — deduplicate within a session

`@memcache` is the in-process equivalent: results live in memory for the
duration of the Julia session and are discarded when the process exits.
Useful for avoiding redundant calls within a notebook or long script.

```julia
occs = @memcache pbdb_occurrences(base_name = "Canidae", show = "full")
taxa = @memcache pbdb_taxa(name = "Canis")

memcache_clear!()   # discard all in-memory results
```

### Pattern 2 — Explicit label assignment

The most transparent pattern. You control exactly what is stored and when it is
retrieved, using dictionary-style indexing. Works with any data source.
The explicit labeling makes it especially useful for packaging results for sharing or export.

```julia
using DataCaches, PaleobiologyDB

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

dc = DataCache(joinpath(homedir(), ".datacaches", "project1"))

# Store
dc["canidae_occs"]  = pbdb_occurrences(base_name = "Canidae", show = "full")
dc["dinosaur_taxa"] = pbdb_taxa(name = "Dinosauria", vocab = "pbdb")

# Retrieve by label
occs = dc["canidae_occs"]
taxa = dc["dinosaur_taxa"]

# Retrieve by sequence index (as shown in showcache output)
occs = dc[1]
taxa = dc[2]

# Conditionally fetch
if !haskey(dc, "trilobites")
    dc["trilobites"] = pbdb_occurrences(base_name = "Trilobita")
end
df = dc["trilobites"]
```

Manage the store:

```julia
# Overwrite an existing label
dc["canidae_occs"] = pbdb_occurrences(base_name = "Canidae", show = "coords")

# Summarize contents
showcache(dc)
# DataCache: /home/user/.datacaches/project1  (3 entries)
#   [1]  2025-08-25T14:23:01  2a9d4a87  canidae_occs
#                                        /home/user/.datacaches/project1/2a9d4a87-....csv
#   ...

# Rename a label
# Also see: `DataCaches.CacheAssets.mv`
relabel!(dc, "canidae_occs", "canidae")   # by label
relabel!(dc, 2, "canidae")                # by sequence index

# Retrieve by sequence index
df = dc[1]

# Remove entries
# Also see: `DataCaches.CacheAssets.rm`
delete!(dc, "trilobites")   # by label
delete!(dc, 2)              # by sequence index
clear!(dc)                  # remove all entries

# Compact sequence numbers after many deletions
reindexcache!(dc)
```

### Pattern 3 — Automatic caching

`set_autocaching!` installs a global hook that intercepts calls to instrumented
functions and transparently caches results. Existing call sites require no modification —
the caching layer is completely invisible.

**Prerequisite:** this pattern requires functions to be *instrumented*, meaning the
library calls the `autocache` hook internally. See [Integration API for library authors](#integration-api-for-library-authors)
for how to add this to a library, or [Thin wrapper approach](#with-any-third-party-library--thin-wrapper-approach)
to instrument any existing function yourself in a few lines.

#### With a natively integrated library (e.g. PaleobiologyDB.jl)

```julia
using DataCaches, PaleobiologyDB

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

# Enable autocaching, using the default global cache
set_autocaching!(true)

# If we do not want to rely on the default global cache, 
# "`:_GLOBAL`", as the above does, we can open a project 
# silo:
# dc = DataCache(:project1)
# set_autocaching!(true; cache = dc)

# All pbdb_* calls now cache automatically — no changes to call sites
occs  = pbdb_occurrences(base_name = "Canidae")           # fetches + stores
occs2 = pbdb_occurrences(base_name = "Canidae")           # instant, from cache
taxa  = pbdb_taxa(name = "Dinosauria", vocab = "pbdb")    # fetches + stores

set_autocaching!(false)
```

Enable caching for specific functions only:

```julia
set_autocaching!(true, pbdb_occurrences; cache = dc)         # only this function
set_autocaching!(true, pbdb_taxa; cache = dc)                # add another
set_autocaching!(false, pbdb_occurrences)                    # remove one
set_autocaching!(false)                                      # disable entirely

# Multiple functions at once
set_autocaching!(true, [pbdb_occurrences, pbdb_taxa, pbdb_collections]; cache = dc)
```

#### With any third-party library — thin wrapper approach

For a library that has not integrated DataCaches.jl, write a one-time thin
wrapper that calls the `autocache` hook. The wrapper is a drop-in replacement
for the original function, and from that point on the full `set_autocaching!`
interface works as normal.

```julia
using DataCaches, GBIF2
import DataCaches: autocache

# One-time wrapper — mirrors the signature of the original function
function gbif_occurrence_search(; kwargs...)
    return autocache(
        () -> GBIF2.occurrence_search(; kwargs...),
        gbif_occurrence_search,
        "occurrence/search",
        kwargs,
    )
end

# Now use the wrapper exactly like a natively integrated function
dc = DataCache(:biodiversity)
set_autocaching!(true; cache = dc)

occs  = gbif_occurrence_search(taxonKey = 212, limit = 300)  # fetches + stores
occs2 = gbif_occurrence_search(taxonKey = 212, limit = 300)  # from cache
taxa  = gbif_occurrence_search(taxonKey = 5219857)           # fetches + stores

set_autocaching!(false)
```

The wrapper body has three moving parts:

| Argument | Purpose | What to put here |
|---|---|---|
| `() -> ...` | The real fetch, as a closure | Call the original function |
| `gbif_occurrence_search` | Identity for the autocache allowlist | Your wrapper function itself |
| `"occurrence/search"` | Endpoint string (part of cache key) | Any stable string identifying the resource |
| `kwargs` | Argument values (part of cache key) | Pass through from the wrapper |

#### Package-owned default cache

By default, when the user calls `set_autocaching!(true)` without an explicit `cache`
argument, results go to the shared `default_filecache()`.
If your package should instead write to its own module-namespace package silo by default — while
still letting the user override with `set_autocaching!(true; cache=x)` — pass a
`package_cache` kwarg to `autocache`:

```julia
module MyPackage
using DataCaches
import DataCaches: autocache

const _PKG_UUID = Base.UUID("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")  # from Project.toml
const _pkg_cache_ref = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    _pkg_cache_ref[] = DataCaches.scratch_datacache!(_PKG_UUID, :mypackage)
end

pkg_cache() = _pkg_cache_ref[]

function my_query(; kwargs...)
    return autocache(
        () -> _do_query(; kwargs...),
        my_query,
        "resource/endpoint",
        kwargs;
        package_cache = _pkg_cache_ref[],   # ← package default, user-overridable
    )
end
end
```

Store resolution priority:

1. **User-explicit** — `set_autocaching!(true; cache=x)` → always `x`
2. **`package_cache`** — used when no explicit user cache was set
3. **`default_filecache()`** — final fallback

See the Library Integration guide in the [full documentation](https://juliadata.org/DataCaches.jl/)
for complete working examples of all three patterns (private cache, user-controlled
cache, and package-owned default cache).

---
