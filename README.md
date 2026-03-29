# DataCaches.jl

[![CI](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml)
[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaData.github.io/DataCaches.jl/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaData.github.io/DataCaches.jl/dev)

A lightweight, file-backed key-value cache for Julia for workflows
that make frequent time-, internet or network bandwidth expensive function calls 
(remote API queries, long-running computations) and need results to 
be available across Julia sessions.
*Any* Julia object can be cached to disk to persist across sessions as `.jls` Julia serialized object files, but a special consideration is given to `DataFrame` objects as these are stored as `.csv` files, so they can also be independently inspected, accessed, and manipulated if needed.


Three levels of caching are provided, from manual to fully automatic:

| Level     | Mechanism              | Persistence     | Wrapper or library integration required? |
|-----------|------------------------|-----------------|------------------------------------------|
| Explicit  | `dc["label"] = result` | Across sessions | No                                       |
| Memoized  | `@filecache`           | Across sessions | No                                       |
| Memoized  | `@memcache`            | In-session only | No                                       |
| Automatic | `set_autocaching!`           | Across sessions | Yes                                      |

## Motivation

This package is generally useful anywhere and everywhere disk-based memoization and caching are required (e.g. analytics, informatics, or software development projects, where databases or computationally expensive functions are frequently queried identically multiple times for the exact same results, and in which backend data query results are not expected to change between (manual) cache refresh operations, or it does not matter if they do.

However, in addition, its broad range of caching mechanisms *and* syntax makes it uniquely suited to solve one class of problems that none of the other offerings out there could do in quite this way.

When teaching labs, practicals, workshops, or courses in which the activities involve querying databases, the 
resulting large numbers of people almost hitting the database repeatedly and frequently in 
at almost the same time often causes issues with the resource itself or supporting resources (such as internet bandwidth).

Memoizing the function calls to the database and caching the data to disk reduces most of this resource stress significantly.
In more extreme circumstances, e.g. teaching in conditions where network access is
slow, unreliable, or just not available, the caches can be distributed on disk or as part of the workshop materials.
One of the key design features is that client code can run without little to (in auto mode) no modification, so the
cache mechanisms do not pollute the syntax and presentation of primary codebase being taught or run.


There are many other solutions out there, but this package is particularly useful in the above contexts due to the following design objectives:

- Syntactically lightweight or (almost) invisible. 
- Seamless integration into REPL- or script-based workflow without requiring any change of logic or structure.
- Straight-forward, flexible, and completely transparent management of cache store, with views and adatra accessible not only 
  through Julia for convenience, but also through standard file-system tools.
- Yet, cache store setup and management is *completely* optional, and novice users need not even be aware of its existence or operation.
- The cache store and usage persists across Julia sessions (i.e., not in-memory only, though that is supported).
- A particular cache store file-system directory can be shared across different computing systems or users by copying, cloning, or as an compressed archive.

`DataCaches.jl` offers three approaches to manipulating the cache that satisfy these objectives, each varying with differences in emphases on the usage pattern or requirement: (1) an explicit `Dict` style interface for folks comfortable with managing their explicit caching/decaching; (1) a syntactically-lightweight memoization approach that allows for selective application of automated background cache pre-population to particular function calls; a fully seamless approach where all function calls (or all calls of particular functions) will have their results cached on first call and retrieved on subsequent calls.


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

---

## Quick Start

```julia
using DataCaches
using PaleobiologDB # For example

# Create a cache backed by a directory on disk
dc = DataCache(joinpath(homedir(), ".datacaches", "myproject"))

# Store and retrieve a result by label
dc["dinosaurs"] = pbdb_occurrences(base_name = "Dinosauria", show = "full")
df = dc["dinosaurs"]
```

---

## Usage Patterns

### Pattern 1 — Explicit label assignment

The most transparent pattern. You control exactly what is stored and when it is
retrieved, using dictionary-style indexing. Works with any data source.

```julia
using DataCaches, PaleobiologyDB

dc = DataCache(joinpath(homedir(), ".datacaches", "project1"))

# Store
dc["canidae_occs"]  = pbdb_occurrences(base_name = "Canidae", show = "full")
dc["dinosaur_taxa"] = pbdb_taxa(name = "Dinosauria", vocab = "pbdb")

# Retrieve
occs = dc["canidae_occs"]
taxa = dc["dinosaur_taxa"]

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

# Remove entries
delete!(dc, "trilobites")   # by label
delete!(dc, 2)              # by sequence index
clear!(dc)                  # remove all entries

# Compact sequence numbers after many deletions
reindexcache!(dc)
```

### Pattern 2 — Memoized function calls

`@filecache` and `@memcache` wrap a single function call expression and cache
its result automatically, keyed on the runtime values of all arguments. If the
same call appears again (even in a new session, for `@filecache`), the cached
result is returned immediately without re-executing the function.

These macros are generic: they work with any function from any library, with no
integration required on the library's part.

#### `@filecache` — persist across Julia sessions

```julia
using DataCaches, PaleobiologyDB

dc = DataCache(joinpath(homedir(), ".datacaches", "project1"))
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

dc = DataCache(joinpath(homedir(), ".datacaches", "biodiversity"))
set_default_filecache!(dc)

occs = @filecache GBIF2.occurrence_search(taxonKey = 212, limit = 300)
# Next session: same call with `@filecache` returns from disk, no network request
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

### Pattern 3 — Automatic caching

`set_autocaching!` installs a global hook that intercepts every call to an
instrumented function and transparently caches the result. Existing call sites
require no modification.

**This pattern requires the library to integrate DataCaches.jl** by calling the
`autocache` hook function internally (see [Integration API](#integration-api-for-library-authors)).
For libraries that have not done this, Pattern 2 (`@filecache`) is the practical
alternative — or you can write a thin wrapper yourself (shown below).

#### With a natively integrated library (e.g. PaleobiologyDB.jl)

```julia
using DataCaches, PaleobiologyDB

dc = DataCache(joinpath(homedir(), ".datacaches", "project1"))
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
dc = DataCache(joinpath(homedir(), ".datacaches", "biodiversity"))
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

---

## Full API Reference

The complete API reference is available in the [package documentation](https://JuliaData.github.io/DataCaches.jl/stable).

---

## Comparison of caching strategies

| | `dc["label"] = ...` | `@filecache` | `@memcache` | `set_autocaching!` |
|---|---|---|---|---|
| Persists across sessions | Yes | Yes | No | Yes |
| Works with any library | Yes | Yes | Yes | Only if integrated (or wrapped) |
| Changes call sites | Yes | Yes | Yes | No |
| Label is human-readable | Yes | Hash | Hash | Hash |
| Force re-fetch | Overwrite by label | Overwrite by label | `memcache_clear!` | `force_refresh = true` |
| Granularity | Any | Per macro site | Per macro site | Per function |

---

## Documentation

The API reference is hosted at <https://JuliaData.github.io/DataCaches.jl/stable>.

To build the docs locally, run from the repository root:

```bash
# One-time setup
julia --project=docs -e '
    import Pkg
    Pkg.develop(Pkg.PackageSpec(path=pwd()))
    Pkg.instantiate()
'

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
| `DATACACHES_DEFAULT_STORE` | `~/.cache/DataCaches` | Root directory used by `DataCache()` (no-argument constructor) |
