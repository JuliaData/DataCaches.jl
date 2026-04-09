module DataCaches

using CSV
using DataFrames
using Dates
using Downloads
import TOML
using Serialization
using UUIDs
using ZipFile

export DataCache, CacheEntry, CacheKey
export write!, relabel!, reindexcache!, keylabels, keypaths, clear!, showcache, label, path
export entries, entry, labels
export @filecache, @filecache!, @memcache
export default_filecache, set_default_filecache!, memcache_clear!
export set_autocaching!
export autocache
export scratch_datacache!

# =============================================================================
# CacheEntry
# =============================================================================

"""
    CacheEntry

A metadata descriptor for a single cached dataset in a [`DataCache`](@ref).

A `CacheEntry` is returned by [`write!`](@ref), [`entries`](@ref), [`entry`](@ref),
and related functions. Fields are accessed directly:

- `e.id            :: String`    — unique identifier (UUID)
- `e.seq           :: Int`       — stable integer index (persisted; use `reindexcache!` to compact gaps)
- `e.label         :: String`    — user-assigned label (hash string for `@filecache` entries; empty if none)
- `e.path          :: String`    — absolute path to the backing data file
- `e.description   :: String`    — human-readable source expression (empty if none was recorded)
- `e.datecached    :: DateTime`  — when the entry was written; `typemin(DateTime)` if unknown
- `e.dateaccessed  :: DateTime`  — when the entry was last read; `typemin(DateTime)` if never accessed

# Backward compatibility

`CacheKey` is a backward-compatible alias for `CacheEntry`. Existing code using
`CacheKey` continues to work without modification. The alias will gain a deprecation
warning in a future release.
"""
struct CacheEntry
    id::String
    seq::Int              # stable integer index, persisted to TOML
    label::String
    path::String
    description::String   # human-readable source expression, or ""
    datecached::DateTime  # timestamp of last write; typemin(DateTime) = unknown (legacy entry)
    dateaccessed::DateTime # timestamp of last read; typemin(DateTime) = never accessed
end

# Backward-compatible alias; will gain a deprecation warning in a future release.
const CacheKey = CacheEntry

function Base.show(io::IO, e::CacheEntry)
    disp = !isempty(e.description) ? e.description :
           !isempty(e.label)       ? e.label        : e.id[1:8]
    print(io, "CacheEntry($(repr(disp)))")
end

# Internal: format one CacheEntry line with a given seq column width for alignment.
function _print_cacheentry(io::IO, e::CacheEntry, seq_width::Int)
    lbl    = !isempty(e.description) ? e.description :
             !isempty(e.label)       ? e.label       : "(unlabeled)"
    dt_str = e.datecached == typemin(DateTime) ?
             " " ^ 19 :
             Dates.format(e.datecached, "yyyy-mm-ddTHH:MM:SS")
    status = isfile(e.path) ? "" : "  *** FILE MISSING ***"
    seq_str = lpad(e.seq, seq_width)
    # prefix: "  [" + seq_str + "]  " + dt_str + "  " + uuid8 + "  "
    #          3   + seq_width + 3  +   19    +  2  +   8   +  2  = seq_width + 37
    prefix_len = seq_width + 37
    println(io, "  [$(seq_str)]  $(dt_str)  $(e.id[1:8])  $lbl$status")
    print(io,   " " ^ prefix_len * e.path)
end

function Base.show(io::IO, ::MIME"text/plain", e::CacheEntry)
    _print_cacheentry(io, e, ndigits(e.seq))
end

# =============================================================================
# DataCache
# =============================================================================

"""
    DataCache([store::AbstractString]; track_access=true)
    DataCache(key::Symbol; track_access=true)

A labeled, file-backed key-value store for caching query results across
Julia sessions.

Data is persisted in `store` as CSV files (for `DataFrame` values) or
serialized Julia objects (`.jls`) for anything else. An index file
(`cache_index.toml`) in `store` keeps track of all entries.

**No argument:** the store is placed in the user silo of DataCaches' depot at
`~/.julia/scratchspaces/<DataCaches-UUID>/caches/user/_DEFAULT/`,
automatically cleaned up if DataCaches.jl is uninstalled and `Pkg.gc()` is run.
Set the `DATACACHES_DEFAULT_STORE` environment variable to override this location.
`DataCache()` is equivalent to `DataCache(:_DEFAULT)`.

**Symbol argument (`DataCache(:name)`):** creates a named user store within
DataCaches.jl's own depot directory (`~/.julia/scratchspaces/<DataCaches-UUID>/caches/user/<name>/`).
The cache is automatically removed along with DataCaches.jl when the package is uninstalled.
This is the recommended approach for users and library authors who want a persistent,
named cache without managing filesystem paths or package UUIDs:

```julia
# User: a named project cache in DataCaches' scratchspace
dc = DataCache(:myproject)

# Library author: lifecycle-managed cache in __init__
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)
function __init__()
    _CACHE[] = DataCache(:mypackage_results)
end
```

Use [`scratch_datacache!`](@ref) instead when you need the cache tied to *your own*
package's lifecycle rather than DataCaches.jl's.

**`track_access` keyword:** when `true` (the default), every `read` updates the
`dateaccessed` field of the corresponding [`CacheEntry`](@ref) and rewrites the
index. This supports LRU inspection via [`entries`](@ref) and [`DataCaches.CacheAssets.ls`](@ref).
Set `track_access = false` to skip this rewrite on caches that are read very
frequently or have many entries.

# Examples
```julia
cache = DataCache()                        # default store: caches/user/_DEFAULT/
cache = DataCache(:_DEFAULT)                # same as DataCache() — the default store
cache = DataCache(:myproject)              # named store: caches/user/myproject/
cache = DataCache("/my/project/cache")     # explicit filesystem path
cache = DataCache(:logs; track_access = false)  # disable access-time recording

# Write
key = write!(cache, df)
key = write!(cache, df; label="Dinosaur families")
cache["Trilobites"] = df          # setindex! sugar

# Read
df = read(cache, key)
df = read(cache, "Dinosaur families")
df = cache["Dinosaur families"]
df = cache[key]

# Introspect
entries(cache)    # → Vector{CacheEntry} (primary — filterable, sortable)
entry(cache, "Dinosaur families")  # → CacheEntry (single entry by label)
labels(cache)     # → Vector{String} (user-assigned labels only)
keys(cache)       # → Vector{CacheEntry} (backward-compat; prefer entries())
keylabels(cache)  # → Vector{String} (backward-compat; prefer labels())
keypaths(cache)   # → Vector{String}
label(cache, key) # → String
path(cache, key)  # → String
haskey(cache, "Dinosaur families")

# Manage
delete!(cache, key)
delete!(cache, "Dinosaur families")
clear!(cache)
showcache(cache)
```
"""
mutable struct DataCache
    store::String
    _index::Dict{String,CacheEntry}  # id → CacheEntry
    _by_label::Dict{String,String}   # label → id
    _next_seq::Int                   # monotonically incrementing seq counter
    track_access::Bool               # record dateaccessed on every read (opt-out with false)
