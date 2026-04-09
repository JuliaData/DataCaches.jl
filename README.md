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

### Cache setup approaches

There is a gradient from no setup approach to full control.

#### The "No-setup" setup: the default cache

In the no-setup approach, we do not explicitly open a cache 
before running any of the cache operations, and a default
"`:_DEFAULT`" cache will be used automatically, so this step 
can be skipped.

 The default file cache is the cache that will be used if we do 
 NOT specify a cache explicitly is given by
 
```julia
using DataCaches
dc = DataCaches.default_filecache()
```

The default cache path will be located in the `DataCaches` module-scoped scratchspace in the Julia depot directory, 

```
/home/username/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5/caches/user/_DEFAULT
```

and is equivalent to the user creating a cache named "`:_DEFAULT`" using public cache creation mechanics:

```julia
dc = DataCache(:_DEFAULT)
```

#### A named cache in the `DataCaches` scratchspace depot

This approach create caches that live inside DataCaches.jl's own depot,
siloed from each other and the default :`:_DEFAULT`".

All these caches are automatically deleted if this package is 
uninstalled and `Pkg.gc()` are run.

Individual users can name individual caches:

```julia
using DataCaches

# for separating projects specific 
dc = DataCache(:project123)
# store: /home/username/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5/caches/user/project123
dc = DataCache(:gbifdata)
# store: /home/username/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5/caches/user/gbifdata
dc = DataCache(:mcmcruns)
# store: /home/username/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5/caches/user/mcmcruns
```

Package authors (or users) can have module-space specific silos:

```julia
using DataCaches
dc = DataCaches.scratch_datacache!(MyPackage_UUID, :rasterdata)
# store: /home/username/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5/caches/module/<MyPackage_UUID>/rasterdata
```

#### A cache in an arbitrary filesystem path

To locate a cache outside of this package's scratchspace depot, 
for easier or customized file-system management, or for cache 
assets to persist even if this package is uninstalled, provide
any writeable path as a string.

```julia
using DataCaches
# Explicit path, for a cache open to 
# non-hidden file-system views.
dc = DataCache(joinpath(homedir(), "shared", "data", "downloads"))
dc = DataCache("/tmp/workshop/data"))
```


### Caching approaches

Again, different approaches providing different levels of automation vs. control.

```julia
using DataCaches, PaleobiologDB

# Optional: show caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

# Here we use a siloed project specific cache.
dc = DataCache(:myproject)
set_default_filecache!(dc)

# If we did not run `set_default_filecache!` above
# , then the default cache will be used in all 
# the patterns below, with `dc` being given by:
# dc = DataCaches.default_filecache()

# --- Pattern 1: @filecache — works with any function, no setup beyond the cache ---
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

More details on these usage patterns can be found in the [note on usage patterns](usage-patterns.md).

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

---
## Inspecting entries — `entries`, `entry`, `labels`

These exported functions provide the primary API for examining what is stored in a cache.
No submodule import is needed.

```julia
using DataCaches

dc = DataCache(:myproject)

# --- Get all entries (returns Vector{CacheEntry}) ---
all     = entries(dc)
labeled = entries(dc; labeled = true)          # only entries with a user-assigned label
recent  = entries(dc; after = DateTime("2026-01-01T00:00:00"))
lru     = entries(dc; sortby = :dateaccessed_desc)   # oldest-accessed first (LRU)
big     = entries(dc; sortby = :size_desc)            # largest first
found   = entries(dc; pattern = r"canidae")           # regex on label / description
entries()                                             # default cache

# --- Get a single entry by label or sequence index ---
e = entry(dc, "canidae_occs")   # by label  → CacheEntry (throws KeyError if absent)
e = entry(dc, 3)                # by seq    → CacheEntry
e = entry("canidae_occs")       # default cache

# Use the entry to read data, delete, relabel, etc.
data = read(dc, e)
delete!(dc, e)
relabel!(dc, e, "canidae_occurrences")

