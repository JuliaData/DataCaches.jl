```@meta
CurrentModule = DataCaches
```

# Caches — store management

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

## Inspection

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

## Renaming and copying within the scratchspace

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

## Moving and copying between scratchspace and filesystem

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

## Quick-reference table

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

## API reference

```@autodocs
Modules = [DataCaches.Caches]
```