end

const _INDEX_FILENAME = "cache_index.toml"
const _DATACACHES_UUID = Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5")

function _default_cache_dir()
    haskey(ENV, "DATACACHES_DEFAULT_STORE") && return ENV["DATACACHES_DEFAULT_STORE"]
    store = joinpath(Caches._user_dir(), "_DEFAULT")
    mkpath(store)
    return store
end

function DataCache(store::AbstractString = _default_cache_dir(); track_access::Bool = true)
    store = abspath(store)
    mkpath(store)
    cache = DataCache(store, Dict{String,CacheEntry}(), Dict{String,String}(), 1, track_access)
    _load_index!(cache)
    return cache
end

function DataCache(key::Symbol; track_access::Bool = true)
    store = joinpath(Caches._user_dir(), string(key))
    return DataCache(store; track_access)
end

"""
    scratch_datacache!(pkg_uuid::Base.UUID, key::Symbol = :datacache) → DataCache

Create a [`DataCache`](@ref) stored under DataCaches' own depot, namespaced by
`pkg_uuid` and `key`, at `<depot>/caches/module/<pkg_uuid>/<key>/`.

The store is managed as part of the DataCaches depot (cleaned up when DataCaches
is uninstalled), not the calling package's own lifecycle. Use different `key`
values to create multiple independent stores for the same package UUID.

Use this in a package's `__init__` to create a named, module-scoped cache:

```julia
module MyPackage
using DataCaches

const _MY_UUID = Base.UUID("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")  # match Project.toml
const _CACHE = Ref{Union{DataCache,Nothing}}(nothing)

function __init__()
    _CACHE[] = DataCaches.scratch_datacache!(_MY_UUID, :results)
end

get_cache() = _CACHE[]
end
```
"""
function scratch_datacache!(pkg_uuid::Base.UUID, key::Symbol = :datacache; track_access::Bool = true)
    store = joinpath(Caches._module_dir(), string(pkg_uuid), string(key))
    mkpath(store)
    return DataCache(store; track_access)
end

# --- Index I/O ---------------------------------------------------------------

_index_file(cache::DataCache) = joinpath(cache.store, _INDEX_FILENAME)

function _load_index!(cache::DataCache)
    p = _index_file(cache)
    isfile(p) || return
    data = TOML.parsefile(p)
    legacy = Tuple{String,String,String,String,DateTime,DateTime}[]  # (id, lbl, fpath, desc, dt, da) for seq==0
    max_seq = 0
    for (id, entry) in get(data, "entries", Dict())
        lbl    = get(entry, "label",       "")
        fpath  = get(entry, "path",        "")
        fpath  = isabspath(fpath) ? fpath : joinpath(cache.store, fpath)
        desc   = get(entry, "description", "")
        seq    = get(entry, "seq",         0)
        dt_raw = get(entry, "datecached",  "")
        dt = if dt_raw isa DateTime
                 dt_raw
             elseif dt_raw isa AbstractString && !isempty(dt_raw)
                 try
                     DateTime(dt_raw, dateformat"yyyy-mm-ddTHH:MM:SS")
                 catch
                     typemin(DateTime)
                 end
             else
                 typemin(DateTime)
             end
        isfile(fpath) || continue
        da_raw = get(entry, "dateaccessed", "")
        da = if da_raw isa DateTime
                 da_raw
             elseif da_raw isa AbstractString && !isempty(da_raw)
                 try
                     DateTime(da_raw, dateformat"yyyy-mm-ddTHH:MM:SS")
                 catch
                     typemin(DateTime)
                 end
             else
                 typemin(DateTime)
             end
        if seq == 0
            push!(legacy, (id, lbl, fpath, desc, dt, da))
        else
            max_seq = max(max_seq, seq)
            key = CacheEntry(id, seq, lbl, fpath, desc, dt, da)
            cache._index[id] = key
            isempty(lbl) || (cache._by_label[lbl] = id)
        end
    end
    # Assign seq to legacy entries (no seq in TOML), ordered by datecached
    sort!(legacy; by = t -> t[5])  # sort by dt
    for (id, lbl, fpath, desc, dt, da) in legacy
        max_seq += 1
        key = CacheEntry(id, max_seq, lbl, fpath, desc, dt, da)
        cache._index[id] = key
        isempty(lbl) || (cache._by_label[lbl] = id)
    end
    cache._next_seq = max_seq + 1
end

function _save_index(cache::DataCache)
    entries = Dict{String,Any}()
    for (id, key) in cache._index
        entries[id] = Dict{String,Any}(
            "seq"          => key.seq,
            "label"        => key.label,
            "path"         => relpath(key.path, cache.store),
            "description"  => key.description,
            "datecached"   => key.datecached == typemin(DateTime) ? "" :
                              Dates.format(key.datecached, "yyyy-mm-ddTHH:MM:SS"),
            "dateaccessed" => key.dateaccessed == typemin(DateTime) ? "" :
                              Dates.format(key.dateaccessed, "yyyy-mm-ddTHH:MM:SS"),
        )
    end
    open(_index_file(cache), "w") do io
        TOML.print(io, Dict{String,Any}("entries" => entries))
    end
