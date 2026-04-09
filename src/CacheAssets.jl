module CacheAssets

import ..DataCaches: DataCache, CacheEntry, CacheKey, default_filecache,
                     _read_file, _remove_entry!, _save_index,
                     _resolve_by_seq, write!
import Dates

# =============================================================================
# Internal: resolve any asset specifier → CacheEntry
# =============================================================================

function _resolve(cache::DataCache, spec::CacheEntry)
    haskey(cache._index, spec.id) || error("CacheEntry not found in this cache")
    return spec
end

function _resolve(cache::DataCache, spec::Integer)
    key = _resolve_by_seq(cache, Int(spec))
    isnothing(key) && error("No cache entry with sequence index $spec")
    return key
end

function _resolve(cache::DataCache, spec::AbstractString)
    id = get(cache._by_label, spec, nothing)
    if isnothing(id)
        matches = [k for k in keys(cache._index) if startswith(k, spec)]
        length(matches) == 0 && error("No cache entry with label or UUID prefix $(repr(spec))")
        length(matches) > 1  && error("Ambiguous UUID prefix $(repr(spec)) matches $(length(matches)) entries")
        id = only(matches)
    end
    return cache._index[id]
end

# =============================================================================
# Internal: display helpers
# =============================================================================

function _fmt_size(bytes::Integer)
    bytes < 1024   && return "$(bytes) B"
    bytes < 1024^2 && return "$(round(bytes / 1024,        digits=1)) KiB"
    bytes < 1024^3 && return "$(round(bytes / 1024^2,      digits=1)) MiB"
    return                   "$(round(bytes / 1024^3,      digits=2)) GiB"
end

function _dt_str(dt::Dates.DateTime)
    dt == typemin(Dates.DateTime) && return " "^19
    return Dates.format(dt, "yyyy-mm-ddTHH:MM:SS")
end

function _ls_print(io::IO, entries::Vector{CacheEntry}, sizes::Dict{String,Int},
                   detail::Symbol)
    if isempty(entries)
        println(io, "(no entries)")
        return
    end
    seq_width = ndigits(maximum(k.seq for k in entries))
    n = length(entries)
    for (i, k) in enumerate(entries)
        label_str = !isempty(k.description) ? k.description :
                    !isempty(k.label)       ? k.label       : "(unlabeled)"
        file_ok   = isfile(k.path)
        miss_tag  = file_ok ? "" : "  *** FILE MISSING ***"
        seq_str   = lpad(k.seq, seq_width)
        # prefix_len: "  [" + seq_width + "]  " + 19 + "  " + 8 + "  " = seq_width + 37
        prefix_len = seq_width + 37

        if detail == :minimal
            println(io, "  [$(seq_str)]  $(label_str)$(miss_tag)")
        elseif detail == :normal
            println(io, "  [$(seq_str)]  $(_dt_str(k.datecached))  $(k.id[1:8])  $(label_str)$(miss_tag)")
            print(io,   " "^prefix_len * k.path)
        elseif detail == :full
            sz    = get(sizes, k.id, -1)
            sz_str = sz >= 0 ? _fmt_size(sz) : "???"
            type_tag = uppercase(k.format)
            println(io, "  [$(seq_str)]  $(_dt_str(k.datecached))  $(k.id[1:8])  $(label_str)$(miss_tag)")
            da_str = k.dateaccessed == typemin(Dates.DateTime) ? "(never)" :
                     Dates.format(k.dateaccessed, "yyyy-mm-ddTHH:MM:SS")
            println(io, " "^prefix_len * "cached: $(_dt_str(k.datecached))  accessed: $(da_str)  $(sz_str)  $(type_tag)")
            print(io,   " "^prefix_len * k.path)
        else
            error("Unknown detail level $(repr(detail)); expected :minimal, :normal, or :full")
        end
        i < n && println(io)
    end
    println(io)
end

# =============================================================================
# ls / ls! — list assets
# =============================================================================

