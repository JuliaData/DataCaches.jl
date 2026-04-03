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

Three caching levels are provided, from manual to fully automatic:

| Level     | Mechanism              | Persistence      | Library integration required? |
|-----------|------------------------|------------------|-------------------------------|
| Explicit  | `dc["label"] = result` | Across sessions  | No                            |
| Memoized  | `@filecache`           | Across sessions  | No                            |
| Memoized  | `@memcache`            | In-session only  | No                            |
| Automatic | `set_autocaching!`        | Across sessions  | Yes                           |

## Installation

At the Julia REPL, press `]` to enter package manager mode:

```
pkg> add DataCaches
```

## Quick Start

```julia
using DataCaches

dc = DataCache(joinpath(homedir(), ".datacaches", "myproject"))

dc["dinosaurs"] = some_expensive_query(; taxon = "Dinosauria")
df = dc["dinosaurs"]
```

## API Reference

```@index
```

```@autodocs
Modules = [DataCaches]
```

---

## Depot — store management

`DataCaches.Depot` is a submodule (public, not exported) that provides a
filesystem-style interface for managing the named caches living in the DataCaches
depot directory (`~/.julia/scratchspaces/<DataCaches-UUID>/`).

Named caches are those created via `DataCache(:symbol)`. The `Depot` submodule
lets you inspect, rename, copy, move, and remove them without needing to construct
or track the underlying path yourself.

Access all functions as `DataCaches.Depot.<function>`.

### Inspection

```julia
using DataCaches

# Depot root — the directory containing all named stores
DataCaches.Depot.pwd()
# → "/home/user/.julia/scratchspaces/c1455f2b-6d6f-4f37-b463-919f923708a5"

# Path to a specific named store (directory need not exist yet)
DataCaches.Depot.pwd(:myproject)
# → ".../c1455f2b-.../myproject"

# Path to the default store (respects DATACACHES_DEFAULT_STORE env var)
DataCaches.Depot.defaultstore()
# → ".../c1455f2b-.../default"

# List all named stores currently in the depot
DataCaches.Depot.ls()
# → ["myproject", "taxonomy", "archived_results"]
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
| `Depot.pwd(:name)` | Path to a named store |
| `Depot.defaultstore()` | Path to the default store |
| `Depot.ls()` | Names of all stores currently in the depot |
| `Depot.rm(:name; force=false)` | Remove a named store |
| `Depot.mv(:old, :new)` | Rename within depot |
| `Depot.mv(:name, path)` | Move (export) named store to filesystem path |
| `Depot.mv(path, :name)` | Move (import) filesystem directory into depot |
| `Depot.cp(:old, :new)` | Copy within depot |
| `Depot.cp(:name, path)` | Copy (export) named store to filesystem path |
| `Depot.cp(path, :name)` | Copy (import) filesystem directory into depot |

### Depot API reference

```@autodocs
Modules = [DataCaches.Depot]
```
