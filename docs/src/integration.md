```@meta
CurrentModule = DataCaches
```

# Library Integration Guide

DataCaches.jl is designed to be embedded in other packages, not just used interactively.
This guide walks through the three standard integration patterns, from the simplest
(private internal cache) to the most seamless (fully transparent autocaching with a
package-owned default store).

The patterns are **independently composable**: a package can use any combination of A,
B, and C, or just one. Each pattern is a self-contained module example that compiles
and runs.

---

## Pattern A — Package-private data store

**When to use:** Your package needs to cache data internally for its own operation —
precomputed indices, downloaded reference snapshots, expensive one-time computations.
Users never interact with the cache directly; from their perspective the data is simply
"already there".

**Mechanism:** `scratch_datacache!` creates a `DataCache` namespaced by your package's
UUID, stored in the DataCaches depot. It is isolated from every other package's data
and is removed if DataCaches.jl is ever uninstalled and `Pkg.gc()` is run.

```julia
module TaxonomyDB
using DataCaches
using DataFrames

# Copy your UUID from Project.toml
const _PKG_UUID = Base.UUID("11111111-2222-3333-4444-555555555555")

# Lazily-initialised cache ref — populated in __init__
const _cache_ref = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    # One scratch_datacache! per logical dataset; use distinct keys for multiple stores.
    _cache_ref[] = DataCaches.scratch_datacache!(_PKG_UUID, :taxonomy)
end

# Expose the cache for power users who want to inspect or manage it
cache() = _cache_ref[]

# --- Public API ---

"""
    TaxonomyDB.get_taxa(group) -> DataFrame

Return the taxon list for `group`, downloading and caching it on first access.
Subsequent calls within the same or future sessions are instant.
"""
function get_taxa(group::String)
    dc = _cache_ref[]
    haskey(dc, group) && return dc[group]
    result = _download_taxa(group)
    dc[group] = result
    return result
end

"""
    TaxonomyDB.refresh!(group)

Force a fresh download of `group`, overwriting the cached copy.
"""
function refresh!(group::String)
    dc = _cache_ref[]
    result = _download_taxa(group)
    dc[group] = result
    return result
end

# --- Internal ---

function _download_taxa(group::String)
    # ... expensive HTTP request, parsing, etc. ...
    return DataFrame(name = ["$(group)_sp1", "$(group)_sp2"], rank = ["species", "species"])
end

end # module
```

**User-facing experience — the cache is invisible:**

```julia
using TaxonomyDB

# First call: downloads and caches transparently
df = TaxonomyDB.get_taxa("Canidae")

# Subsequent calls (same session or future sessions): instant
df = TaxonomyDB.get_taxa("Canidae")

# Power users can inspect or manage the store if they want to
showcache(TaxonomyDB.cache())
clear!(TaxonomyDB.cache())
```

---

## Pattern B — Instrumented functions, user controls cache

**When to use:** You want users to be able to call `set_autocaching!(true)` and have
your functions benefit automatically, but you are happy for caching to go to wherever
the user points — the DataCaches shared default or a cache they explicitly choose.
Your package does not own any cache storage.

**Mechanism:** Wrap each public function with [`autocache`](@ref). When autocaching is
off, `autocache` calls the real function directly with zero overhead. When on, it checks
the user-configured store and returns cached results or fetches and stores fresh ones.

```julia
module WeatherAPI
using DataCaches
using DataFrames
import DataCaches: autocache

# --- Public API ---

"""
    WeatherAPI.forecast(city; days=7) -> DataFrame

Fetch a weather forecast for `city` over the next `days` days.
Supports DataCaches autocaching — call `set_autocaching!(true)` before use.
"""
function forecast(city::String; days::Int = 7)
    return autocache(
        () -> _fetch_forecast(city; days = days),   # the real work, as a zero-arg closure
        forecast,                                    # this function (used for autocache allowlist)
        "weather/forecast",                          # stable endpoint string (part of cache key)
        (; city = city, days = days),                # kwargs (part of cache key)
    )
end

"""
    WeatherAPI.current(city) -> DataFrame
"""
function current(city::String)
    return autocache(
        () -> _fetch_current(city),
        current,
        "weather/current",
        (; city = city),
    )
end

# --- Internal ---

function _fetch_forecast(city; days)
    # ... real HTTP request ...
    return DataFrame(day = 1:days, city = fill(city, days), temp_c = rand(days) .* 20 .+ 10)
end

function _fetch_current(city)
    return DataFrame(city = [city], temp_c = [rand() * 20 + 10])
end

end # module
```

