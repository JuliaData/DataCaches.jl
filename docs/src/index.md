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

## Further reading

- [API Reference](api.md) — full `DataCaches` function and type reference
- [Caches](caches.md) — filesystem-style management of cache stores in the scratchspace
- [Cache Assets](cache_assets.md) — inspect, copy, move, and remove individual cache entries
- [Library Integration](integration.md) — embedding DataCaches.jl in a package