end

# --- Storage helpers ---------------------------------------------------------

function _data_path(cache::DataCache, id::String, data)
    ext = data isa AbstractDataFrame ? ".csv" : ".jls"
    return joinpath(cache.store, id * ext)
end

function _write_file(fpath::String, data)
    if data isa AbstractDataFrame
        CSV.write(fpath, data)
    else
        open(fpath, "w") do io
            serialize(io, data)
        end
    end
end

function _read_file(key::CacheEntry)
    if endswith(key.path, ".csv")
        return DataFrame(CSV.File(key.path; normalizenames = true))
    else
        return open(deserialize, key.path)
    end
end

# --- Internal removal --------------------------------------------------------

function _remove_entry!(cache::DataCache, id::String)
    key = get(cache._index, id, nothing)
    isnothing(key) && return
    isfile(key.path) && rm(key.path; force = true)
    delete!(cache._index, id)
    isempty(key.label) || delete!(cache._by_label, key.label)
end

# --- Public write/read -------------------------------------------------------

"""
    write!(cache::DataCache, data; label::AbstractString = "", description::AbstractString = "") → CacheEntry

Store `data` in `cache` and return a [`CacheEntry`](@ref) describing the stored item.

If `label` is given and another entry with that label already exists,
it is silently replaced. `DataFrame` values are stored as CSV; all other
values use Julia `Serialization`. `description` is an optional human-readable
string (e.g. the source expression) stored alongside the entry for display.

The returned [`CacheEntry`](@ref) can be passed directly to [`read`](@ref),
[`delete!`](@ref), [`relabel!`](@ref), and related functions, or retrieved
later by label using [`entry`](@ref).
"""
function write!(cache::DataCache, data; label::AbstractString = "", description::AbstractString = "")
    id    = string(uuid4())
    seq   = cache._next_seq
    cache._next_seq += 1
    fpath = _data_path(cache, id, data)
    _write_file(fpath, data)
    if !isempty(label)
        old = get(cache._by_label, label, nothing)
        isnothing(old) || _remove_entry!(cache, old)
        cache._by_label[label] = id
    end
    key = CacheEntry(id, seq, label, fpath, description, Dates.now(), typemin(DateTime))
    cache._index[id] = key
    _save_index(cache)
    return key
end

"""
    read(cache::DataCache, entry::CacheEntry) → data
    read(cache::DataCache, label::AbstractString) → data
    read(cache::DataCache, n::Integer) → data

Retrieve a cached dataset by [`CacheEntry`](@ref), label string, or stable sequence
index. The `Integer` form uses the sequence index shown in brackets by `showcache`
(e.g. `[1]`, `[2]`). Use `reindexcache!` to compact gaps after many deletions.
"""
function Base.read(cache::DataCache, key::CacheEntry)
    isfile(key.path) || error("Cache file missing: $(key.path)")
    data = _read_file(key)
    if cache.track_access
        new_key = CacheEntry(key.id, key.seq, key.label, key.path, key.description,
                           key.datecached, Dates.now())
        cache._index[key.id] = new_key
        _save_index(cache)
    end
    return data
end

function Base.read(cache::DataCache, lbl::AbstractString)
    id = get(cache._by_label, lbl, nothing)
    isnothing(id) && error("No cache entry with label $(repr(lbl))")
    return Base.read(cache, cache._index[id])
end

function Base.read(cache::DataCache, n::Integer)
    key = _resolve_by_seq(cache, Int(n))
    isnothing(key) && error("No cache entry with sequence index $n")
    return Base.read(cache, key)
end

Base.getindex(cache::DataCache, lbl::AbstractString) = Base.read(cache, lbl)
Base.getindex(cache::DataCache, key::CacheEntry)        = Base.read(cache, key)
Base.getindex(cache::DataCache, n::Integer)           = Base.read(cache, n)
Base.setindex!(cache::DataCache, data, lbl::AbstractString) = write!(cache, data; label = lbl)

# --- Introspection -----------------------------------------------------------

Base.haskey(cache::DataCache, lbl::AbstractString) = haskey(cache._by_label, lbl)
Base.haskey(cache::DataCache, key::CacheEntry)        = haskey(cache._index, key.id)
Base.length(cache::DataCache)  = length(cache._index)
Base.isempty(cache::DataCache) = isempty(cache._index)

"""
    keys(cache::DataCache) → Vector{CacheEntry}

Return all [`CacheEntry`](@ref) objects stored in `cache`.

!!! note
    Prefer [`entries`](@ref) for new code — it supports filtering and sorting.
    `keys` is maintained for backward compatibility.
"""
Base.keys(cache::DataCache) = collect(values(cache._index))

"""
    keylabels(cache::DataCache) → Vector{String}

Return all labels of entries in `cache` (empty string for unlabeled entries).

!!! note
    Prefer [`labels`](@ref) for new code — it returns only user-assigned labels
    (no empty strings). `keylabels` is maintained for backward compatibility.
"""
keylabels(cache::DataCache) = [k.label for k in values(cache._index)]

"""
    keypaths(cache::DataCache) → Vector{String}

Return the file paths of all entries in `cache`.
"""
keypaths(cache::DataCache) = [k.path for k in values(cache._index)]

"""
    label(cache::DataCache, entry::CacheEntry) → String

Return the label associated with `entry` (same as `entry.label`).
"""
label(::DataCache, entry::CacheEntry) = entry.label

"""
    path(cache::DataCache, entry::CacheEntry) → String

Return the file path of the data file backing `entry` (same as `entry.path`).
"""
path(::DataCache, entry::CacheEntry) = entry.path

# --- Management --------------------------------------------------------------

