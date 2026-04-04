module Depot

# Same UUID as _DATACACHES_UUID in the parent module — stable package identifier.
const _UUID = Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5")

function _root()
    joinpath(first(Base.DEPOT_PATH), "scratchspaces", string(_UUID))
end

# Set by DataCaches after include("Depot.jl") to break the forward-reference cycle.
const _datacache_ctor = Ref{Any}(nothing)

_caches_dir()      = joinpath(_root(), "caches")
_local_dir()       = joinpath(_caches_dir(), "local")
_module_dir()      = joinpath(_caches_dir(), "module")
_test_caches_dir() = joinpath(_root(), "test", "caches")

"""
    DataCaches.Depot.pwd() → String
    DataCaches.Depot.pwd(name::Symbol) → String

Return the absolute path to the DataCaches depot root (no argument), or the path
to the named local store `name` within the depot (one argument).

The depot root is the scratchspaces directory managed by Scratch.jl for DataCaches.
Local stores live under `<depot>/caches/local/` and are created via `DataCache(:name)`.

The path is returned whether or not the directory currently exists.

# Examples
```julia
DataCaches.Depot.pwd()          # "~/.julia/scratchspaces/c1455f2b-.../
DataCaches.Depot.pwd(:mydata)   # "~/.julia/scratchspaces/c1455f2b-.../caches/local/mydata"
```
"""
pwd() = _root()
pwd(name::Symbol) = joinpath(_local_dir(), string(name))

"""
    DataCaches.Depot.defaultstore() → String

Return the absolute path to the default [`DataCache`](@ref DataCaches.DataCache) store.

Respects the `DATACACHES_DEFAULT_STORE` environment variable; otherwise returns
the path of the `"defaultcache"` store inside `<depot>/caches/`.

Unlike `DataCache()`, this function does not create the directory.
"""
function defaultstore()
    haskey(ENV, "DATACACHES_DEFAULT_STORE") && return ENV["DATACACHES_DEFAULT_STORE"]
    return joinpath(_caches_dir(), "defaultcache")
end

"""
    DataCaches.Depot.ls(storetype::Symbol = :local) → Vector{Symbol}

List the names of [`DataCache`](@ref DataCaches.DataCache) stores in the depot.

`storetype` controls which category is listed:

- `:local` (default) — named stores created via `DataCache(:name)`, living under
  `<depot>/caches/local/`. Returns store names (e.g. `[:myproject, :mydata]`).
- `:module` — stores created via `scratch_datacache!(uuid, key)`, living under
  `<depot>/caches/module/<uuid>/<key>/`. Returns `Symbol("<uuid>/<key>")` entries.
- `:root` — raw subdirectory listing of the depot root (legacy flat view).

Returns an empty vector if the relevant directory does not yet exist.
"""
function ls(storetype::Symbol = :local)
    if storetype === :local
        dir = _local_dir()
        isdir(dir) || return Symbol[]
        result = [Symbol(n) for n in readdir(dir) if isdir(joinpath(dir, n))]
        @debug "Depot.ls" storetype=:local paths=joinpath.(_local_dir(), string.(result))
        return result
    elseif storetype === :module
        dir = _module_dir()
        isdir(dir) || return Symbol[]
        result = Symbol[]
        for uuid_dir in readdir(dir)
            full_uuid = joinpath(dir, uuid_dir)
            isdir(full_uuid) || continue
            for key in readdir(full_uuid)
                isdir(joinpath(full_uuid, key)) && push!(result, Symbol("$uuid_dir/$key"))
            end
        end
        @debug "Depot.ls" storetype=:module count=length(result)
        return result
    elseif storetype === :root
        root = _root()
        isdir(root) || return Symbol[]
        result = [Symbol(n) for n in readdir(root) if isdir(joinpath(root, n))]
        @debug "Depot.ls" storetype=:root paths=joinpath.(root, string.(result))
        return result
    else
        error("Unknown storetype $(repr(storetype)); expected :local, :module, or :root")
    end
end

"""
    DataCaches.Depot.rm(name::Symbol; force=false)

Remove the named local cache store from the depot.

Raises an error if the store does not exist, unless `force=true` (in which case a
missing store is silently ignored).
"""
function rm(name::Symbol; force::Bool = false)
    path = pwd(name)
    if !isdir(path)
        force && return
        error("No depot cache named $(repr(name))")
    end
    @debug "Depot.rm" path=path
    Base.rm(path; recursive=true)
end

"""
    DataCaches.Depot.mv(src::Symbol, dst::Symbol)
    DataCaches.Depot.mv(src::Symbol, dst::AbstractString)
    DataCaches.Depot.mv(src::AbstractString, dst::Symbol)

Move a cache store. Three dispatch forms:

  - `mv(src::Symbol, dst::Symbol)` — rename `src` to `dst` within the local depot stores.
  - `mv(src::Symbol, dst::AbstractString)` — move named depot cache `src` to filesystem
    path `dst` (export from depot).
  - `mv(src::AbstractString, dst::Symbol)` — move a filesystem directory `src` into
    the depot as `dst` (import into depot).

Raises an error if the source does not exist or the destination already exists.
"""
function mv(src::Symbol, dst::Symbol)
    src_path = pwd(src)
    dst_path = pwd(dst)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    @debug "Depot.mv" src=src_path dst=dst_path
    Base.mv(src_path, dst_path)
end

function mv(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    @debug "Depot.mv" src=src_path dst=dst_path
    Base.mv(src_path, dst_path)
end

function mv(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    @debug "Depot.mv" src=src_path dst=dst_path
    Base.mv(src_path, dst_path)
end

"""
    DataCaches.Depot.cp(src::Symbol, dst::Symbol)
    DataCaches.Depot.cp(src::Symbol, dst::AbstractString)
    DataCaches.Depot.cp(src::AbstractString, dst::Symbol)

Copy a cache store. Three dispatch forms:

  - `cp(src::Symbol, dst::Symbol)` — copy depot cache `src` to `dst` within the local depot stores.
  - `cp(src::Symbol, dst::AbstractString)` — copy named depot cache `src` to filesystem
    path `dst` (export copy from depot).
  - `cp(src::AbstractString, dst::Symbol)` — copy a filesystem directory `src` into
    the depot as `dst` (import copy into depot).

Raises an error if the source does not exist or the destination already exists.
"""
function cp(src::Symbol, dst::Symbol)
    src_path = pwd(src)
    dst_path = pwd(dst)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    @debug "Depot.cp" src=src_path dst=dst_path
    Base.cp(src_path, dst_path)
end

function cp(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    @debug "Depot.cp" src=src_path dst=dst_path
    Base.cp(src_path, dst_path)
end

function cp(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    @debug "Depot.cp" src=src_path dst=dst_path
    Base.cp(src_path, dst_path)
end

"""
    DataCaches.Depot.cleanuptests()

Remove the test cache directory (`<depot>/test/caches/`) and all its contents.
Silently does nothing if the directory does not exist.
"""
function cleanuptests()
    d = _test_caches_dir()
    isdir(d) && Base.rm(d; recursive=true)
end

"""
    DataCaches.Depot.test_datacache!(key::Symbol) → DataCache

Create a [`DataCache`](@ref DataCaches.DataCache) under the depot's test area
(`<depot>/test/caches/<key>/`). Use [`cleanuptests`](@ref) to remove all test caches.
"""
function test_datacache!(key::Symbol)
    store = joinpath(_test_caches_dir(), string(key))
    mkpath(store)
    return _datacache_ctor[](store)
end

end # module Depot