**User-facing experience:**

```julia
using WeatherAPI, DataCaches

# --- No caching (default) ---
df = WeatherAPI.forecast("London"; days = 5)   # always live

# --- Enable autocaching: use DataCaches shared default ---
set_autocaching!(true)
df = WeatherAPI.forecast("London"; days = 5)   # fetches + stores
df = WeatherAPI.forecast("London"; days = 5)   # instant, from cache
set_autocaching!(false)

# --- Use a specific store for this project ---
my_cache = DataCache(:weather_project)
set_autocaching!(true; cache = my_cache)
df = WeatherAPI.forecast("Paris"; days = 3)    # fetches + stores in my_cache
set_autocaching!(false)

# --- Cache only specific functions ---
set_autocaching!(true, WeatherAPI.forecast)    # only forecast; current is always live
df  = WeatherAPI.forecast("Tokyo")             # cached
cur = WeatherAPI.current("Tokyo")              # not cached
set_autocaching!(false)

# --- Force refresh ---
set_autocaching!(true)
df = WeatherAPI.forecast("London"; days = 5; force_refresh = true)  # re-fetches even if cached
set_autocaching!(false)
```

---

## Pattern C — Instrumented functions with package-owned default cache

**When to use:** You want the benefits of Pattern B (user-visible `set_autocaching!`
control) **plus** namespace isolation: when the user enables autocaching without
specifying a store, results should go to your package's own scratch store — not the
shared DataCaches default. The user can still override at any time by passing an
explicit `cache` to `set_autocaching!`.

**Mechanism:** Create a `scratch_datacache!` in `__init__` and pass it as
`package_cache` to every `autocache` call. The store-resolution priority is:

1. User-explicit: `set_autocaching!(true; cache=x)` → always uses `x`
2. `package_cache` → used when no explicit user cache was set
3. [`default_filecache()`](@ref) → final fallback

```julia
module BioSearch
using DataCaches
using DataFrames
import DataCaches: autocache

# Copy your UUID from Project.toml
const _PKG_UUID = Base.UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

const _pkg_cache_ref = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    _pkg_cache_ref[] = DataCaches.scratch_datacache!(_PKG_UUID, :biosearch)
end

"""
    BioSearch.pkg_cache() -> DataCache

Return BioSearch's own package-scoped cache.
Used as the default store for autocaching unless the user supplies an explicit one.
"""
pkg_cache() = _pkg_cache_ref[]

# --- Public API ---

"""
    BioSearch.search_species(; kwargs...) -> DataFrame

Search the biodiversity database. Supports DataCaches autocaching.
When autocaching is enabled without an explicit cache, results are stored in
BioSearch's own package-scoped store (see [`BioSearch.pkg_cache`](@ref)).
"""
function search_species(; kwargs...)
    return autocache(
        () -> _do_search_species(; kwargs...),
        search_species,
        "species/search",
        kwargs;
        package_cache = _pkg_cache_ref[],   # ← the key addition vs Pattern B
    )
end

"""
    BioSearch.occurrences(taxon; kwargs...) -> DataFrame
"""
function occurrences(taxon::String; kwargs...)
    return autocache(
        () -> _do_occurrences(taxon; kwargs...),
        occurrences,
        "occurrences/list",
        merge((; taxon = taxon), kwargs);
        package_cache = _pkg_cache_ref[],
    )
end

# --- Internal ---

function _do_search_species(; kwargs...)
    # ... real HTTP request ...
    return DataFrame(name = ["Species A", "Species B"], rank = ["species", "species"])
end

function _do_occurrences(taxon; kwargs...)
    return DataFrame(taxon = fill(taxon, 3), lat = rand(3), lon = rand(3))
end

end # module
```

**User-facing experience:**