# Shared filtering/sorting backend.  Returns (entries, sizes) where `sizes` is
# populated only when `need_sizes` is true (required for :size/:size_desc sort
# and for the :full display detail level).
function _ls_select(cache::DataCache;
                    pattern::Union{Nothing,Regex,AbstractString} = nothing,
                    before::Union{Nothing,Dates.DateTime}        = nothing,
                    after::Union{Nothing,Dates.DateTime}         = nothing,
                    accessed_before::Union{Nothing,Dates.DateTime} = nothing,
                    accessed_after::Union{Nothing,Dates.DateTime}  = nothing,
                    labeled::Union{Nothing,Bool}                 = nothing,
                    missing_file::Bool                           = false,
                    sortby::Symbol                               = :seq,
                    rev::Bool                                    = false,
                    need_sizes::Bool                             = false)
    entries = collect(values(cache._index))

    # --- Filter ---
    pat = pattern isa AbstractString ? Regex(pattern) :
          pattern isa Regex          ? pattern        : nothing

    filter!(entries) do k
        !missing_file && !isfile(k.path) && return false
        if !isnothing(labeled)
            labeled  && isempty(k.label)  && return false
            !labeled && !isempty(k.label) && return false
        end
        if !isnothing(before)
            k.datecached != typemin(Dates.DateTime) && k.datecached >= before && return false
        end
        if !isnothing(after)
            k.datecached != typemin(Dates.DateTime) && k.datecached <= after && return false
        end
        if !isnothing(accessed_before)
            k.dateaccessed != typemin(Dates.DateTime) && k.dateaccessed >= accessed_before && return false
        end
        if !isnothing(accessed_after)
            k.dateaccessed != typemin(Dates.DateTime) && k.dateaccessed <= accessed_after && return false
        end
        if !isnothing(pat)
            target = !isempty(k.label)       ? k.label :
                     !isempty(k.description) ? k.description : k.id
            occursin(pat, target) || return false
        end
        return true
    end

    # --- Sizes (fetch only when needed) ---
    sizes = if need_sizes
        Dict{String,Int}(k.id => (isfile(k.path) ? stat(k.path).size : -1) for k in entries)
    else
        Dict{String,Int}()
    end

    # --- Sort ---
    do_rev = rev
    sort_fn = if sortby == :seq
        k -> k.seq
    elseif sortby == :label
        k -> (isempty(k.label) ? "\xff" * k.id : k.label)
    elseif sortby == :date
        k -> k.datecached
    elseif sortby == :date_desc
        do_rev = !rev
        k -> k.datecached
    elseif sortby == :dateaccessed
        k -> k.dateaccessed
    elseif sortby == :dateaccessed_desc
        do_rev = !rev
        k -> k.dateaccessed
    elseif sortby == :size
        k -> get(sizes, k.id, -1)
    elseif sortby == :size_desc
        do_rev = !rev
        k -> get(sizes, k.id, -1)
    else
        error("Unknown sortby $(repr(sortby)); expected :seq, :label, :date, :date_desc, " *
              ":dateaccessed, :dateaccessed_desc, :size, or :size_desc")
    end
    sort!(entries; by = sort_fn, rev = do_rev)

    return entries, sizes
end

"""
    DataCaches.CacheAssets.ls([cache::DataCache]; kwargs...) → Vector{CacheEntry}

Return a filtered and sorted vector of cache entries from `cache`.
If `cache` is omitted, the active default cache is used (see `default_filecache()`).

!!! note
    [`DataCaches.entries`](@ref) exposes the same functionality at the top level
    without needing to import `CacheAssets`.

# Keyword arguments

**Filtering:**
- `pattern` — `Regex` or `String` (converted to `Regex`); matched against label,
  description, then UUID. Pass `nothing` (default) to disable.
- `before::DateTime` — include only entries written before this time
- `after::DateTime` — include only entries written after this time
- `accessed_before::DateTime` — include only entries last accessed before this time
- `accessed_after::DateTime` — include only entries last accessed after this time
- `labeled::Union{Nothing,Bool} = nothing` — `true` for labeled entries only,
  `false` for unlabeled only, `nothing` for all
- `missing_file::Bool = false` — when `true`, include entries whose backing file is absent

**Sorting:**
- `sortby::Symbol = :seq` — sort criterion: `:seq`, `:label`, `:date`, `:date_desc`,
  `:dateaccessed`, `:dateaccessed_desc`, `:size`, `:size_desc`
- `rev::Bool = false` — reverse the sort order

See also [`ls!`](@ref) for a display-oriented variant that prints to an `IO` stream.
"""
function ls(cache::DataCache;
            pattern::Union{Nothing,Regex,AbstractString} = nothing,
            before::Union{Nothing,Dates.DateTime}        = nothing,
            after::Union{Nothing,Dates.DateTime}         = nothing,
            accessed_before::Union{Nothing,Dates.DateTime} = nothing,
            accessed_after::Union{Nothing,Dates.DateTime}  = nothing,
            labeled::Union{Nothing,Bool}                 = nothing,
            missing_file::Bool                           = false,
            sortby::Symbol                               = :seq,
            rev::Bool                                    = false)
    entries, _ = _ls_select(cache;
                            pattern, before, after, accessed_before, accessed_after,
                            labeled, missing_file, sortby, rev,
                            need_sizes = sortby ∈ (:size, :size_desc))
    return entries
