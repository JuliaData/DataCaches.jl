module CacheAssets

import ..DataCaches: DataCache, CacheEntry, CacheEntry, default_filecache,
                     _read_file, _remove_entry!, _save_index,
                     _resolve_by_seq, write!, isstale
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
        matches = [k for k in entries(cache._index) if startswith(k, spec)]
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
                    pattern::Union{Nothing,Regex,AbstractString}             = nothing,
                    filepath_pattern::Union{Nothing,Regex,AbstractString}    = nothing,
                    filename_pattern::Union{Nothing,Regex,AbstractString}    = nothing,
                    format::Union{Nothing,String,Regex}                      = nothing,
                    before::Union{Nothing,Dates.DateTime}                    = nothing,
                    after::Union{Nothing,Dates.DateTime}                     = nothing,
                    accessed_before_date::Union{Nothing,Dates.DateTime}      = nothing,
                    accessed_after_date::Union{Nothing,Dates.DateTime}       = nothing,
                    labeled::Union{Nothing,Bool}                             = nothing,
                    missing_file::Bool                                       = false,
                    sortby::Symbol                                           = :seq,
                    rev::Bool                                                = false,
                    need_sizes::Bool                                         = false)
    entries = collect(values(cache._index))

    # --- Filter ---
    pat    = pattern          isa AbstractString ? Regex(pattern)          :
             pattern          isa Regex          ? pattern                 : nothing
    fp_pat = filepath_pattern isa AbstractString ? Regex(filepath_pattern) :
             filepath_pattern isa Regex          ? filepath_pattern        : nothing
    fn_pat = filename_pattern isa AbstractString ? Regex(filename_pattern) :
             filename_pattern isa Regex          ? filename_pattern        : nothing
    fmt_pat = format isa AbstractString ? Regex(string("^", format, "\$")) :
              format isa Regex          ? format                           : nothing

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
        if !isnothing(accessed_before_date)
            k.dateaccessed != typemin(Dates.DateTime) && k.dateaccessed >= accessed_before_date && return false
        end
        if !isnothing(accessed_after_date)
            k.dateaccessed != typemin(Dates.DateTime) && k.dateaccessed <= accessed_after_date && return false
        end
        if !isnothing(pat)
            target = !isempty(k.label)       ? k.label :
                     !isempty(k.description) ? k.description : k.id
            occursin(pat, target) || return false
        end
        if !isnothing(fp_pat)
            occursin(fp_pat, k.path) || return false
        end
        if !isnothing(fn_pat)
            occursin(fn_pat, basename(k.path)) || return false
        end
        if !isnothing(fmt_pat)
            occursin(fmt_pat, k.format) || return false
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
- `filepath_pattern` — `Regex` or `String`; matched against the full absolute file path
  of each entry's backing data file.
- `filename_pattern` — `Regex` or `String`; matched against only the filename
  (i.e. `basename(path)`) of each entry's backing data file.
- `before::DateTime` — include only entries written before this time
- `after::DateTime` — include only entries written after this time
- `accessed_before_date::DateTime` — include only entries last accessed before this time
- `accessed_after_date::DateTime` — include only entries last accessed after this time
- `labeled::Union{Nothing,Bool} = nothing` — `true` for labeled entries only,
  `false` for unlabeled only, `nothing` for all
- `missing_file::Bool = false` — when `true`, include entries whose backing file is absent
- `format::Union{Nothing,String,Regex} = nothing` — `String` for exact format tag match
  (e.g. `"csv"`, `"jls"`), `Regex` for pattern match (e.g. `r"csv|json"`)

**Sorting:**
- `sortby::Symbol = :seq` — sort criterion: `:seq`, `:label`, `:date`, `:date_desc`,
  `:dateaccessed`, `:dateaccessed_desc`, `:size`, `:size_desc`
- `rev::Bool = false` — reverse the sort order

