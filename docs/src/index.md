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

DataCaches selects a transparent, inspectable storage format automatically based
on the data type, falling back to Julia's binary serialization for types without
a dedicated format:

| Data type | Format | File | Version-stable? |
|-----------|--------|------|----------------|
| `DataFrame`, Tables.jl-compatible | CSV | `.csv` | Yes |
| `NamedTuple` | JSON | `.json` | Yes (JSON-primitive values) |
| Images (`Matrix{<:Colorant}`, requires FileIO) | PNG/JPG/TIF | `.png` etc. | Yes |
| Anything else | Julia serialization | `.jls` | No |

The format used is recorded per entry in the cache index so the correct
deserializer is always selected on read. Custom serializers can be registered
for additional types via [`register_serializer!`](@ref).

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
      _DEFAULT/             ← DataCache() / DataCache(:_DEFAULT) default store
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
# → ".../c1455f2b-.../caches/user/_DEFAULT"

# Listing of the caches directory root (default)
DataCaches.Caches.ls()
# → [:user, :module]

# List user stores (DataCache(:name))
DataCaches.Caches.ls(:user)
# → [:_DEFAULT, :myproject, :taxonomy, :archived_results]

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
| `Caches.defaultstore()` | Path to the default store (`caches/user/_DEFAULT`) |
| `Caches.ls()` | Returns `Vector{Symbol}` — caches root listing (same as `ls(:root)`) |
| `Caches.ls(:root)` | Returns `Vector{Symbol}` — top-level caches subdirs (e.g. `[:user, :module]`) |
| `Caches.ls(:user)` | Returns `Vector{Symbol}` — names of `DataCache(:name)` stores |
| `Caches.ls(:module)` | Returns `Vector{Symbol}` — `"<uuid>/<key>"` entries for `scratch_datacache!` stores |
| `Caches.ls!(storetype; io)` | Prints the result of `ls(storetype)` to `io` (default `stdout`), returns `nothing` |
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

---

## CacheAssets — asset management within a cache

`DataCaches.CacheAssets` is a submodule (public, not exported) that provides a
filesystem-style interface for managing individual *assets* (entries) within a
`DataCache`. Import it as `using DataCaches.CacheAssets` or access functions as
`DataCaches.CacheAssets.<function>`.

All four functions accept an optional leading `DataCache` argument. When omitted,
`default_filecache()` is used.

### List assets

`ls` returns a `Vector{CacheEntry}` for programmatic use; `ls!` prints a formatted
listing to an `IO` stream and returns `nothing`. Both accept the same filtering and
sorting keyword arguments.

!!! note
    [`entries`](@ref) (exported at the top level) provides the same data-retrieval
    functionality without importing `CacheAssets`. Use `CacheAssets.ls!` when you
    want formatted output.

```julia
using DataCaches.CacheAssets

# --- Data form: returns Vector{CacheEntry} ---

entries = CacheAssets.ls(dc)

# Filter by label/description pattern
entries = CacheAssets.ls(dc; pattern = r"canidae")
entries = CacheAssets.ls(dc; pattern = "dino")          # string is converted to Regex

# Filter by write or access date
entries = CacheAssets.ls(dc; after  = DateTime("2026-01-01T00:00:00"))
entries = CacheAssets.ls(dc; before = DateTime("2026-06-01T00:00:00"))
entries = CacheAssets.ls(dc; accessed_after = DateTime("2026-03-01T00:00:00"))

# Filter by whether the entry has a label
entries = CacheAssets.ls(dc; labeled = true)   # only labeled entries
entries = CacheAssets.ls(dc; labeled = false)  # only unlabeled entries

# Sort
entries = CacheAssets.ls(dc; sortby = :date_desc)          # newest first
entries = CacheAssets.ls(dc; sortby = :dateaccessed_desc)  # least recently used last
entries = CacheAssets.ls(dc; sortby = :size_desc)          # largest first (requires stat)
entries = CacheAssets.ls(dc; sortby = :label)

# Use default cache (default_filecache())
entries = CacheAssets.ls()
entries = CacheAssets.ls(; sortby = :date_desc)

# --- Display form: prints to io, returns nothing ---

# Default: normal detail level, sorted by sequence index
CacheAssets.ls!(dc)

# Terse — just labels
CacheAssets.ls!(dc; detail = :minimal)

# Full — includes last-access time, file size, and data format
CacheAssets.ls!(dc; detail = :full)

# All ls filter/sort kwargs are also accepted by ls!
CacheAssets.ls!(dc; pattern = r"canidae", sortby = :date_desc)

# Redirect output
CacheAssets.ls!(dc; io = my_io)

# Use default cache
CacheAssets.ls!()
CacheAssets.ls!(; detail = :full, sortby = :date_desc)
```