end

ls(; kwargs...) = ls(default_filecache(); kwargs...)

"""
    DataCaches.CacheAssets.ls!([cache::DataCache]; kwargs...) → nothing

Print a formatted listing of assets in `cache` to `io` (default `stdout`).
If `cache` is omitted, the active default cache is used (see `default_filecache()`).

Accepts all the same filtering and sorting keyword arguments as [`ls`](@ref), plus:

# Additional keyword arguments

**Display:**
- `detail::Symbol = :normal` — richness of the output:
  - `:minimal` — sequence index and label only
  - `:normal` (default) — index, write timestamp, UUID prefix, label, and file path
  - `:full` — all of `:normal` plus last-access time, file size, and data format
- `io::IO = stdout`
"""
function ls!(cache::DataCache;
             detail::Symbol                               = :normal,
             pattern::Union{Nothing,Regex,AbstractString} = nothing,
             before::Union{Nothing,Dates.DateTime}        = nothing,
             after::Union{Nothing,Dates.DateTime}         = nothing,
             accessed_before::Union{Nothing,Dates.DateTime} = nothing,
             accessed_after::Union{Nothing,Dates.DateTime}  = nothing,
             labeled::Union{Nothing,Bool}                 = nothing,
             missing_file::Bool                           = false,
             sortby::Symbol                               = :seq,
             rev::Bool                                    = false,
             io::IO                                       = stdout)
    entries, sizes = _ls_select(cache;
                                pattern, before, after, accessed_before, accessed_after,
                                labeled, missing_file, sortby, rev,
                                need_sizes = sortby ∈ (:size, :size_desc) || detail == :full)
    _ls_print(io, entries, sizes, detail)
    return nothing
end

ls!(; kwargs...) = ls!(default_filecache(); kwargs...)

# =============================================================================
# rm — remove assets
# =============================================================================

"""
    DataCaches.CacheAssets.rm([cache::DataCache,] assets...; force=false)

Remove one or more assets from `cache` (default: active default cache).
Each asset can be specified as a [`CacheEntry`](@ref), label `String`, UUID-prefix `String`,
or sequence index `Integer`. The backing data file is also deleted from disk.

All removals are batched into a single index rewrite for efficiency.

Pass `force=true` to suppress errors for unresolvable specifiers (they are silently skipped).
"""
function rm(cache::DataCache, assets...; force::Bool = false)
    isempty(assets) && error("rm: at least one asset specifier is required")
    for spec in assets
        key = try
            _resolve(cache, spec)
        catch e
            force && continue
            rethrow(e)
        end
        _remove_entry!(cache, key.id)
    end
    _save_index(cache)
    return cache
end

rm(assets...; kwargs...) = rm(default_filecache(), assets...; kwargs...)

# =============================================================================
# mv — relabel within cache OR move to another cache
# =============================================================================