See also [`ls!`](@ref) for a display-oriented variant that prints to an `IO` stream.
"""
function ls(cache::DataCache;
            pattern::Union{Nothing,Regex,AbstractString}          = nothing,
            filepath_pattern::Union{Nothing,Regex,AbstractString} = nothing,
            filename_pattern::Union{Nothing,Regex,AbstractString} = nothing,
            format::Union{Nothing,String,Regex}                   = nothing,
            before::Union{Nothing,Dates.DateTime}                 = nothing,
            after::Union{Nothing,Dates.DateTime}                  = nothing,
            accessed_before_date::Union{Nothing,Dates.DateTime}   = nothing,
            accessed_after_date::Union{Nothing,Dates.DateTime}    = nothing,
            labeled::Union{Nothing,Bool}                          = nothing,
            missing_file::Bool                                    = false,
            sortby::Symbol                                        = :seq,
            rev::Bool                                             = false)
    entries, _ = _ls_select(cache;
                            pattern, filepath_pattern, filename_pattern, format,
                            before, after, accessed_before_date, accessed_after_date,
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
             detail::Symbol                                        = :normal,
             pattern::Union{Nothing,Regex,AbstractString}          = nothing,
             filepath_pattern::Union{Nothing,Regex,AbstractString} = nothing,
             filename_pattern::Union{Nothing,Regex,AbstractString}  = nothing,
             format::Union{Nothing,String,Regex}                    = nothing,
             before::Union{Nothing,Dates.DateTime}                  = nothing,
             after::Union{Nothing,Dates.DateTime}                   = nothing,
             accessed_before_date::Union{Nothing,Dates.DateTime}    = nothing,
             accessed_after_date::Union{Nothing,Dates.DateTime}     = nothing,
             labeled::Union{Nothing,Bool}                           = nothing,
             missing_file::Bool                                     = false,
             sortby::Symbol                                         = :seq,
             rev::Bool                                              = false,
             io::IO                                                 = stdout)
    entries, sizes = _ls_select(cache;
                                pattern, filepath_pattern, filename_pattern, format,
                                before, after, accessed_before_date, accessed_after_date,
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
    DataCaches.CacheAssets.rm([cache::DataCache,] specs::AbstractVector; force=false)

Remove one or more assets from `cache` (default: active default cache).
Each asset can be specified as a [`CacheEntry`](@ref), label `String`, UUID-prefix `String`,
or sequence index `Integer`. The backing data file is also deleted from disk.

All removals are batched into a single index rewrite for efficiency.

The `AbstractVector` form accepts a vector of any mix of the above specifier types,
which is convenient for operating on the result of [`ls`](@ref).

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

function rm(cache::DataCache, specs::AbstractVector; force::Bool = false)
    isempty(specs) && return cache
    for spec in specs
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

rm(assets...; kwargs...)                   = rm(default_filecache(), assets...; kwargs...)
rm(specs::AbstractVector; kwargs...)       = rm(default_filecache(), specs; kwargs...)

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
                        key.datecached, key.dateaccessed, key.ttl)
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
- Each entry preserves its original label; returns a `Vector{CacheEntry}` of new entries
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

# =============================================================================
# purge! — bulk deletion with rich criteria
# =============================================================================

"""
    DataCaches.CacheAssets.purge!([cache::DataCache]; kwargs...) → DataCache

Bulk-delete cache entries matching the given criteria. All standard `ls` filtering
keyword arguments are accepted to scope which entries are candidates for purging.
When `cache` is omitted, the active default cache is used (see `default_filecache()`).

All removals are batched into a single index rewrite.

# Standard filter kwargs (same as `ls`)

- `pattern`, `filepath_pattern`, `filename_pattern` — label/path/filename pattern
- `format::Union{Nothing,String,Regex}` — format tag filter (e.g. `"jls"`, `r"csv|json"`)
- `before`, `after` — filter by `datecached`
- `accessed_before_date`, `accessed_after_date` — filter by `dateaccessed`
- `labeled::Union{Nothing,Bool}` — `true` = labeled only; `false` = unlabeled only

# Purge criteria (applied after filtering)

- `stale::Bool = false` — delete entries past their TTL (requires TTL to be configured)
- `max_age::Union{Nothing,Period}` — delete entries whose age (by `datecached`) exceeds this
- `max_idle::Union{Nothing,Period}` — delete entries that have not been accessed within this period
  (entries never accessed are treated as least-recently-used and are eligible)
- `keep_count::Union{Nothing,Int}` — keep only the N most-recently-accessed entries
  among the candidates; delete the rest
- `max_size_bytes::Union{Nothing,Int}` — purge LRU entries until the total size of
  the remaining candidates is at or below this limit

# Options

- `keep_labeled::Bool = false` — when `true`, labeled entries are never deleted,
  even if they match all other criteria
- `dry_run::Bool = false` — print what would be deleted to `io` without deleting
- `io::IO = stdout` — output stream for `dry_run` messages

# Examples

```julia
dc = DataCache(:myproject)

# Remove all stale entries (requires TTL on entries or cache)
CacheAssets.purge!(dc; stale = true)

# Remove entries older than 30 days
CacheAssets.purge!(dc; max_age = Dates.Day(30))

# Keep only the 10 most recently accessed entries
CacheAssets.purge!(dc; keep_count = 10)

# Purge LRU entries until cache is under 100 MiB, keep labeled entries
CacheAssets.purge!(dc; max_size_bytes = 100 * 1024 * 1024, keep_labeled = true)

# Preview without deleting
CacheAssets.purge!(dc; max_age = Dates.Day(7), dry_run = true)

# Purge using default cache
CacheAssets.purge!(; keep_count = 50)
```

