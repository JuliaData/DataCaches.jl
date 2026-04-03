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

## Purpose

The purpose of this package is to provide a persistent, file-backed key-value store for arbitrary Julia objects, keyed by user-assigned labels or auto-generated argument hashes.
This enables short-circuiting of expensive function calls by returning stored results instead of recomputing repeated calls across Julia sessions while also providing a portable, inspectable cache that can be shared across users or systems without requiring database infrastructure.

This package also provides mechanisms allowing library developers to patch in support for a fully transparent, under-the-hood auto-caching layer that requires no changes to user-facing call syntax.
This keeps exploratory and instructional code clean and readable, with caching remaining invisible in automatic mode and introducing no modifications to program logic or presentation.

## Features

DataCaches.jl provides three complementary interfaces aligned with its [purpose](#Purpose): 

- an explicit Dict-style API for manual cache control

```julia
# Just like a `Dict`, but auto-persists across sessions.
cache["fig1"] = plot(...)
fig1 = cache["fig1"] 
```
- a lightweight memoization mechanism enabling selective, automated caching of function call (and particular combination of run time argument values).

```julia
# If the active disk cache does not have this particular 
# combination of function name and argument values stored,
# then the function will be evaluated, cached, and returned.
foo = @filecache func1(x, y) 
# Function not evaluated; cached result returned
bar = @filecache func1(x, y) 
```

- and a fully seamless mode in which (instrumented) function calls are cached on first execution and transparently retrieved thereafter

```julia
# Automatically cache all instrumented
# functions.
set_autocaching!(true)
# If the active disk cache does not have this particular 
# combination of function name and argument values stored,
# then the function will be evaluated, cached, and returned.
foo = func1(x, y) 
# Function not evaluated; cached result returned
bar = func1(x, y) 
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

```julia
using DataCaches
using PaleobiologDB # For example

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

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

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

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

# Optional: track caching operations in debug logs
ENV["JULIA_DEBUG"] = "DataCaches"

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

When `DATACACHES_DEFAULT_STORE` is not set, the no-argument `DataCache()` constructor stores its data in a [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) scratch space under the active Julia depot (`~/.julia/scratchspaces/<DataCaches-UUID>/default/`). This integrates with Julia's package manager: the default cache is automatically removed if DataCaches.jl is ever uninstalled and `Pkg.gc()` is run.

## Named scratch-backed caches

Pass a `Symbol` to `DataCache` to create a named cache within DataCaches.jl's own
[Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) depot directory. No path
management or UUIDs required, and the cache is automatically removed if DataCaches.jl
is uninstalled:

```julia
dc = DataCache(:myproject)
```

The store lives at `~/.julia/scratchspaces/<DataCaches-UUID>/myproject/`. Multiple
independent stores are created by using different symbols:

```julia
queries = DataCache(:pbdb_queries)
taxa    = DataCache(:taxonomy)
```

This form is also convenient for library authors who want a lifecycle-managed cache
without introducing their own scratch space:

```julia
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)
function __init__()
    _CACHE[] = DataCache(:mypackage_results)
end
```

## Depot — managing named caches

`DataCaches.Depot` is a submodule that provides a filesystem-style interface for
browsing and managing the named caches that live in the DataCaches depot
(`~/.julia/scratchspaces/<DataCaches-UUID>/`). It is public but not exported;
access it as `DataCaches.Depot`.

```julia
using DataCaches

# Inspect the depot
DataCaches.Depot.pwd()          # → "/home/user/.julia/scratchspaces/c1455f2b-..."
DataCaches.Depot.defaultstore() # → ".../c1455f2b-.../default"
DataCaches.Depot.ls()           # → ["myproject", "taxonomy", ...]

# Create named caches as usual, then manage them through the Depot
queries = DataCache(:myproject)
taxa    = DataCache(:taxonomy)

# Rename within depot
DataCaches.Depot.mv(:myproject, :archived_project)

# Copy within depot
DataCaches.Depot.cp(:taxonomy, :taxonomy_backup)

# Export to / import from the filesystem
DataCaches.Depot.mv(:archived_project, "/data/exports/myproject")  # move out
DataCaches.Depot.mv("/data/imports/shared_cache", :shared)         # move in
DataCaches.Depot.cp(:taxonomy, "/tmp/taxonomy_snapshot")           # copy out

# Remove
DataCaches.Depot.rm(:taxonomy_backup)
DataCaches.Depot.rm(:nonexistent; force=true)  # silently ignore if absent
```

See the [full API reference](https://juliadata.org/DataCaches.jl) for complete
documentation of each function.

---

## Depot — managing named caches

`DataCaches.Depot` is a submodule that provides a filesystem-style interface for
browsing and managing the named caches that live in the DataCaches depot
(`~/.julia/scratchspaces/<DataCaches-UUID>/`). It is public but not exported;
access it as `DataCaches.Depot`.

```julia
using DataCaches

# Inspect the depot
DataCaches.Depot.pwd()          # → "/home/user/.julia/scratchspaces/c1455f2b-..."
DataCaches.Depot.defaultstore() # → ".../c1455f2b-.../default"
DataCaches.Depot.ls()           # → ["myproject", "taxonomy", ...]

# Create named caches as usual, then manage them through the Depot
queries = DataCache(:myproject)
taxa    = DataCache(:taxonomy)

# Rename within depot
DataCaches.Depot.mv(:myproject, :archived_project)

# Copy within depot
DataCaches.Depot.cp(:taxonomy, :taxonomy_backup)

# Export to / import from the filesystem
DataCaches.Depot.mv(:archived_project, "/data/exports/myproject")  # move out
DataCaches.Depot.mv("/data/imports/shared_cache", :shared)         # move in
DataCaches.Depot.cp(:taxonomy, "/tmp/taxonomy_snapshot")           # copy out

# Remove
DataCaches.Depot.rm(:taxonomy_backup)
DataCaches.Depot.rm(:nonexistent; force=true)  # silently ignore if absent
```

See the [full API reference](https://juliadata.org/DataCaches.jl) for complete
documentation of each function.

---

## Using DataCaches.jl inside a package (own lifecycle)

If you need the cache tied to *your own* package's lifecycle (removed when *your* package
is uninstalled, independently of DataCaches.jl), use `scratch_datacache!` with your
package's UUID:

```julia
module MyPackage
using DataCaches

const _MY_UUID = Base.UUID("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")  # copy from Project.toml
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    _CACHE[] = DataCaches.scratch_datacache!(_MY_UUID, "results")
end

get_cache() = _CACHE[]
end
```

The scratch space lives at `~/.julia/scratchspaces/<MY_UUID>/results/` and is automatically removed when your package is uninstalled and `Pkg.gc()` is run. Use different `key` strings (second argument) to maintain independent cache stores within the same package.


## About

This package addresses a general need for disk-based memoization and caching in contexts such as 
analytics, informatics, and software development, where identical database queries or computationally 
expensive functions are executed repeatedly and expected to return stable results between manual cache refreshes. 
It is broadly applicable, but its combination of flexible caching mechanisms and minimal syntactic overhead makes 
it particularly effective for a specific class of problems not well handled by existing tools.

However, in addition, its broad range of caching mechanisms *and* syntax makes it 
uniquely suited to solve one class of problems that none of the other offerings out 
there could do in quite this way.

This package addresses a general need for disk-based memoization and caching in contexts such as analytics, informatics, and software development, 
where identical database queries or computationally expensive functions are executed repeatedly and expected to return stable results between manual cache refreshes. 
It is broadly applicable, but its combination of flexible caching mechanisms and minimal syntactic overhead makes it particularly effective for a specific class of problems not well handled by existing tools.

A primary use case arises in instructional settings (labs, workshops, and courses) where many users simultaneously issue repeated database queries, often overwhelming shared resources such as the database itself or available network bandwidth.
By memoizing these calls and persisting results to disk, the package substantially reduces this load. 
In constrained environments with limited or unreliable connectivity, caches can be precomputed and distributed with course materials, allowing code to run with little to no modification. 
In automatic modes, the caching layer remains effectively invisible, preserving the clarity and integrity of the instructional code.

The design prioritizes lightweight, unobtrusive integration into REPL and script workflows, requiring no changes to program logic or structure. 
Cache storage is fully transparent and accessible both programmatically and via the file system, yet entirely optional—novice users can remain unaware of its existence. 
Caches persist across sessions and can be shared across systems by copying or archiving the underlying directory.