"""
    delete!(cache::DataCache, entry::CacheEntry)
    delete!(cache::DataCache, label::AbstractString)
    delete!(cache::DataCache, uuid_prefix::AbstractString)
    delete!(cache::DataCache, n::Integer)

Remove an entry from `cache` and delete its backing file from disk.

The `AbstractString` form first tries to match a label exactly, then falls back
to matching the UUID prefix shown in brackets by `showcache` (e.g. `"2a9d4a87"`).
An ambiguous prefix (matching more than one entry) is an error.

The `Integer` form identifies the entry by its stable sequence index (as shown
in `showcache`). Use `reindexcache!` to compact gaps after many deletions.
"""
function Base.delete!(cache::DataCache, key::CacheEntry)
    _remove_entry!(cache, key.id)
    _save_index(cache)
    return cache
end

function Base.delete!(cache::DataCache, lbl::AbstractString)
    id = get(cache._by_label, lbl, nothing)
    if isnothing(id)
        matches = [k for k in Base.keys(cache._index) if startswith(k, lbl)]
        if length(matches) == 1
            id = only(matches)
        elseif length(matches) > 1
            error("Ambiguous UUID prefix $(repr(lbl)) matches $(length(matches)) entries")
        else
            return cache
        end
    end
    _remove_entry!(cache, id)
    _save_index(cache)
    return cache
end

function Base.delete!(cache::DataCache, n::Integer)
    key = _resolve_by_seq(cache, Int(n))
    isnothing(key) && return cache
    _remove_entry!(cache, key.id)
    _save_index(cache)
    return cache
end

# --- Internal seq/relabel helpers --------------------------------------------

function _resolve_by_seq(cache::DataCache, n::Int)
    for key in values(cache._index)
        key.seq == n && return key
    end
    return nothing
end

function _relabel_by_id!(cache::DataCache, id::String, new_label::AbstractString)
    current = get(cache._index, id, nothing)
    isnothing(current) && error("No cache entry with id $(repr(id))")
    existing_id = get(cache._by_label, new_label, nothing)
    if !isnothing(existing_id) && existing_id != id
        error("Label $(repr(new_label)) is already used by another cache entry")
    end
    isempty(current.label) || delete!(cache._by_label, current.label)
    new_key = CacheEntry(id, current.seq, new_label, current.path, current.description,
                       current.datecached, current.dateaccessed)
    cache._index[id] = new_key
    isempty(new_label) || (cache._by_label[new_label] = id)
    _save_index(cache)
    return new_key
end

"""
    relabel!(cache::DataCache, entry::CacheEntry, new_label::AbstractString) → CacheEntry
    relabel!(cache::DataCache, old_label::AbstractString, new_label::AbstractString) → CacheEntry
    relabel!(cache::DataCache, n::Integer, new_label::AbstractString) → CacheEntry

Rename the label of an existing cache entry without touching its backing data file.

The `CacheEntry` overload identifies the entry by its UUID. The `AbstractString`
overload first tries to match `old_label` as an exact label, then falls back to
UUID-prefix matching (same rules as `delete!`). The `Integer` overload identifies
the entry by its stable sequence index (as shown in `showcache`).

Raises an error if `new_label` is already in use by a different entry.
Returns the updated [`CacheEntry`](@ref).
"""
function relabel!(cache::DataCache, key::CacheEntry, new_label::AbstractString)
    haskey(cache._index, key.id) || error("CacheEntry not found in cache")
    return _relabel_by_id!(cache, key.id, new_label)
end

function relabel!(cache::DataCache, old_label::AbstractString, new_label::AbstractString)
    id = get(cache._by_label, old_label, nothing)
    if isnothing(id)
        matches = [k for k in Base.keys(cache._index) if startswith(k, old_label)]
        if length(matches) == 1
            id = only(matches)
        elseif length(matches) > 1
            error("Ambiguous UUID prefix $(repr(old_label)) matches $(length(matches)) entries")
        else
            error("No cache entry with label $(repr(old_label))")
        end
    end
    return _relabel_by_id!(cache, id, new_label)
end

function relabel!(cache::DataCache, n::Integer, new_label::AbstractString)
    key = _resolve_by_seq(cache, Int(n))
    isnothing(key) && error("No cache entry with index $n")
    return _relabel_by_id!(cache, key.id, new_label)
end

"""
    clear!(cache::DataCache)

Remove **all** entries from `cache` and delete their backing files from disk.
"""
function clear!(cache::DataCache)
    for id in collect(Base.keys(cache._index))
        _remove_entry!(cache, id)
    end
    _save_index(cache)
    return cache
end

"""
    reindexcache!(cache::DataCache)

Renumber all entries 1..n (sorted by current sequence order), closing gaps
left by deletions. After `reindexcache!`, integer indices in `showcache` output
restart from 1 with no gaps.

Use this after many write/delete cycles to keep index numbers manageable.
"""
function reindexcache!(cache::DataCache)
    sorted = sort(collect(values(cache._index)); by = k -> k.seq)
    for (new_seq, key) in enumerate(sorted)
        new_key = CacheEntry(key.id, new_seq, key.label, key.path, key.description,
                           key.datecached, key.dateaccessed)
        cache._index[key.id] = new_key
    end
    cache._next_seq = length(sorted) + 1
    _save_index(cache)
    return cache
end

# =============================================================================
# Cache management — move and import
# =============================================================================

public movecache!
public importcache!
public Caches
public CacheAssets

"""
    DataCaches.movecache!(cache::DataCache, new_path::AbstractString) → DataCache

Move the cache's underlying store directory to `new_path`, updating `cache.store`.

Because `cache_index.toml` stores paths as relative paths, the TOML file does not need
rewriting. In-memory `CacheEntry.path` fields (which are absolute) are updated in place.

  - If `new_path` does not exist, it is created (including any missing parent directories).
  - If `new_path == abspath(cache.store)`, returns `cache` unchanged (no-op).
  - If `new_path` already exists (and differs), throws an error.

The move is performed with `Base.mv`, which copies then deletes across filesystem boundaries.
"""
function movecache!(cache::DataCache, new_path::AbstractString)
    src = cache.store
    dst = abspath(new_path)
    src == dst && return cache

    isdir(dst) && error(
        "Destination already exists: $(repr(dst)). Remove it first or choose a different path."
    )

    mkpath(dirname(dst))
    mv(src, dst)
    cache.store = dst

    # Update in-memory absolute paths; TOML uses relative paths and moved with the dir.
    for (id, key) in cache._index
        new_abs = joinpath(dst, relpath(key.path, src))
        cache._index[id] = CacheEntry(key.id, key.seq, key.label, new_abs,
                                    key.description, key.datecached, key.dateaccessed)
    end
    return cache
