module Caches

# Same UUID as _DATACACHES_UUID in the parent module — stable package identifier.
const _UUID = Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5")

function _root()
    return joinpath(first(Base.DEPOT_PATH), "scratchspaces", string(_UUID))
end

# Set by DataCaches after include("Caches.jl") to break the forward-reference cycle.
const _datacache_ctor = Ref{Any}(nothing)

_caches_dir() = joinpath(_root(), "caches")
_user_dir() = joinpath(_caches_dir(), "user")
_module_dir() = joinpath(_caches_dir(), "module")

"""
    DataCaches.Caches.pwd() → String
    DataCaches.Caches.pwd(name::Symbol) → String

Return the absolute path to the DataCaches scratchspace root (no argument), or the path
to the named user store `name` within the scratchspace (one argument).

The root is the scratchspaces directory managed by Scratch.jl for DataCaches.
User stores live under `<root>/caches/user/` and are created via `DataCache(:name)`.

The path is returned whether or not the directory currently exists.

# Examples
```julia
DataCaches.Caches.pwd()          # "~/.julia/scratchspaces/c1455f2b-.../
DataCaches.Caches.pwd(:mydata)   # "~/.julia/scratchspaces/c1455f2b-.../caches/user/mydata"
```
"""
pwd() = _root()
pwd(name::Symbol) = joinpath(_user_dir(), string(name))

"""
    DataCaches.Caches.autocachestore() → String

Return the absolute path to the active autocache store.

Respects the `DATACACHES_AUTOCACHE_STORE` environment variable; otherwise returns
the path of the `_AUTOCACHE` store inside `<root>/caches/user/`.

Unlike [`active_autocache`](@ref DataCaches.active_autocache), this function does
not create the directory.
"""
function autocachestore()
    haskey(ENV, "DATACACHES_AUTOCACHE_STORE") && return ENV["DATACACHES_AUTOCACHE_STORE"]
    return joinpath(_user_dir(), "_AUTOCACHE")
end

"""
    DataCaches.Caches.ls(storetype::Symbol = :root) → Vector{Symbol}

List the names of store categories or stores in the DataCaches cache directory.

`storetype` controls which category is listed:

- `:root` (default) — subdirectory listing of the caches root directory
  (e.g. `[:user, :module]`).
- `:user` — named stores created via `DataCache(:name)`, living under
  `<caches>/user/`. Returns store names (e.g. `[:myproject, :mydata]`).
- `:module` — stores created via `scratch_datacache!(uuid, key)`, living under
  `<caches>/module/<uuid>/<key>/`. Returns `Symbol("<uuid>/<key>")` entries.

Returns an empty vector if the relevant directory does not yet exist.

See also [`ls!`](@ref) for a display-oriented variant that prints to an `IO` stream.
"""
function ls(storetype::Symbol = :root)
    if storetype === :user
        dir = _user_dir()
        isdir(dir) || return Symbol[]
        result = [Symbol(n) for n in readdir(dir) if isdir(joinpath(dir, n))]
        @debug "Caches.ls" storetype = :user paths = joinpath.(_user_dir(), string.(result))
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
        @debug "Caches.ls" storetype = :module count = length(result)
        return result
    elseif storetype === :root
        dir = _caches_dir()
        isdir(dir) || return Symbol[]
        result = [Symbol(n) for n in readdir(dir) if isdir(joinpath(dir, n))]
        @debug "Caches.ls" storetype = :root paths = joinpath.(dir, string.(result))
        return result
    else
        error("Unknown storetype $(repr(storetype)); expected :root, :user, or :module")
    end
end

"""
    DataCaches.Caches.ls!(storetype::Symbol = :root; io::IO = stdout) → nothing

Print the names of store categories or stores in the DataCaches cache directory to `io`.

Accepts the same `storetype` argument as [`ls`](@ref). Returns `nothing`.
"""
function ls!(storetype::Symbol = :root; io::IO = stdout)
    names = ls(storetype)
    if isempty(names)
        println(io, "(no stores)")
    else
        for n in names
            println(io, n)
        end
    end
    return nothing
end

"""
    DataCaches.Caches.rm(name::Symbol; force=false)

Remove the named local cache store from the depot.

Raises an error if the store does not exist, unless `force=true` (in which case a
missing store is silently ignored).
"""
function rm(name::Symbol; force::Bool = false)
    path = pwd(name)
    if !isdir(path)
        force && return
        error("No cache named $(repr(name))")
    end
    @debug "Caches.rm" path = path
    return Base.rm(path; recursive = true)
end

"""
    DataCaches.Caches.mv(src::Symbol, dst::Symbol)
    DataCaches.Caches.mv(src::Symbol, dst::AbstractString)
    DataCaches.Caches.mv(src::AbstractString, dst::Symbol)

Move a cache store. Three dispatch forms:

  - `mv(src::Symbol, dst::Symbol)` — rename `src` to `dst` within the user depot stores.
  - `mv(src::Symbol, dst::AbstractString)` — move named depot cache `src` to filesystem
    path `dst` (export from depot).
  - `mv(src::AbstractString, dst::Symbol)` — move a filesystem directory `src` into
    the depot as `dst` (import into depot).

Raises an error if the source does not exist or the destination already exists.
"""
function mv(src::Symbol, dst::Symbol)
    src_path = pwd(src)
    dst_path = pwd(dst)
    isdir(src_path) || error("No cache named $(repr(src))")
    isdir(dst_path) && error("Cache $(repr(dst)) already exists")
    @debug "Caches.mv" src = src_path dst = dst_path
    return Base.mv(src_path, dst_path)
end

function mv(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    @debug "Caches.mv" src = src_path dst = dst_path
    return Base.mv(src_path, dst_path)
end

function mv(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    @debug "Caches.mv" src = src_path dst = dst_path
    return Base.mv(src_path, dst_path)
end

"""
    DataCaches.Caches.cp(src::Symbol, dst::Symbol)
    DataCaches.Caches.cp(src::Symbol, dst::AbstractString)
    DataCaches.Caches.cp(src::AbstractString, dst::Symbol)

Copy a cache store. Three dispatch forms:

  - `cp(src::Symbol, dst::Symbol)` — copy depot cache `src` to `dst` within the user depot stores.
  - `cp(src::Symbol, dst::AbstractString)` — copy named depot cache `src` to filesystem
    path `dst` (export copy from depot).
  - `cp(src::AbstractString, dst::Symbol)` — copy a filesystem directory `src` into
    the depot as `dst` (import copy into depot).

Raises an error if the source does not exist or the destination already exists.
"""
function cp(src::Symbol, dst::Symbol)
    src_path = pwd(src)
    dst_path = pwd(dst)
    isdir(src_path) || error("No cache named $(repr(src))")
    isdir(dst_path) && error("Cache $(repr(dst)) already exists")
    @debug "Caches.cp" src = src_path dst = dst_path
    return Base.cp(src_path, dst_path)
end

function cp(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    @debug "Caches.cp" src = src_path dst = dst_path
    return Base.cp(src_path, dst_path)
end

function cp(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    @debug "Caches.cp" src = src_path dst = dst_path
    return Base.cp(src_path, dst_path)
end

end # module Caches
