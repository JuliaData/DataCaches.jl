## Planned

### Cache rebuild

Add rebuild cache -- missing files removed from index etc. All with @debug logging of individual files found, @warn if not found, @error if cache malformed etc. Rebuild proceeds if kwarg `dr

### ~~Expiration / invalidation primitives~~ (implemented in 0.4.0)

Implemented:
- `CacheEntry.ttl` field + `DataCache(; default_ttl=)` for per-entry and cache-level TTL
- `isstale(cache, entry/label)` for stale detection (stale-while-revalidate friendly)
- `invalidate!(cache; stale, pattern, format, before, after, labeled, predicate, dry_run)` for bulk invalidation
- `CacheAssets.purge!(cache; max_age, max_idle, keep_count, max_size_bytes, stale, keep_labeled, dry_run, …filters…)` for LRU/size-limit purging
- `set_autopurge!(cache; max_age, max_idle, keep_count, max_size_bytes, keep_labeled)` for automatic post-write purging
- `format` filter added to `CacheAssets.ls` / `ls!` / `entries`

### Cache size stats


### Atomic writes and corruption resistance

The implementation writes payload files and rewrites cache_index.toml, but I did not see a crash-safe transaction pattern, temporary-file-plus-rename flow, or locking. That leaves obvious failure modes:

interrupted writes
partial index updates
two Julia processes writing to the same cache
reads during index rewrite

For 1.0, I would want:

atomic index write via temp file + rename
atomic payload write via temp file + rename
some locking story, at least per-cache lockfile
explicit recovery behavior for damaged index/data mismatch

If this is going to slow performance, opt in.


### Documentation that default cache settings are configured for automated management

- High-latency on cache access due to write-on-read access to track "`last_access_time`" (required for auto-expiration, LRU etc.).
- Locking the cache for updates
- CONSIDER: `last_access_time` opt-in instead of opt-out?

### Size limits and cache pruning

You already track dates and can list/sort assets, which makes this a natural next step:

max cache size
max entry count
prune LRU / oldest / unlabeled
dry-run pruning

## Considering

### Concurrency semantics documented and, ideally, enforced

Because this is file-backed and explicitly shareable across sessions and systems, users will assume some amount of multi-process safety. 1.0 should either support that or state exact limits very plainly.


### Better portability backends for tabular data

DataFrame -> CSV is a good default, but for 1.0 it would be useful to support or plan for:

Arrow
Parquet
configurable serializer/backend by type

CSV is inspectable, but it is not always the best choice for fidelity, performance, or large tables.

### More test coverage

Highest-value missing tests for 1.0 are:

cross-session key stability for @filecache
concurrent writer behavior
interrupted write / recovery behavior
corrupted index handling
serializer/version compatibility behavior
Windows-path and filesystem edge cases
large-cache performance regressions


### Actually using Aqua/JET

The test environment lists Aqua and JET, but from the repo layout I did not see them integrated into CI execution. For 1.0, I would want those checks wired in if they pass cleanly.

### Full doc review

In addition to:

- Ensuring code examples, API, discussion are up to date with the code,
- Document syntax, structure, markup errors are correct
- Language, spelling, grammatical errors are corrected
- All internal links and references are correct or correctly resolved

also:

#### Stronger API-level docs on guarantees and non-guarantees

The docs are fairly extensive, especially for usage patterns and integration, but 1.0 should add a very explicit “contract” section:

what is guaranteed stable
what is best-effort
what is not portable
what happens across Julia/package upgrades
what happens under concurrent access

### CacheAssets.read()/write!()


### get, pop!, get!, and default-return ergonomics

For a dict-like API, these would make the package feel more complete.

### Pattern-based asset operations

Since you already have CacheAssets.ls, natural QoL additions are:

rm(pattern=...)
relabel by predicate
bulk invalidate / bulk move
bulk export selected entries

### Built-in export/archive helpers

Import is present, but end-user ergonomics would improve with:

export cache to zip
export selected assets only
manifest file with metadata summary