end

"""
    DataCaches.importcache!(dest::DataCache, source; conflict=:overwrite) → DataCache

Import all entries from an external cache `source` into `dest`.

`source` can be:

  - A **filesystem directory** containing a DataCache store (`cache_index.toml` at its root).
  - A **`.zip` file** containing a DataCache store at its root.
  - An **HTTP/HTTPS URL** pointing to a `.zip` file; downloaded to a temp location first.

The `conflict` keyword controls behavior when an entry in `source` has the same label as
an existing entry in `dest`:

  - `:overwrite` (default) — replace the existing entry with the imported one.
  - `:skip` — keep the existing entry, discard the incoming one.
  - `:error` — raise an `ErrorException` immediately on conflict.

Unlabeled entries are always imported regardless of `conflict`. Imported entries receive
a new UUID, sequence number, and `datecached` timestamp in `dest`. Returns `dest`.
"""
function importcache!(dest::DataCache, source::AbstractString;
                      conflict::Symbol = :overwrite)
    conflict in (:overwrite, :skip, :error) || error(
        "conflict must be :overwrite, :skip, or :error; got $(repr(conflict))"
    )
    resolved = _resolve_import_source(source)
    try
        _do_import!(dest, resolved.path; conflict=conflict)
    finally
        resolved.is_temp && rm(resolved.path; recursive=true, force=true)
    end
    return dest
end

function _resolve_import_source(source::AbstractString)
    if startswith(source, "http://") || startswith(source, "https://")
        endswith(lowercase(source), ".zip") || error(
            "URL imports must point to a .zip file; got: $(repr(source))"
        )
        tmp = mktempdir()
        zip_path = joinpath(tmp, "download.zip")
        Downloads.download(source, zip_path)
        extract_dir = mktempdir()
        rm(tmp; recursive=true)
        _extract_zip(zip_path, extract_dir)
        return (path=extract_dir, is_temp=true)
    elseif endswith(lowercase(source), ".zip")
        isfile(source) || error("Zip file not found: $(repr(source))")
        extract_dir = mktempdir()
        _extract_zip(source, extract_dir)
        return (path=extract_dir, is_temp=true)
    else
        isdir(source) || error("Import source directory not found: $(repr(source))")
        return (path=source, is_temp=false)
    end
end

function _extract_zip(zip_path::AbstractString, dest_dir::AbstractString)
    mkpath(dest_dir)
    zf = ZipFile.Reader(zip_path)
    try
        for f in zf.files
            outpath = joinpath(dest_dir, f.name)
            if endswith(f.name, "/")
                mkpath(outpath)
            else
                mkpath(dirname(outpath))
                write(outpath, read(f))
            end
        end
    finally
        close(zf)
    end
end

function _do_import!(dest::DataCache, src_dir::AbstractString; conflict::Symbol)
    src = DataCache(src_dir)
    for (_, src_key) in src._index
        lbl = src_key.label
        if !isempty(lbl) && haskey(dest._by_label, lbl)
            if conflict == :error
                error("Label conflict during import: $(repr(lbl)) already exists in destination")
            elseif conflict == :skip
                continue
            end
            # :overwrite — write! will replace the existing entry
        end
        data = _read_file(src_key)
        write!(dest, data; label=lbl, description=src_key.description)
    end
end

"""
    showcache(cache::DataCache)

Print a detailed summary of all entries in `cache`.
Equivalent to `show(stdout, MIME"text/plain"(), cache)`.
"""
function showcache(cache::DataCache)
    show(stdout, MIME"text/plain"(), cache)
end

function Base.show(io::IO, cache::DataCache)
    n = length(cache._index)
    print(io, "DataCache(\"$(cache.store)\", $n entr$(n == 1 ? "y" : "ies"))")
end

function Base.show(io::IO, ::MIME"text/plain", cache::DataCache)
    entries = sort(collect(values(cache._index)); by = k -> k.seq)
    if isempty(entries)
        print(io, "DataCache is empty: $(cache.store)")
        return
    end
    n = length(entries)
    seq_width = isempty(entries) ? 1 : ndigits(entries[end].seq)
    println(io, "DataCache: $(cache.store)  ($n entr$(n == 1 ? "y" : "ies"))")
    for (i, key) in enumerate(entries)
        _print_cacheentry(io, key, seq_width)
        i < n && println(io)
    end
end

# =============================================================================
# Memoization macros  (@mcache / @fcache)
# =============================================================================

# Module-level stores
const _memcache_store = Dict{UInt64,Any}()
const _filecache_ref  = Ref{Union{DataCache,Nothing}}(nothing)

# Autocache state
const _autocache_enabled_ref      = Ref{Bool}(false)
const _autocache_cache_ref        = Ref{Union{DataCache,Nothing}}(nothing)
const _autocache_cache_explicit   = Ref{Bool}(false)   # true iff user passed cache= explicitly
# nothing = all functions (global mode); Set = per-function allowlist
const _autocache_funcs_ref        = Ref{Union{Nothing,Set{Any}}}(nothing)

"""
    default_filecache() → DataCache

Return the module-level default [`DataCache`](@ref) used by [`@filecache`](@ref).
Created lazily on first access using the default Scratch.jl-backed store
(see [`DataCache`](@ref) for details on the default location).
"""
function default_filecache()
    if isnothing(_filecache_ref[])
        _filecache_ref[] = DataCache()
    end
    return _filecache_ref[]