```julia
using BioSearch, DataCaches

# --- No caching (default) ---
df = BioSearch.search_species(taxon = "Canidae")   # always live

# --- Enable autocaching without explicit cache ---
# Results go to BioSearch's own package-scoped store automatically
set_autocaching!(true)
df = BioSearch.search_species(taxon = "Canidae")   # fetches + stores in BioSearch's cache
df = BioSearch.search_species(taxon = "Canidae")   # instant, from BioSearch's cache
set_autocaching!(false)

# --- User explicitly overrides: their cache wins ---
my_cache = DataCache(:my_project)
set_autocaching!(true; cache = my_cache)
df = BioSearch.search_species(taxon = "Felidae")   # stored in my_cache, not BioSearch's
set_autocaching!(false)

# --- Inspect BioSearch's own cache ---
showcache(BioSearch.pkg_cache())
# DataCache: ~/.julia/scratchspaces/<DataCaches-UUID>/caches/module/aaaa.../biosearch (2 entries)
#   [1]  2026-04-03T10:12:00  3f2a1b9c  search_species(species/search; taxon = "Canidae")
#   [2]  2026-04-03T10:12:05  8d4e7a2f  search_species(species/search; taxon = "Felidae")

# --- Clear only BioSearch's cache (does not affect user caches) ---
clear!(BioSearch.pkg_cache())
```

---

## Storage formats and library dependencies

### Automatic format selection

The storage format for each cache entry is chosen automatically from the data
type at write time. No configuration is needed for the common cases:

| Data type | Format | File | Version-stable? |
|-----------|--------|------|----------------|
| `DataFrame`, Tables.jl-compatible | CSV | `.csv` | Yes |
| `NamedTuple` | JSON | `.json` | Yes (JSON-primitive values) |
| Images (`Matrix{<:Colorant}`, requires FileIO) | PNG/JPG/TIF | `.png` etc. | Yes |
| Anything else | Julia serialization | `.jls` | No |

The format tag is persisted to the cache index so reads always use the correct
deserializer, independent of Julia version.

To override the automatic selection for a specific entry, pass `format=` to `write!`:

```julia
write!(cache, img; label = "my_plot", format = "png")   # explicit PNG
write!(cache, df;  label = "backup",  format = "jls")   # force opaque serialization
```

### NamedTuple JSON contract

`NamedTuple` values are stored as JSON. The roundtrip is clean for JSON-primitive
types (Int, Float64, String, Bool, arrays of same, nested NamedTuples). Note that
`Float32` and `Float16` values widen to `Float64` on read — this is a documented
property of the JSON format, not a bug.

### Image-returning functions and FileIO

If your instrumented functions return image data (e.g. `Matrix{RGB{N0f8}}`),
transparent PNG/JPG/TIF storage requires both **FileIO** and **ColorTypes** (or a
package that brings them in, such as **Images**) to be loaded in the session.

**For library authors:** if your package loads or produces images, list **FileIO**
as a dependency in your `Project.toml`. Any user of your package will then have
FileIO loaded transitively, and DataCaches will store image results as `.png`
automatically — no extra steps needed by the user.

```toml
# YourPackage/Project.toml
[deps]
DataCaches = "c1455f2b-6d6f-4f37-b463-919f923708a5"
FileIO     = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
ColorTypes = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"   # or Images, which brings both
```

If FileIO is not a dependency of your package and the user has not loaded it
themselves, DataCaches will raise a clear error at write time if it attempts to
store an image entry, explaining what needs to be added.

If you need JPG or TIF instead of the PNG default, pass `format=` explicitly:

```julia
write!(cache, img; label = "photo", format = "jpg")
```

---

## Comparison

| | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| Package owns a scratch store | Yes | No | Yes |
| Functions support `set_autocaching!` | No | Yes | Yes |
| Default store when user omits `cache=` | N/A | `default_filecache()` | Package's own store |
| User can override to a different store | N/A | Yes | Yes |
| Results isolated from other packages | Yes | No | Yes |
| Cache removed with package on `Pkg.gc()` | Yes | N/A | Yes |
| User-visible cache accessor needed | Optional | No | Recommended |

Patterns A and C are naturally combined: a package can have both a private internal
cache (Pattern A) for reference data that users should never touch, and autocache-
instrumented public functions (Pattern C) whose default store users can inspect and
manage via the exposed accessor.

---

## Integration API reference

```@docs
autocache
set_autocaching!
scratch_datacache!
```