# --- Get all user-assigned labels ---
lbls = labels(dc)    # → Vector{String}, no empty strings
labels()             # default cache
```

Each `CacheEntry` has these fields:

| Field          | Type       | Description                                             |
|:---------------|:-----------|:--------------------------------------------------------|
| `e.id`         | `String`   | UUID (unique identifier)                                |
| `e.seq`        | `Int`      | Stable integer index shown by `showcache`               |
| `e.label`      | `String`   | User-assigned label (empty if none)                     |
| `e.path`       | `String`   | Absolute path to the backing file                       |
| `e.description`| `String`   | Source expression (from `@filecache`; empty if none)    |
| `e.datecached` | `DateTime` | When the entry was written                              |
| `e.dateaccessed`|`DateTime` | When the entry was last read                            |

> **Backward compatibility:** `CacheKey` is a silent alias for `CacheEntry`. Code
> written against earlier releases continues to work unchanged.

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

# --- List (data) — same filter/sort kwargs as entries() ---
all_entries = CacheAssets.ls(dc)                                 # → Vector{CacheEntry}
all_entries = CacheAssets.ls(dc; pattern = r"canidae")           # filter by label/description
all_entries = CacheAssets.ls(dc; sortby = :dateaccessed_desc)    # LRU: oldest access first
all_entries = CacheAssets.ls(dc; sortby = :size_desc)            # largest first
all_entries = CacheAssets.ls(dc; after = DateTime("2026-01-01T00:00:00"), labeled = true)

# --- List (display) ---
CacheAssets.ls!(dc)                                # normal detail: seq, timestamp, label, path
CacheAssets.ls!(dc; detail = :minimal)             # seq + label only
CacheAssets.ls!(dc; detail = :full)                # + access time, file size, format
CacheAssets.ls!(dc; pattern = r"canidae")          # filter by label/description (same as ls)
CacheAssets.ls!(dc; sortby = :dateaccessed_desc)   # LRU: oldest access first
CacheAssets.ls!(dc; sortby = :size_desc)           # largest first
CacheAssets.ls!(dc; io = my_io)                    # redirect output

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
CacheAssets.ls()                                   # → Vector{CacheEntry}
CacheAssets.ls!()                                  # prints to stdout
CacheAssets.rm("stale_entry")
CacheAssets.mv("old", "new")
```

### Access-time tracking

By default, every `read` updates the `dateaccessed` timestamp on each entry's
[`CacheEntry`](@ref), enabling LRU inspection and future pruning. This requires
rewriting the cache index on every read. For caches that are read very frequently
or that contain many entries, opt out by constructing the cache with
`track_access = false`:

```julia
dc = DataCache(:high_frequency; track_access = false)
```

## Caches — managing named caches

`DataCaches.Caches` is a submodule that provides a filesystem-style interface for
browsing and managing the caches (rather than assets within a particular cache) that live in the DataCaches scratchspace
(`~/.julia/scratchspaces/<DataCaches-UUID>/`). It is public but not exported;
access it as `DataCaches.Caches`.

The scratchspace uses a structured subdirectory layout:

```
~/.julia/scratchspaces/<DataCaches-UUID>/
  caches/
    user/
      _DEFAULT/             ← DataCache() / DataCache(:_DEFAULT) default store
      <name>/              ← DataCache(:name) stores
    module/<uuid>/<key>/   ← scratch_datacache!(uuid, key) stores
```

```julia
using DataCaches

# Inspect the scratchspace
DataCaches.Caches.pwd()           # → "/home/user/.julia/scratchspaces/c1455f2b-..."
DataCaches.Caches.defaultstore()  # → ".../c1455f2b-.../caches/user/_DEFAULT"
DataCaches.Caches.ls()            # → [:user, :module]                          (caches root — default)
DataCaches.Caches.ls(:user)       # → [:_DEFAULT, :myproject, :taxonomy, ...]    (user stores)
DataCaches.Caches.ls(:module)     # → [Symbol("uuid1/key1"), ...]               (module stores)
DataCaches.Caches.ls!()           # prints caches root to stdout
DataCaches.Caches.ls!(:user)      # prints user store names to stdout
DataCaches.Caches.ls!(:user; io = my_io)  # redirect output

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