end

"""
    set_default_filecache!(cache::DataCache)

Replace the module-level default cache used by [`@filecache`](@ref).
"""
function set_default_filecache!(cache::DataCache)
    _filecache_ref[] = cache
    return cache
end

"""
    memcache_clear!()

Discard all results stored by [`@memcache`](@ref) for this session.
"""
function memcache_clear!()
    empty!(_memcache_store)
end

"""
    set_autocaching!(enabled::Bool; cache::Union{DataCache,Nothing} = nothing) → Union{DataCache,Nothing}

Enable or disable automatic caching for **all** instrumented API functions.

When `enabled=true`, every call to an instrumented function automatically stores its
result in a [`DataCache`](@ref) and returns the cached result on subsequent identical
calls.

Pass `cache` to use a specific store; that cache is then used regardless of any
`package_cache` the library supplies. When `cache` is omitted, store resolution is
deferred to the `autocache` call site: any `package_cache` supplied by the library
takes priority, with [`default_filecache()`](@ref) as the final fallback.

Returns the active [`DataCache`](@ref) when enabling with an explicit `cache`, or
`nothing` when disabling (or when enabling without an explicit `cache`, in which case
store selection is deferred).

# Examples
```julia
set_autocaching!(true)                                  # library default or default_filecache()
set_autocaching!(false)
set_autocaching!(true; cache=DataCache("/my/project/cache"))  # explicit store
```
"""
function set_autocaching!(enabled::Bool; cache::Union{DataCache,Nothing} = nothing)
    _autocache_enabled_ref[]    = enabled
    _autocache_funcs_ref[]      = nothing  # global mode
    if enabled
        _autocache_cache_ref[]      = isnothing(cache) ? default_filecache() : cache
        _autocache_cache_explicit[] = !isnothing(cache)
    else
        _autocache_cache_ref[]      = nothing
        _autocache_cache_explicit[] = false
    end
    return _autocache_cache_ref[]
end

"""
    set_autocaching!(enabled::Bool, func; cache::Union{DataCache,Nothing} = nothing) → Union{DataCache,Nothing}
    set_autocaching!(enabled::Bool, funcs::AbstractVector; cache::Union{DataCache,Nothing} = nothing) → Union{DataCache,Nothing}

Enable or disable automatic caching for a specific function (or list of functions).

When `enabled=true`, autocache is activated for `func` (additive — does not affect
other per-function settings). If global autocache is currently on, calling this switches
to per-function mode with only `{func}`.

When `enabled=false` and per-function mode is active, removes `func` from the allowlist.
If the allowlist becomes empty, autocache is fully disabled.

**Note:** `set_autocaching!(false, func)` has no effect when global autocache is on; call
`set_autocaching!(false)` to disable globally.

Returns the active [`DataCache`](@ref), or `nothing` when fully disabled.

# Examples
```julia
DataCaches.set_autocaching!(true, pbdb_occurrences)
DataCaches.set_autocaching!(true, [pbdb_occurrences, pbdb_taxa])
DataCaches.set_autocaching!(false, pbdb_occurrences)
```
"""
function set_autocaching!(enabled::Bool, func; cache::Union{DataCache,Nothing} = nothing)
    if enabled
        _autocache_enabled_ref[] = true
        if isnothing(_autocache_cache_ref[]) || !isnothing(cache)
            _autocache_cache_ref[]      = isnothing(cache) ? default_filecache() : cache
            _autocache_cache_explicit[] = !isnothing(cache)
        end
        existing = _autocache_funcs_ref[]
        if isnothing(existing)
            _autocache_funcs_ref[] = Set{Any}([func])
        else
            push!(existing, func)
        end
    else
        existing = _autocache_funcs_ref[]
        if isnothing(existing)
            @warn "set_autocaching!(false, func) has no effect when global autocache is active. " *
                  "Call set_autocaching!(false) to disable autocache globally."
            return _autocache_cache_ref[]
        end
        delete!(existing, func)
        if isempty(existing)
            _autocache_enabled_ref[]    = false
            _autocache_funcs_ref[]      = nothing
            _autocache_cache_ref[]      = nothing
            _autocache_cache_explicit[] = false
        end
    end
    return _autocache_cache_ref[]
end

function set_autocaching!(enabled::Bool, funcs::AbstractVector; cache::Union{DataCache,Nothing} = nothing)
    for f in funcs
        set_autocaching!(enabled, f; cache=cache)
    end
    return _autocache_cache_ref[]
end

# Internal helpers — not exported

_log_ts() = Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")

function _autocache_active(func)
    _autocache_enabled_ref[] || return false
    get(task_local_storage(), :_pbdb_in_explicit_cache, false) && return false
    funcs = _autocache_funcs_ref[]
    isnothing(funcs) && return true  # global mode: all functions
    return func in funcs
end

function _get_autocache_store(package_cache::Union{DataCache,Nothing} = nothing)
    # User explicitly passed cache= to set_autocaching! → always wins
    _autocache_cache_explicit[] && return _autocache_cache_ref[]
    # Library supplied a package-specific default → use it
    isnothing(package_cache) || return package_cache
    # Fall through to whatever set_autocaching! resolved (default_filecache())
    c = _autocache_cache_ref[]
    isnothing(c) && error("Autocache is enabled but no cache is configured.")
    return c
end

function _autocache_key(func, endpoint, kwargs)
    sorted_kw = sort(collect(pairs(kwargs)); by=first)
    label = string(hash(("_autocache_", nameof(func), endpoint, sorted_kw)))
    kw_str = join(["$(k) = $(repr(v))" for (k, v) in sorted_kw], ", ")
    desc = isempty(kw_str) ? "$(nameof(func))($(endpoint))" :
                             "$(nameof(func))($(endpoint); $(kw_str))"
    return (label, desc)
end

