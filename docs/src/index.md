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

## Caches — store management

`DataCaches.Caches` is a submodule (public, not exported) that provides a
filesystem-style interface for managing the caches living in the DataCaches
scratchspace directory (`~/.julia/scratchspaces/<DataCaches-UUID>/`).

The scratchspace organises stores into subdirectories by kind:

```
~/.julia/scratchspaces/<DataCaches-UUID>/
  caches/
    user/
      _GLOBAL/             ← DataCache() / DataCache(:_GLOBAL) default store
      <name>/              ← DataCache(:name) stores
    module/<uuid>/<key>/   ← scratch_datacache!(uuid, key) stores
```

The `Caches` submodule lets you inspect, rename, copy, move, and remove stores
without needing to construct or track the underlying path yourself.

Access all functions as `DataCaches.Caches.<function>`.

### Inspection

```julia
using DataCaches

# Scratchspace root — the top-level scratchspaces directory for DataCaches
DataCaches.Caches.pwd()
# → "/home/user/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5"

# Path to a specific user store (directory need not exist yet)
DataCaches.Caches.pwd(:myproject)
# → ".../c1455f2b-.../caches/user/myproject"

# Path to the default store (respects DATACACHES_DEFAULT_STORE env var)
DataCaches.Caches.defaultstore()
# → ".../c1455f2b-.../caches/user/_GLOBAL"

# Raw listing of the scratchspace root (default)
DataCaches.Caches.ls()
# → [:caches]

# List user stores (DataCache(:name))
DataCaches.Caches.ls(:user)
# → [:_GLOBAL, :myproject, :taxonomy, :archived_results]

# List module-scoped stores (scratch_datacache!(uuid, key))
DataCaches.Caches.ls(:module)
# → [Symbol("00000000-.../results"), Symbol("aaaabbbb-.../datacache")]
```

### Renaming and copying within the scratchspace

```julia
# Create some stores
queries = DataCache(:pbdb_queries)
taxa    = DataCache(:taxonomy)

# Rename
DataCaches.Caches.mv(:pbdb_queries, :paleodb_queries)

# Duplicate
DataCaches.Caches.cp(:taxonomy, :taxonomy_backup)

# Remove
DataCaches.Caches.rm(:taxonomy_backup)
DataCaches.Caches.rm(:nonexistent; force=true)  # no-op if absent
```

### Moving and copying between scratchspace and filesystem

The `mv` and `cp` functions accept one `Symbol` (store name) and one
`AbstractString` (filesystem path) in either order:

```julia
# Export — move a named cache out of the scratchspace to a filesystem path
DataCaches.Caches.mv(:paleodb_queries, "/data/exports/paleodb_queries")

# Import — move a filesystem directory into the scratchspace as a named cache
DataCaches.Caches.mv("/data/imports/shared_cache", :shared)

# Export copy (source stays in scratchspace)
DataCaches.Caches.cp(:taxonomy, "/tmp/taxonomy_snapshot")

# Import copy (source stays on filesystem)
DataCaches.Caches.cp("/data/reference/baseline", :baseline)
```

These round-trip cleanly with [`importcache!`](@ref) and
[`movecache!`](@ref): use `Caches.mv`/`Caches.cp` when working entirely with
named stores, and `importcache!`/`movecache!` when working with
arbitrary `DataCache` objects.

### Quick-reference table

| Function | Description |
|---|---|
| `Caches.pwd()` | Scratchspace root path |
| `Caches.pwd(:name)` | Path to a user named store (`caches/user/<name>`) |
| `Caches.defaultstore()` | Path to the default store (`caches/user/_GLOBAL`) |
| `Caches.ls()` | Raw subdirectory listing of the scratchspace root — same as `ls(:root)` |
| `Caches.ls(:root)` | Raw subdirectory listing of the scratchspace root |
| `Caches.ls(:user)` | Names of `DataCache(:name)` stores |
| `Caches.ls(:module)` | `"<uuid>/<key>"` strings for `scratch_datacache!` stores |
| `Caches.rm(:name; force=false)` | Remove a user named store |
| `Caches.mv(:old, :new)` | Rename user store within scratchspace |
| `Caches.mv(:name, path)` | Move (export) user store to filesystem path |
| `Caches.mv(path, :name)` | Move (import) filesystem directory into scratchspace |
| `Caches.cp(:old, :new)` | Copy user store within scratchspace |
| `Caches.cp(:name, path)` | Copy (export) user store to filesystem path |
| `Caches.cp(path, :name)` | Copy (import) filesystem directory into scratchspace |

### Caches API reference

```@autodocs
Modules = [DataCaches.Caches]
```