"""
    DataCaches.CacheAssets.mv([src_cache::DataCache,] src, dest; kwargs...)

Move or relabel a cache asset. `src` can be a [`CacheEntry`](@ref), label `String`,
UUID-prefix `String`, or sequence index `Integer`.

**Relabel within the same cache** (when `dest` is a `String`):

    mv(cache, src, new_label::String; force=false)

Rename `src` to `new_label` in place. If `new_label` is already taken by a
different entry, an error is raised unless `force=true`, in which case the
conflicting entry is removed first.

**Move to another cache** (when `dest` is a `DataCache`):

    mv(src_cache, src, dest_cache::DataCache; label="", force=false)

Read the asset from `src_cache`, write it to `dest_cache` (with a new UUID,
sequence number, and `datecached` timestamp), then remove it from `src_cache`.
The `label` kwarg overrides the destination label (default: preserve the original).
Pass `force=true` to overwrite an existing entry with the same label in `dest_cache`.

If `src_cache` is omitted, `default_filecache()` is used as the source.
"""
function mv(cache::DataCache, src, dest::AbstractString; force::Bool = false)
    key = _resolve(cache, src)
    existing_id = get(cache._by_label, dest, nothing)
    if !isnothing(existing_id) && existing_id != key.id
        force || error("Label $(repr(dest)) is already in use by another entry; pass force=true to replace it")
        _remove_entry!(cache, existing_id)
    end
    isempty(key.label) || delete!(cache._by_label, key.label)
    new_key = CacheEntry(key.id, key.seq, dest, key.path, key.format, key.description,
                        key.datecached, key.dateaccessed)
    cache._index[key.id] = new_key
    isempty(dest) || (cache._by_label[dest] = key.id)
    _save_index(cache)
    return new_key
end

function mv(src_cache::DataCache, src, dest_cache::DataCache;
            label::AbstractString = "", force::Bool = false)
    src_cache === dest_cache && error("mv: source and destination caches are the same; use mv(cache, src, new_label) to relabel")
    key       = _resolve(src_cache, src)
    new_label = !isempty(label) ? label : key.label
    if !isempty(new_label) && haskey(dest_cache._by_label, new_label)
        force || error("Label $(repr(new_label)) already exists in destination cache; pass force=true to overwrite")
    end
    data = _read_file(key)
    new_key = write!(dest_cache, data; label = new_label, description = key.description)
    _remove_entry!(src_cache, key.id)
    _save_index(src_cache)
    return new_key
end

# Default-cache forms
mv(src, dest::AbstractString; kwargs...)  = mv(default_filecache(), src, dest; kwargs...)
mv(src, dest::DataCache; kwargs...)       = mv(default_filecache(), src, dest; kwargs...)

# =============================================================================
# cp — copy assets to another cache
# =============================================================================

"""
    DataCaches.CacheAssets.cp([src_cache::DataCache,] src, dest_cache::DataCache; kwargs...)
    DataCaches.CacheAssets.cp([src_cache::DataCache,] srcs::AbstractVector, dest_cache::DataCache; kwargs...)

Copy one or more assets to `dest_cache`. Each copy receives a new UUID, sequence
number, and `datecached` timestamp in the destination. Copying within the same
cache is allowed and produces a distinct new entry.

`src` / each element of `srcs` can be a [`CacheEntry`](@ref), label `String`, UUID-prefix
`String`, or sequence index `Integer`.

**Single-source form:**
- `label=""` — override the destination label (default: preserve original label)
- `force=false` — when `true`, silently replace an existing entry with the same label

**Multi-source form (`srcs::AbstractVector`):**
- Each entry preserves its original label; returns a `Vector{CacheKey}` of new keys
- `force=false` — apply to all entries

If `src_cache` is omitted, `default_filecache()` is used as the source.
"""
function cp(src_cache::DataCache, src, dest_cache::DataCache;
            label::AbstractString = "", force::Bool = false)
    key       = _resolve(src_cache, src)
    new_label = !isempty(label) ? label : key.label
    if !isempty(new_label) && haskey(dest_cache._by_label, new_label)
        force || error("Label $(repr(new_label)) already exists in destination cache; pass force=true to overwrite")
    end
    data = _read_file(key)
    return write!(dest_cache, data; label = new_label, description = key.description)
end

function cp(src_cache::DataCache, srcs::AbstractVector, dest_cache::DataCache;
            force::Bool = false)
    isempty(srcs) && error("cp: at least one source specifier is required")
    results = CacheEntry[]
    for src in srcs
        key = _resolve(src_cache, src)
        new_label = key.label
        if !isempty(new_label) && haskey(dest_cache._by_label, new_label)
            force || error("Label $(repr(new_label)) already exists in destination cache; pass force=true to overwrite")
        end
        data = _read_file(key)
        push!(results, write!(dest_cache, data; label = new_label, description = key.description))
    end
    return results
end

# Default-cache forms
cp(src, dest_cache::DataCache; kwargs...)                    = cp(default_filecache(), src, dest_cache; kwargs...)
cp(srcs::AbstractVector, dest_cache::DataCache; kwargs...)   = cp(default_filecache(), srcs, dest_cache; kwargs...)

end # module CacheAssets