"""
    autocache(fetch_fn, func, endpoint, kwargs;
              package_cache::Union{DataCache,Nothing} = nothing,
              force_refresh::Bool = false)

Integration hook for library authors: transparently apply autocaching around a fetch closure.

If autocache is enabled for `func`, checks the cache for a prior result keyed on
`(func, endpoint, kwargs)`. On a hit (and `force_refresh = false`) returns the cached
value immediately. On a miss, calls `fetch_fn()`, stores the result, and returns it.

If autocache is not active for `func`, calls `fetch_fn()` directly.

# Arguments
- `fetch_fn`:       Zero-argument callable that performs the real fetch.
- `func`:           The public API function whose autocache opt-in is checked.
- `endpoint`:       The API endpoint string (e.g. `"occs/list"`).
- `kwargs`:         Keyword arguments passed by the caller.
- `package_cache`:  Optional library-owned default [`DataCache`](@ref). Used when
                    autocache is active but the user did **not** pass an explicit
                    `cache` to [`set_autocaching!`](@ref). Allows a library to default
                    to its own [`scratch_datacache!`](@ref)-backed store while still
                    letting the user override via `set_autocaching!(true; cache=x)`.
                    Pass `nothing` (default) to fall through to [`default_filecache()`](@ref).
- `force_refresh`:  When `true`, bypasses the hit check and overwrites any existing entry.

# Store resolution priority

1. User-explicit: `set_autocaching!(true; cache=x)` → always uses `x`
2. `package_cache` kwarg → used when no explicit user cache was set
3. [`default_filecache()`](@ref) → final fallback
"""
function autocache(fetch_fn, func, endpoint, kwargs;
                   package_cache::Union{DataCache,Nothing} = nothing,
                   force_refresh::Bool = false)
    _autocache_active(func) || return fetch_fn()
    _store = _get_autocache_store(package_cache)
    _ac_key, _ac_desc = _autocache_key(func, endpoint, kwargs)
    if haskey(_store, _ac_key) && !force_refresh
        @debug "$(_log_ts()) autocache: cache hit — $_ac_desc"
        return Base.read(_store, _ac_key)
    end
    @debug "$(_log_ts()) autocache: fetching live — $_ac_desc"
    result = fetch_fn()
    write!(_store, result; label = _ac_key, description = _ac_desc)
    return result
end

# Build the runtime hash-key expression for both macros.
# Positional args are hashed by value; keyword args by (name, value) pairs.
function _cache_hash_expr(func_name::String, raw_args)
    pos = Any[]
    kw  = Any[]
    for a in raw_args
        if a isa Expr && a.head == :kw
            push!(kw, :($(QuoteNode(a.args[1])) => $(esc(a.args[2]))))
        elseif a isa Expr && a.head == :parameters
            for pa in a.args
                if pa isa Expr && pa.head == :kw
                    push!(kw, :($(QuoteNode(pa.args[1])) => $(esc(pa.args[2]))))
                end
            end
        else
            push!(pos, esc(a))
        end
    end
    return :(hash(($func_name, ($(pos...),), ($(kw...),))))
end

function _memcache_impl(expr)
    expr isa Expr && expr.head == :call ||
        error("@memcache: expected a function call, got: $expr")
    func_name = string(expr.args[1])
    key_expr  = _cache_hash_expr(func_name, expr.args[2:end])
    return quote
        let _k = $key_expr
            if haskey(_memcache_store, _k)
                @debug "$(DataCaches._log_ts()) @memcache: cache hit — $($func_name)"
                _memcache_store[_k]
            else
                @debug "$(DataCaches._log_ts()) @memcache: computing live — $($func_name)"
                _r = $(esc(expr))
                _memcache_store[_k] = _r
                _r
            end
        end
    end
end

function _filecache_impl(expr, cache_expr)
    expr isa Expr && expr.head == :call ||
        error("@filecache: expected a function call, got: $expr")
    func_name = string(expr.args[1])
    key_expr  = _cache_hash_expr(func_name, expr.args[2:end])
    expr_str  = sprint(Base.show_unquoted, expr)
    return quote
        let _c = $cache_expr,
            _lbl = string($key_expr)
            if haskey(_c, _lbl)
                @debug "$(DataCaches._log_ts()) @filecache: cache hit — $($expr_str)"
                Base.read(_c, _lbl)
            else
                @debug "$(DataCaches._log_ts()) @filecache: computing live — $($expr_str)"
                _r = task_local_storage(:_pbdb_in_explicit_cache, true) do
                    $(esc(expr))
                end
                write!(_c, _r; label = _lbl, description = $expr_str)
                _r
            end
        end
    end
end

"""
    @memcache expr

Evaluate `expr` (a function call) and cache the result **in memory** for
the current Julia session. Subsequent calls with identical arguments return
the cached value without re-executing the function.

The cache is keyed on the runtime values of all arguments. Use
[`memcache_clear!`](@ref) to discard cached results.

# Example
```julia
occs = @memcache pbdb_occurrences(base_name="Canidae", show="full")
taxa = @memcache pbdb_taxa(name="Dinosauria")
```
"""
macro memcache(expr)
    return _memcache_impl(expr)
end

"""
    @filecache expr
    @filecache cache expr

Evaluate `expr` (a function call) and store the result in a
[`DataCache`](@ref), persisting it **across Julia sessions**.
Subsequent calls with identical arguments load from cache without
executing the function again.

The one-argument form uses [`default_filecache()`](@ref). Pass an explicit
`DataCache` as the first argument to use a different store.

# Examples
```julia
occs = @filecache pbdb_occurrences(base_name="Canidae", show="full")

my_cache = DataCache("/data/pbdb_cache")
occs = @filecache my_cache pbdb_occurrences(base_name="Canidae")
```
"""
macro filecache(expr)
    return _filecache_impl(expr, :(default_filecache()))
end

macro filecache(cache, expr)
    return _filecache_impl(expr, esc(cache))
end

