```@meta
CurrentModule = DataCaches
```

# DataCaches.jl

[![CI](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml)
[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaData.github.io/DataCaches.jl/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaData.github.io/DataCaches.jl/dev)

A lightweight, file-backed key-value cache for Julia workflows that make
frequent expensive function calls (remote API queries, long-running
computations) and need results available across Julia sessions.

Three levels of caching are provided, from lightest-weight to most manual:

| Level     | Mechanism              | Persistence      | Works with any function?  |
|-----------|------------------------|------------------|---------------------------|
| Memoized  | `@filecache`           | Across sessions  | Yes                       |
| Refresh   | `@filecache!`          | Across sessions  | Yes                       |
| Memoized  | `@memcache`            | In-session only  | Yes                       |
| Explicit  | `dc["label"] = result` | Across sessions  | Yes                       |
| Automatic | `set_autocaching!`     | Across sessions  | Only if instrumented      |

## Installation

At the Julia REPL, press `]` to enter package manager mode:

```
pkg> add DataCaches
```

## Quick Start

### Cache store

First, create a `DataCache`. The simplest form requires no configuration:

```julia
dc = DataCache()                                         # lifecycle-managed default
dc = DataCache(:myproject)                               # named, no path management
dc = DataCache(joinpath(homedir(), ".datacaches", "p1")) # explicit path
```

### Caching approaches

```julia
using DataCaches

dc = DataCache(:myproject)

# Memoized — works with any function, just wrap the call
set_default_filecache!(dc)
result = @filecache some_expensive_query(; taxon = "Dinosauria")  # fetches + stores
result = @filecache some_expensive_query(; taxon = "Dinosauria")  # from cache
result = @filecache! some_expensive_query(; taxon = "Dinosauria") # force refresh

# Explicit — dict-style, full control over labels
dc["dinosaurs"] = some_expensive_query(; taxon = "Dinosauria")
df = dc["dinosaurs"]

# Automatic — zero call-site changes, but requires instrumented functions
# (see Pattern 3 in the README for setup)
set_autocaching!(true; cache = dc)
result = some_expensive_query(; taxon = "Dinosauria")   # fetches + stores
result = some_expensive_query(; taxon = "Dinosauria")   # from cache, unchanged call
set_autocaching!(false)
```

For guidance on integrating DataCaches.jl into a library — from private scratch caches
to fully instrumented autocacheable functions with a package-owned default store — see
the [Library Integration](integration.md) guide.

## API Reference

```@index
```

```@autodocs
Modules = [DataCaches]
```

---

## Depot — store management

`DataCaches.Depot` is a submodule (public, not exported) that provides a
filesystem-style interface for managing the caches living in the DataCaches depot
directory (`~/.julia/scratchspaces/<DataCaches-UUID>/`).

The depot organises stores into subdirectories by kind:

```
~/.julia/scratchspaces/<DataCaches-UUID>/
  caches/
    defaultcache/          ← DataCache() default store
    local/<name>/          ← DataCache(:name) stores
    module/<uuid>/<key>/   ← scratch_datacache!(uuid, key) stores
```

The `Depot` submodule lets you inspect, rename, copy, move, and remove stores
without needing to construct or track the underlying path yourself.

Access all functions as `DataCaches.Depot.<function>`.

### Inspection

```julia
using DataCaches

# Depot root — the top-level scratchspaces directory for DataCaches
DataCaches.Depot.pwd()
# → "/home/user/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5"

# Path to a specific local store (directory need not exist yet)
DataCaches.Depot.pwd(:myproject)
# → ".../c1455f2b-.../caches/local/myproject"

# Path to the default store (respects DATACACHES_DEFAULT_STORE env var)
DataCaches.Depot.defaultstore()
# → ".../c1455f2b-.../caches/defaultcache"

# List local stores (DataCache(:name))
DataCaches.Depot.ls()              # default storetype is :local
DataCaches.Depot.ls(:local)
# → [:myproject, :taxonomy, :archived_results]

# List module-scoped stores (scratch_datacache!(uuid, key))
DataCaches.Depot.ls(:module)
# → [Symbol("00000000-.../results"), Symbol("aaaabbbb-.../datacache")]

# Raw listing of the depot root
DataCaches.Depot.ls(:root)
# → [:caches]
```

### Renaming and copying within the depot

```julia
# Create some stores
queries = DataCache(:pbdb_queries)
taxa    = DataCache(:taxonomy)

# Rename
DataCaches.Depot.mv(:pbdb_queries, :paleodb_queries)

# Duplicate
DataCaches.Depot.cp(:taxonomy, :taxonomy_backup)

# Remove
DataCaches.Depot.rm(:taxonomy_backup)
DataCaches.Depot.rm(:nonexistent; force=true)  # no-op if absent
```

### Moving and copying between depot and filesystem

The `mv` and `cp` functions accept one `Symbol` (depot name) and one
`AbstractString` (filesystem path) in either order:

```julia
# Export — move a named cache out of the depot to a filesystem path
DataCaches.Depot.mv(:paleodb_queries, "/data/exports/paleodb_queries")

# Import — move a filesystem directory into the depot as a named cache
DataCaches.Depot.mv("/data/imports/shared_cache", :shared)

# Export copy (source stays in depot)
DataCaches.Depot.cp(:taxonomy, "/tmp/taxonomy_snapshot")

# Import copy (source stays on filesystem)
DataCaches.Depot.cp("/data/reference/baseline", :baseline)
```

These round-trip cleanly with [`importcache!`](@ref) and
[`movecache!`](@ref): use `Depot.mv`/`Depot.cp` when working entirely with
depot-named stores, and `importcache!`/`movecache!` when working with
arbitrary `DataCache` objects.

### Quick-reference table

| Function | Description |
|---|---|
| `Depot.pwd()` | Depot root path |
| `Depot.pwd(:name)` | Path to a local named store (`caches/local/<name>`) |
| `Depot.defaultstore()` | Path to the default store (`caches/defaultcache`) |
| `Depot.ls()` | Local store names — same as `ls(:local)` |
| `Depot.ls(:local)` | Names of `DataCache(:name)` stores |
| `Depot.ls(:module)` | `"<uuid>/<key>"` strings for `scratch_datacache!` stores |
| `Depot.ls(:root)` | Raw subdirectory listing of the depot root |
| `Depot.rm(:name; force=false)` | Remove a local named store |
| `Depot.mv(:old, :new)` | Rename local store within depot |
| `Depot.mv(:name, path)` | Move (export) local store to filesystem path |
| `Depot.mv(path, :name)` | Move (import) filesystem directory into depot |
| `Depot.cp(:old, :new)` | Copy local store within depot |
| `Depot.cp(:name, path)` | Copy (export) local store to filesystem path |
| `Depot.cp(path, :name)` | Copy (import) filesystem directory into depot |

### Depot API reference

```@autodocs
Modules = [DataCaches.Depot]
```
