```@meta
CurrentModule = DataCaches
```

# Cache Assets — asset management within a cache

`DataCaches.CacheAssets` is a submodule (public, not exported) that provides a
filesystem-style interface for managing individual *assets* (entries) within a
`DataCache`. Import it as `using DataCaches.CacheAssets` or access functions as
`DataCaches.CacheAssets.<function>`.

All functions accept an optional leading `DataCache` argument. When omitted,
`default_filecache()` is used.

## List assets

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

# Filter by file path (full path or filename only)
entries = CacheAssets.ls(dc; filepath_pattern = r"/project/caches/")
entries = CacheAssets.ls(dc; filepath_pattern = "/scratch")    # string → Regex
entries = CacheAssets.ls(dc; filename_pattern = r"^abc1234")   # UUID-prefix match
entries = CacheAssets.ls(dc; filename_pattern = r"\.csv$")     # CSV-backed entries only

# Filter by write or access date
entries = CacheAssets.ls(dc; after  = DateTime("2026-01-01T00:00:00"))
entries = CacheAssets.ls(dc; before = DateTime("2026-06-01T00:00:00"))
entries = CacheAssets.ls(dc; accessed_after_date  = DateTime("2026-03-01T00:00:00"))
entries = CacheAssets.ls(dc; accessed_before_date = DateTime("2026-06-01T00:00:00"))

# Filter by whether the entry has a label
entries = CacheAssets.ls(dc; labeled = true)   # only labeled entries
entries = CacheAssets.ls(dc; labeled = false)  # only unlabeled entries

# Filter by format tag
entries = CacheAssets.ls(dc; format = "jls")        # exact match
entries = CacheAssets.ls(dc; format = r"csv|json")  # Regex match

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
CacheAssets.ls!(dc; filename_pattern = r"\.csv$", detail = :full)

# Redirect output
CacheAssets.ls!(dc; io = my_io)

# Use default cache
CacheAssets.ls!()
CacheAssets.ls!(; detail = :full, sortby = :date_desc)
```

## Remove assets

```julia
# Remove by label, sequence index, UUID prefix, or CacheEntry — in any combination
CacheAssets.rm(dc, "canidae_occs")
CacheAssets.rm(dc, 3)
CacheAssets.rm(dc, "canidae_occs", "dinosaur_taxa", 5)

# Pass a vector of specifiers (any mix of CacheEntry, label String, seq Integer)
stale = CacheAssets.ls(dc; before = DateTime("2026-01-01"))
CacheAssets.rm(dc, stale)                              # remove all at once (one index rewrite)
CacheAssets.rm(dc, [entry1, "old_label", 7])           # mixed-type vector

# Suppress errors for missing specifiers
CacheAssets.rm(dc, "maybe_exists"; force = true)
CacheAssets.rm(dc, ["maybe1", "maybe2"]; force = true)

# Default cache
CacheAssets.rm("old_entry")
CacheAssets.rm(stale)
```

## Relabel and move assets

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

## Copy assets to another cache

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

## Access-time tracking and LRU support

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

## Quick-reference table

| Function | Description |
|---|---|
| `CacheAssets.ls([dc]; pattern, filepath_pattern, filename_pattern, format, before, after, accessed_before_date, accessed_after_date, labeled, sortby, rev)` | List assets in a cache |
| `CacheAssets.ls!([dc]; detail, …same filters…, io)` | Print formatted listing to `io` |
| `CacheAssets.rm([dc,] assets...; force)` | Remove assets by varargs (batched index rewrite) |
| `CacheAssets.rm([dc,] specs::Vector; force)` | Remove assets by vector (batched index rewrite) |
| `delete!(dc, specs::Vector)` | Remove assets by vector from `DataCache` directly |
| `CacheAssets.mv([dc,] src, new_label; force)` | Relabel an asset within a cache |
| `CacheAssets.mv([src_dc,] src, dest_dc; label, force)` | Move asset to another cache |
| `CacheAssets.cp([src_dc,] src, dest_dc; label, force)` | Copy asset to another cache |
| `CacheAssets.cp([src_dc,] srcs::Vector, dest_dc; force)` | Copy multiple assets to another cache |
| `CacheAssets.purge!([dc]; max_age, max_idle, keep_count, max_size_bytes, stale, keep_labeled, dry_run, …ls filters…)` | Bulk-delete entries by age, idle time, count, or size (LRU) |

## API reference

```@autodocs
Modules = [DataCaches.CacheAssets]
```
