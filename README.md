# DataCaches.jl

[![CI](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml)
[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaData.github.io/DataCaches.jl/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaData.github.io/DataCaches.jl/dev)

A lightweight, file-backed key-value cache for Julia for workflows
that make frequent time-, internet or network bandwidth expensive function calls 
(remote API queries, long-running computations) and need results to 
be available across Julia sessions.
*Any* Julia object can be cached to disk to persist across sessions as `.jls` Julia serialized object files, but a special consideration is given to `DataFrame` objects as these are stored as `.csv` files, so they can also be independently inspected, accessed, and manipulated if needed.


Three levels of caching are provided, from lightest-weight to most manual:

| Level     | Mechanism              | Persistence     | Works with any function? |
|-----------|------------------------|-----------------|--------------------------|
| Memoized  | `@filecache`           | Across sessions | Yes                      |
| Refresh   | `@filecache!`          | Across sessions | Yes                      |
| Memoized  | `@memcache`            | In-session only | Yes                      |
| Explicit  | `dc["label"] = result` | Across sessions | Yes                      |
| Automatic | `set_autocaching!`     | Across sessions | Only if instrumented     |

## Purpose

The purpose of this package is to provide a persistent, file-backed key-value store for arbitrary Julia objects, keyed by user-assigned labels or auto-generated argument hashes.
This enables short-circuiting of expensive function calls by returning stored results instead of recomputing repeated calls across Julia sessions while also providing a portable, inspectable cache that can be shared across users or systems without requiring database infrastructure.

This package also provides mechanisms allowing library developers to patch in support for a fully transparent, under-the-hood auto-caching layer that requires no changes to user-facing call syntax.
This keeps exploratory and instructional code clean and readable, with caching remaining invisible in automatic mode and introducing no modifications to program logic or presentation.

## Features

DataCaches.jl provides three complementary interfaces aligned with its [purpose](#Purpose):

- a lightweight memoization mechanism, not requiring any function instrumentation or wrapping, enabling selective, automated caching of any function call (keyed on the runtime values of all arguments)

```julia
# If the active disk cache does not have this particular 
# combination of function name and argument values stored,
# then the function will be evaluated, cached, and returned.
foo = @filecache func1(x, y) 
# Function not evaluated; cached result returned
bar = @filecache func1(x, y) 
# Unconditionally re-execute and overwrite the cache entry
foo = @filecache! func1(x, y)
```

- a straightforward Dict-style API for explicit, manual cache control

```julia
# Just like a `Dict`, but auto-persists across sessions.
cache["fig1"] = plot(...)
fig1 = cache["fig1"] 
```

- a fully seamless mode in which specially-instrumented or wrapped function calls are cached on first execution and transparently retrieved thereafter, with no changes to call sites (see [Pattern 3 — Automatic caching](#pattern-3--automatic-caching))

```julia
# Once functions are instrumented (or wrapped), enable automatic caching:
set_autocaching!(true)
foo = func1(x, y)   # fetches + stores
bar = func1(x, y)   # instant, from cache — call site unchanged
```

with the following design principles:

- Syntactically lightweight or (almost) invisible. 
- Seamless integration into REPL- or script-based workflow without requiring any change of logic or structure.
- Straight-forward, flexible, and completely transparent management of cache store, with views and data accessible not only 
  through Julia for convenience, but also through standard file-system tools.
- Yet, cache store setup and management is *completely* optional, and novice users need not even be aware of its existence or operation.
- The cache store and usage persists across Julia sessions (i.e., not in-memory only, though that is supported).
- A particular cache store file-system directory can be shared across different computing systems or users by copying, cloning, or as an compressed archive.

## Installation

At the Julia REPL, type "`]`" to switch into Package manager mode and then type:

```
pkg> add DataCaches
```

Or, either in the Julia REPL or a script:

```julia
using Pkg
Pkg.add("DataCaches")
```

Or, if you want the latest development version from the source repository:

```julia
using Pkg
Pkg.add(url = "https://github.com/JuliaData/DataCaches.jl")
```

## Quick Start

### Cache store setup

Before caching anything, create a `DataCache`. There is a gradient from zero-configuration to full control:

```julia
# Zero config — lifecycle-managed default store, no path required
dc = DataCache()

# Named store — still lifecycle-managed, useful for separating projects
dc = DataCache(:project123)

# Explicit path — full portability, shareable across systems
dc = DataCache("/path/to/cache")

# Module-scoped — for package authors; namespaced by UUID
dc = DataCaches.scratch_datacache!(MyPackage_UUID, :results)
```

The first two forms live inside DataCaches.jl's own depot and are automatically removed
if DataCaches.jl is uninstalled and `Pkg.gc()` is run. The explicit path form is portable
and can be shared by copying or archiving the directory. See [Cache Store](#cache-store) for details.

### Caching approaches

With a cache in hand, all three patterns are available:

```julia
using DataCaches, PaleobiologDB

# Optional: show caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

dc = DataCache(:myproject)

# --- Pattern 1: @filecache — works with any function, no setup beyond the cache ---
set_default_filecache!(dc)
occs = @filecache pbdb_occurrences(base_name = "Canidae", show = "full")  # fetches + stores
occs = @filecache pbdb_occurrences(base_name = "Canidae", show = "full")  # from cache

# --- Pattern 2: explicit dict-style — full control over labels and timing ---
dc["canidae_occs"] = pbdb_occurrences(base_name = "Canidae", show = "full")
occs = dc["canidae_occs"]

# --- Pattern 3: set_autocaching! — zero call-site changes, but requires
#     instrumented or wrapped functions (see Pattern 3 section below) ---
set_autocaching!(true; cache = dc)
occs = pbdb_occurrences(base_name = "Canidae", show = "full")   # fetches + stores
occs = pbdb_occurrences(base_name = "Canidae", show = "full")   # from cache, unchanged call
set_autocaching!(false)
```

---

## Cache Store

`DataCache` constructors span a gradient from zero-configuration to full path control:

```julia
# Zero config — lifecycle-managed default store
dc = DataCache()

# Named store — lifecycle-managed, no path management required
dc = DataCache(:project123)

# Explicit path — portable, shareable across systems or users
dc = DataCache(joinpath(homedir(), ".datacaches", "project1"))

# Module-scoped — for package authors, namespaced by package UUID
dc = DataCaches.scratch_datacache!(MyPackage_UUID, :results)
```

`DataCache()` and `DataCache(:name)` store data inside DataCaches.jl's Scratch.jl depot
(`~/.julia/scratchspaces/<DataCaches-UUID>/caches/`) and are automatically removed when
DataCaches.jl is uninstalled and `Pkg.gc()` is run — no manual cleanup needed.

`DataCache("/path")` gives full control and portability: copy or archive the directory
to share a cache across machines or users.

`scratch_datacache!` is intended for package authors who need a cache scoped to their
package's UUID with no risk of collision. See [Using DataCaches.jl inside a package](#using-datacachesjl-inside-a-package-module-scoped-cache).

---

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
relabel!(dc, "canidae_occs", "canidae")   # by label
relabel!(dc, 2, "canidae")                # by sequence index

# Retrieve by sequence index
df = dc[1]

# Remove entries
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

dc = DataCache(:project1)
set_autocaching!(true; cache = dc)

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
argument, results go to the shared [`default_filecache()`](https://juliadata.org/DataCaches.jl).
If your package should instead write to its own namespaced
[`scratch_datacache!`](https://juliadata.org/DataCaches.jl) store by default — while
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

See the [Library Integration guide](https://juliadata.org/DataCaches.jl/integration/)
for complete working examples of all three patterns (private cache, user-controlled
cache, and package-owned default cache).

---

## Comparison of caching strategies

| | `@filecache` | `@filecache!` | `@memcache` | `dc["label"] = ...` | `set_autocaching!` |
|---|---|---|---|---|---|
| Persists across sessions | Yes | Yes | No | Yes | Yes |
| Works with any library | Yes | Yes | Yes | Yes | Only if instrumented (or wrapped) |
| Changes call sites | Yes | Yes | Yes | Yes | No |
| Label is human-readable | Hash | Hash | Hash | Yes | Hash |
| Always re-executes | No | **Yes** | No | Yes | With `force_refresh = true` |
| Granularity | Per macro site | Per macro site | Per macro site | Any | Per function |

---

## Documentation

The full API reference is hosted online at <https://juliadata.org/DataCaches.jl>.

To build the documentation locally, run from the repository root:

```bash
# One-time setup
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
# Build
julia --project=docs docs/make.jl
```

The generated site is written to `docs/build/`. Open `docs/build/index.html`
in a browser to view it. See [`docs/README.md`](docs/README.md) for details.

---

## Testing

Run the full test suite with:

```bash
julia -e 'import Pkg; Pkg.test("DataCaches")'
```

Or, in package manager REPL mode (`]`):

```
pkg> test DataCaches
```

See [`test/README.md`](test/README.md) for more options.

---

## Environment variable

| Variable | Default | Description |
|---|---|---|
| `DATACACHES_DEFAULT_STORE` | See below | Override the default store used by `DataCache()` (no-argument constructor) |

When `DATACACHES_DEFAULT_STORE` is not set, the no-argument `DataCache()` constructor stores its data inside the DataCaches depot at `~/.julia/scratchspaces/<DataCaches-UUID>/caches/user/_GLOBAL/`. This is equivalent to `DataCache(:_GLOBAL)`. The default cache is automatically removed if DataCaches.jl is ever uninstalled and `Pkg.gc()` is run.

## Named depot caches

Pass a `Symbol` to `DataCache` to create a named user cache inside DataCaches.jl's
own depot directory. No path management or UUIDs required, and the cache is
automatically removed if DataCaches.jl is uninstalled:

```julia
dc = DataCache(:myproject)
```

The store lives at `~/.julia/scratchspaces/<DataCaches-UUID>/caches/user/myproject/`.
Multiple independent stores are created by using different symbols:

```julia
queries = DataCache(:pbdb_queries)
taxa    = DataCache(:taxonomy)
```

This form is also convenient for library authors who want a lifecycle-managed cache
without introducing their own path management:

```julia
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)
function __init__()
    _CACHE[] = DataCache(:mypackage_results)
end
```

## Caches — managing named caches

`DataCaches.Caches` is a submodule that provides a filesystem-style interface for
browsing and managing the caches that live in the DataCaches scratchspace
(`~/.julia/scratchspaces/<DataCaches-UUID>/`). It is public but not exported;
access it as `DataCaches.Caches`.

The scratchspace uses a structured subdirectory layout:

```
~/.julia/scratchspaces/<DataCaches-UUID>/
  caches/
    user/
      _GLOBAL/             ← DataCache() / DataCache(:_GLOBAL) default store
      <name>/              ← DataCache(:name) stores
    module/<uuid>/<key>/   ← scratch_datacache!(uuid, key) stores
```

```julia
using DataCaches

# Inspect the scratchspace
DataCaches.Caches.pwd()           # → "/home/user/.julia/scratchspaces/c1455f2b-..."
DataCaches.Caches.defaultstore()  # → ".../c1455f2b-.../caches/user/_GLOBAL"
DataCaches.Caches.ls()            # → [:user, :module]                          (caches root — default)
DataCaches.Caches.ls(:user)       # → [:_GLOBAL, :myproject, :taxonomy, ...]    (user stores)
DataCaches.Caches.ls(:module)     # → [Symbol("uuid1/key1"), ...]               (module stores)

# Create named caches as usual, then manage them through Caches
queries = DataCache(:myproject)
taxa    = DataCache(:taxonomy)

# Rename within scratchspace
DataCaches.Caches.mv(:myproject, :archived_project)

# Copy within scratchspace
DataCaches.Caches.cp(:taxonomy, :taxonomy_backup)

# Export to / import from the filesystem
DataCaches.Caches.mv(:archived_project, "/data/exports/myproject")  # move out
DataCaches.Caches.mv("/data/imports/shared_cache", :shared)         # move in
DataCaches.Caches.cp(:taxonomy, "/tmp/taxonomy_snapshot")           # copy out

# Remove
DataCaches.Caches.rm(:taxonomy_backup)
DataCaches.Caches.rm(:nonexistent; force=true)  # silently ignore if absent
```

See the [full API reference](https://juliadata.org/DataCaches.jl) for complete
documentation of each function.

---

## CacheAssets — managing assets within a cache

`DataCaches.CacheAssets` is a submodule that provides a filesystem-style interface
for inspecting and managing individual *entries* within a `DataCache`. It is public
but not exported; use `using DataCaches.CacheAssets` to bring it into scope.

All functions accept an optional leading `DataCache` argument. When omitted,
`default_filecache()` is used.

```julia
using DataCaches
using DataCaches.CacheAssets

dc = DataCache(:myproject)

# --- List ---
CacheAssets.ls(dc)                                 # normal detail: seq, timestamp, label, path
CacheAssets.ls(dc; detail = :minimal)              # seq + label only
CacheAssets.ls(dc; detail = :full)                 # + access time, file size, format
CacheAssets.ls(dc; pattern = r"canidae")           # filter by label/description
CacheAssets.ls(dc; sortby = :dateaccessed_desc)    # LRU: oldest access first
CacheAssets.ls(dc; sortby = :size_desc)            # largest first
CacheAssets.ls(dc; after = DateTime("2026-01-01T00:00:00"), labeled = true)

# --- Remove ---
CacheAssets.rm(dc, "old_label")                    # by label
CacheAssets.rm(dc, 2)                              # by sequence index
CacheAssets.rm(dc, "label1", "label2", 5)          # multiple assets, single index rewrite

# --- Relabel within a cache ---
CacheAssets.mv(dc, "old_label", "new_label")
CacheAssets.mv(dc, 3, "new_label")                 # by sequence index

# --- Move to another cache ---
dc2 = DataCache(:archive)
CacheAssets.mv(dc, "canidae_occs", dc2)
CacheAssets.mv(dc, "canidae_occs", dc2; label = "canidae_archived")

# --- Copy to another cache ---
CacheAssets.cp(dc, "canidae_occs", dc2)
CacheAssets.cp(dc, ["canidae_occs", "dino_taxa"], dc2)   # multiple assets

# --- Default cache (omit the DataCache argument) ---
CacheAssets.ls()
CacheAssets.rm("stale_entry")
CacheAssets.mv("old", "new")
```

### Access-time tracking

By default, every `read` updates the `dateaccessed` timestamp on each entry's
[`CacheKey`](@ref), enabling LRU inspection and future pruning. This requires
rewriting the cache index on every read. For caches that are read very frequently
or that contain many entries, opt out by constructing the cache with
`track_access = false`:

```julia
dc = DataCache(:high_frequency; track_access = false)
```

---

## Using DataCaches.jl inside a package (module-scoped cache)

Use `scratch_datacache!` with your package's UUID to create a named cache scoped to
your package's identity, stored under `<DataCaches-depot>/caches/module/<your-UUID>/<key>/`:

```julia
module MyPackage
using DataCaches

const _MY_UUID = Base.UUID("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")  # copy from Project.toml
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    _CACHE[] = DataCaches.scratch_datacache!(_MY_UUID, :results)
end

get_cache() = _CACHE[]
end
```

The cache is namespaced by UUID so it will not collide with stores from other packages.
Use different `key` strings (second argument) to maintain independent cache stores
within the same package. The cache is managed as part of the DataCaches depot and is
removed when DataCaches.jl is uninstalled and `Pkg.gc()` is run.


## About

This package addresses a general need for disk-based memoization and caching in contexts such as 
analytics, informatics, and software development, where identical database queries or computationally 
expensive functions are executed repeatedly and expected to return stable results between manual cache refreshes. 
It is broadly applicable, but its combination of flexible caching mechanisms and minimal syntactic overhead makes 
it particularly effective for a specific class of problems not well handled by existing tools.

However, in addition, its broad range of caching mechanisms *and* syntax makes it 
uniquely suited to solve one class of problems that none of the other offerings out 
there could do in quite this way.

A primary use case arises in instructional settings (labs, workshops, and courses) where many users simultaneously issue repeated database queries, often overwhelming shared resources such as the database itself or available network bandwidth.
By memoizing these calls and persisting results to disk, the package substantially reduces this load. 
In constrained environments with limited or unreliable connectivity, caches can be precomputed and distributed with course materials, allowing code to run with little to no modification. 
In automatic modes, the caching layer remains effectively invisible, preserving the clarity and integrity of the instructional code.

The design prioritizes lightweight, unobtrusive integration into REPL and script workflows, requiring no changes to program logic or structure. 
Cache storage is fully transparent and accessible both programmatically and via the file system, yet entirely optional—novice users can remain unaware of its existence. 
Caches persist across sessions and can be shared across systems by copying or archiving the underlying directory.