See also [`ls`](@ref), [`rm`](@ref), [`DataCaches.invalidate!`](@ref),
[`DataCaches.set_autopurge!`](@ref).
"""
function purge!(cache::DataCache;
                stale::Bool                                           = false,
                max_age::Union{Nothing,Dates.Period}                  = nothing,
                max_idle::Union{Nothing,Dates.Period}                 = nothing,
                keep_count::Union{Nothing,Int}                        = nothing,
                max_size_bytes::Union{Nothing,Int}                    = nothing,
                keep_labeled::Bool                                    = false,
                dry_run::Bool                                         = false,
                io::IO                                                = stdout,
                pattern::Union{Nothing,Regex,AbstractString}          = nothing,
                filepath_pattern::Union{Nothing,Regex,AbstractString} = nothing,
                filename_pattern::Union{Nothing,Regex,AbstractString} = nothing,
                format::Union{Nothing,String,Regex}                   = nothing,
                before::Union{Nothing,Dates.DateTime}                 = nothing,
                after::Union{Nothing,Dates.DateTime}                  = nothing,
                accessed_before_date::Union{Nothing,Dates.DateTime}   = nothing,
                accessed_after_date::Union{Nothing,Dates.DateTime}    = nothing,
                labeled::Union{Nothing,Bool}                          = nothing,
                missing_file::Bool                                    = false,
                sortby::Symbol                                        = :seq,
                rev::Bool                                             = false)::DataCache
    need_sizes = !isnothing(max_size_bytes)
    candidates, sizes = _ls_select(cache;
                                   pattern, filepath_pattern, filename_pattern, format,
                                   before, after, accessed_before_date, accessed_after_date,
                                   labeled, missing_file, sortby, rev,
                                   need_sizes)

    # Apply keep_labeled: remove labeled entries from the candidates set
    if keep_labeled
        filter!(e -> isempty(e.label), candidates)
    end

    # Collect ids to delete using a Set to avoid duplicates
    to_delete = Set{String}()

    # stale: entries past their TTL
    if stale
        for e in candidates
            isstale(cache, e) && push!(to_delete, e.id)
        end
    end

    # max_age: entries older than max_age (by datecached)
    if !isnothing(max_age)
        cutoff = Dates.now() - max_age
        for e in candidates
            e.datecached != typemin(Dates.DateTime) && e.datecached < cutoff && push!(to_delete, e.id)
        end
    end

    # max_idle: entries not accessed in max_idle (never-accessed treated as most idle)
    if !isnothing(max_idle)
        cutoff = Dates.now() - max_idle
        for e in candidates
            if e.dateaccessed == typemin(Dates.DateTime) || e.dateaccessed < cutoff
                push!(to_delete, e.id)
            end
        end
    end

    # keep_count: delete LRU entries beyond the top-N most recently accessed
    if !isnothing(keep_count) && keep_count < length(candidates)
        sorted_by_access = sort(candidates;
                                by = e -> e.dateaccessed,
                                rev = true)  # most recently accessed first
        for e in sorted_by_access[keep_count + 1:end]
            push!(to_delete, e.id)
        end
    end

    # max_size_bytes: purge LRU entries until total remaining size ≤ limit
    if !isnothing(max_size_bytes)
        # Compute sizes for all candidates (use the sizes dict if already computed)
        sorted_lru = sort(candidates;
                          by = e -> e.dateaccessed)  # least recently accessed first
        total_bytes = sum(get(sizes, e.id, isfile(e.path) ? stat(e.path).size : 0)
                          for e in candidates; init = 0)
        for e in sorted_lru
            total_bytes <= max_size_bytes && break
            push!(to_delete, e.id)
            total_bytes -= get(sizes, e.id, isfile(e.path) ? stat(e.path).size : 0)
        end
    end

    # Resolve final delete list in seq order for readable output
    delete_entries = filter(e -> e.id ∈ to_delete, candidates)
    sort!(delete_entries; by = e -> e.seq)

    if dry_run
        if isempty(delete_entries)
            println(io, "purge! (dry run): no entries match criteria")
        else
            println(io, "purge! (dry run): $(length(delete_entries)) entr$(length(delete_entries) == 1 ? "y" : "ies") would be removed:")
            seq_width = ndigits(maximum(e.seq for e in delete_entries))
            for e in delete_entries
                lbl = !isempty(e.label) ? e.label : !isempty(e.description) ? e.description : "(unlabeled)"
                println(io, "  [$(lpad(e.seq, seq_width))]  $(lbl)  $(e.path)")
            end
        end
        return cache
    end

    for e in delete_entries
        _remove_entry!(cache, e.id)
    end
    isempty(delete_entries) || _save_index(cache)
    return cache
end

purge!(; kwargs...)::DataCache = purge!(default_filecache(); kwargs...)

end # module CacheAssets