function _filecache_refresh_impl(expr, cache_expr)
    expr isa Expr && expr.head == :call ||
        error("@filecache!: expected a function call, got: $expr")
    func_name = string(expr.args[1])
    key_expr  = _cache_hash_expr(func_name, expr.args[2:end])
    expr_str  = sprint(Base.show_unquoted, expr)
    return quote
        let _c = $cache_expr,
            _lbl = string($key_expr)
            @debug "$(DataCaches._log_ts()) @filecache!: updating cache — $($expr_str)"
            _r = task_local_storage(:_pbdb_in_explicit_cache, true) do
                $(esc(expr))
            end
            write!(_c, _r; label = _lbl, description = $expr_str)
            _r
        end
    end
end

"""
    @filecache! expr
    @filecache! cache expr

Evaluate `expr` (a function call), **unconditionally** store the result in a
[`DataCache`](@ref), and return the result. Unlike [`@filecache`](@ref), this
macro always re-executes the function and overwrites any existing cached entry,
making it useful for forcing a cache refresh.

The one-argument form uses [`default_filecache()`](@ref). Pass an explicit
`DataCache` as the first argument to target a specific store.

A `@debug` message is emitted (visible when `ENV["JULIA_DEBUG"] = "DataCaches"`)
announcing the update.

# Examples
```julia
# Force-refresh the default cache
occs = @filecache! pbdb_occurrences(base_name="Canidae", show="full")

# Force-refresh a specific cache
my_cache = DataCache("/data/pbdb_cache")
occs = @filecache! my_cache pbdb_occurrences(base_name="Canidae")
```
"""
macro filecache!(expr)
    return _filecache_refresh_impl(expr, :(default_filecache()))
end

macro filecache!(cache, expr)
    return _filecache_refresh_impl(expr, esc(cache))
end

include("Caches.jl")
Caches._datacache_ctor[] = DataCache
include("CacheAssets.jl")
include("_migrate_legacy_defaultcache.jl")

# =============================================================================
# entries / entry / labels — primary inspection API
# =============================================================================

"""
    entries(cache::DataCache; kwargs...) → Vector{CacheEntry}
    entries(; kwargs...) → Vector{CacheEntry}

Return the entries of `cache` as a `Vector{`[`CacheEntry`](@ref)`}`, optionally
filtered and sorted. When called without a `cache` argument, uses
[`default_filecache()`](@ref).

This is the primary function for inspecting a cache's contents. Use
[`entry`](@ref) to look up a single entry by label or index, and
[`labels`](@ref) to get just the labels.

# Filtering keyword arguments

| Keyword           | Type                   | Effect                                          |
|:------------------|:-----------------------|:------------------------------------------------|
| `pattern`         | `AbstractString`/Regex | Keep entries whose label or description matches |
| `before`          | `DateTime`             | Keep entries cached before this time            |
| `after`           | `DateTime`             | Keep entries cached after this time             |
| `accessed_before` | `DateTime`             | Keep entries last accessed before this time     |
| `accessed_after`  | `DateTime`             | Keep entries last accessed after this time      |
| `labeled`         | `Bool`                 | `true` = only labeled; `false` = only unlabeled |
| `missing_file`    | `Bool`                 | `true` = only entries whose backing file is gone|

# Sorting keyword arguments

| Keyword  | Values                                                                          |
|:---------|:--------------------------------------------------------------------------------|
| `sortby` | `:seq` (default), `:label`, `:date`, `:date_desc`, `:dateaccessed`,             |
|          | `:dateaccessed_desc`, `:size`, `:size_desc`                                     |
| `rev`    | `Bool` — reverse the sort order                                                 |

# Examples
```julia
dc = DataCache(:myproject)

all_entries   = entries(dc)
labeled_only  = entries(dc; labeled = true)
recent        = entries(dc; after = DateTime("2026-01-01T00:00:00"))
lru           = entries(dc; sortby = :dateaccessed_desc)   # oldest-accessed first
large_first   = entries(dc; sortby = :size_desc)
canidae       = entries(dc; pattern = r"canidae")
entries()                                                   # default cache
```

See also: [`entry`](@ref), [`labels`](@ref), [`keys`](@ref),
[`DataCaches.CacheAssets.ls`](@ref).
"""
entries(cache::DataCache; kwargs...) = CacheAssets.ls(cache; kwargs...)
entries(; kwargs...) = entries(default_filecache(); kwargs...)

"""
    entry(cache::DataCache, label::AbstractString) → CacheEntry
    entry(cache::DataCache, n::Integer) → CacheEntry
    entry(spec) → CacheEntry

Look up a single [`CacheEntry`](@ref) by label string or sequence index `n`.
When called with a single non-`DataCache` argument, uses [`default_filecache()`](@ref).

Throws a `KeyError` if no matching entry exists.

# Examples
```julia
dc = DataCache(:myproject)

e = entry(dc, "dinosaurs")   # by label
e = entry(dc, 3)             # by sequence index
e = entry("dinosaurs")       # default cache, by label
e = entry(2)                 # default cache, by index
```

See also: [`entries`](@ref), [`write!`](@ref), [`haskey`](@ref).
"""
function entry(cache::DataCache, label::AbstractString)
    id = get(cache._by_label, label, nothing)
    isnothing(id) && throw(KeyError(label))
    return cache._index[id]
end

function entry(cache::DataCache, n::Integer)
    e = _resolve_by_seq(cache, Int(n))
    isnothing(e) && throw(KeyError(n))
    return e
end

entry(spec) = entry(default_filecache(), spec)

"""
    labels(cache::DataCache) → Vector{String}
    labels() → Vector{String}

Return all user-assigned labels for entries in `cache`, excluding unlabeled entries
(those keyed only by an auto-generated hash). When called without arguments, uses
[`default_filecache()`](@ref).

# Examples
```julia
dc = DataCache(:myproject)
dc["foo"] = 1
dc["bar"] = 2

labels(dc)   # → ["foo", "bar"] (order may vary)
labels()     # default cache
```

See also: [`entries`](@ref), [`keylabels`](@ref).
"""
labels(cache::DataCache) = collect(keys(cache._by_label))
labels() = labels(default_filecache())

end # module