### Remove assets

```julia
# Remove by label, sequence index, UUID prefix, or CacheEntry — in any combination
CacheAssets.rm(dc, "canidae_occs")
CacheAssets.rm(dc, 3)
CacheAssets.rm(dc, "canidae_occs", "dinosaur_taxa", 5)

# Suppress errors for missing specifiers
CacheAssets.rm(dc, "maybe_exists"; force = true)

# Default cache
CacheAssets.rm("old_entry")
```

### Relabel and move assets

```julia
# Relabel within the same cache (dest is a String)
CacheAssets.mv(dc, "old_label", "new_label")
CacheAssets.mv(dc, 2, "new_label")             # by sequence index

# Relabel with conflict resolution
CacheAssets.mv(dc, "old", "taken_label"; force = true)  # replaces the conflicting entry

# Move to another cache (dest is a DataCache)
dc2 = DataCache(:archive)
CacheAssets.mv(dc, "canidae_occs", dc2)
CacheAssets.mv(dc, "canidae_occs", dc2; label = "renamed_in_dest")
CacheAssets.mv(dc, "canidae_occs", dc2; force = true)   # overwrite if label exists in dc2

# Default-cache forms
CacheAssets.mv("old_label", "new_label")
CacheAssets.mv("entry", dc2)
```

### Copy assets to another cache

```julia
# Single asset
CacheAssets.cp(dc, "canidae_occs", dc2)
CacheAssets.cp(dc, "canidae_occs", dc2; label = "canidae_copy")

# Multiple assets (vector of specifiers)
CacheAssets.cp(dc, ["canidae_occs", "dinosaur_taxa", 5], dc2)
CacheAssets.cp(dc, ["canidae_occs", "dinosaur_taxa"], dc2; force = true)

# Default-cache form
CacheAssets.cp("canidae_occs", dc2)
CacheAssets.cp(["entry1", "entry2"], dc2)
```

Each copy receives a new UUID, sequence number, and `datecached` timestamp in
the destination. Copying within the same cache is allowed and produces a distinct
new entry.

### Access-time tracking and LRU support

Every `DataCache` records when each asset was last read via the `dateaccessed`
field on each [`CacheEntry`](@ref). This is enabled by default; disable it for caches
that are read at very high frequency or have many entries, since every read
triggers a full index rewrite:

```julia
dc = DataCache(:large_cache; track_access = false)
```

`CacheAssets.ls(dc; detail = :full)` shows both `datecached` and `dateaccessed`
for each entry. Sort by `:dateaccessed` or `:dateaccessed_desc` to find
least-recently-used assets.

### Quick-reference table

| Function | Description |
|---|---|
| `CacheAssets.ls([dc]; detail, pattern, before, after, accessed_before, accessed_after, labeled, sortby, rev)` | List assets in a cache |
| `CacheAssets.rm([dc,] assets...; force)` | Remove assets (batched index rewrite) |
| `CacheAssets.mv([dc,] src, new_label; force)` | Relabel an asset within a cache |
| `CacheAssets.mv([src_dc,] src, dest_dc; label, force)` | Move asset to another cache |
| `CacheAssets.cp([src_dc,] src, dest_dc; label, force)` | Copy asset to another cache |
| `CacheAssets.cp([src_dc,] srcs::Vector, dest_dc; force)` | Copy multiple assets to another cache |

### CacheAssets API reference

```@autodocs
Modules = [DataCaches.CacheAssets]
```
