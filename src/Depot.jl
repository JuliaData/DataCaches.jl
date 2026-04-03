module Depot

# Same UUID as _DATACACHES_UUID in the parent module — stable package identifier.
const _UUID = Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5")

function _root()
    joinpath(first(Base.DEPOT_PATH), "scratchspaces", string(_UUID))
end

"""
    DataCaches.Depot.pwd() → String
    DataCaches.Depot.pwd(name::Symbol) → String

Return the absolute path to the DataCaches depot root (no argument), or the path
to the named store `name` within the depot (one argument).

The depot root is the scratchspaces directory managed by Scratch.jl for DataCaches.
Depot-managed stores live here as subdirectories and are created via `DataCache(:name)`.

The path is returned whether or not the directory currently exists.

# Examples
```julia
DataCaches.Depot.pwd()          # "~/.julia/scratchspaces/c1455f2b-.../
DataCaches.Depot.pwd(:mydata)   # "~/.julia/scratchspaces/c1455f2b-.../mydata"
```
"""
pwd() = _root()
pwd(name::Symbol) = joinpath(_root(), string(name))

"""
    DataCaches.Depot.defaultstore() → String

Return the absolute path to the default [`DataCache`](@ref) store.

Respects the `DATACACHES_DEFAULT_STORE` environment variable; otherwise returns
the path of the `"default"` named store inside the depot root.

Unlike `DataCache()`, this function does not create the directory.
"""
function defaultstore()
    haskey(ENV, "DATACACHES_DEFAULT_STORE") && return ENV["DATACACHES_DEFAULT_STORE"]
    return joinpath(_root(), "default")
end

"""
    DataCaches.Depot.ls() → Vector{String}

List the names of all [`DataCache`](@ref) stores currently in the depot.

Only lists stores created via `DataCache(:name)` or by placing a directory in the
DataCaches scratchspace. Does not include caches at explicit filesystem paths or those
created by `scratch_datacache!` with a different package UUID.

Returns an empty vector if the depot does not yet exist.
"""
function ls()
    root = _root()
    isdir(root) || return String[]
    return [name for name in readdir(root) if isdir(joinpath(root, name))]
end

"""
    DataCaches.Depot.rm(name::Symbol; force=false)

Remove the named cache store from the depot.

Raises an error if the store does not exist, unless `force=true` (in which case a
missing store is silently ignored).
"""
function rm(name::Symbol; force::Bool = false)
    path = pwd(name)
    if !isdir(path)
        force && return
        error("No depot cache named $(repr(name))")
    end
    Base.rm(path; recursive=true)
end

"""
    DataCaches.Depot.mv(src::Symbol, dst::Symbol)
    DataCaches.Depot.mv(src::Symbol, dst::AbstractString)
    DataCaches.Depot.mv(src::AbstractString, dst::Symbol)

Move a cache store. Three dispatch forms:

  - `mv(src::Symbol, dst::Symbol)` — rename `src` to `dst` within the depot.
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
    Base.mv(src_path, dst_path)
end

function mv(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    Base.mv(src_path, dst_path)
end

function mv(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    Base.mv(src_path, dst_path)
end

"""
    DataCaches.Depot.cp(src::Symbol, dst::Symbol)
    DataCaches.Depot.cp(src::Symbol, dst::AbstractString)
    DataCaches.Depot.cp(src::AbstractString, dst::Symbol)

Copy a cache store. Three dispatch forms:

  - `cp(src::Symbol, dst::Symbol)` — copy depot cache `src` to `dst` within the depot.
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
    Base.cp(src_path, dst_path)
end

function cp(src::Symbol, dst::AbstractString)
    src_path = pwd(src)
    isdir(src_path) || error("No depot cache named $(repr(src))")
    dst_path = abspath(dst)
    isdir(dst_path) && error("Destination already exists: $(repr(dst_path))")
    mkpath(dirname(dst_path))
    Base.cp(src_path, dst_path)
end

function cp(src::AbstractString, dst::Symbol)
    src_path = abspath(src)
    isdir(src_path) || error("Source directory not found: $(repr(src_path))")
    dst_path = pwd(dst)
    isdir(dst_path) && error("Depot cache $(repr(dst)) already exists")
    mkpath(dirname(dst_path))
    Base.cp(src_path, dst_path)
end

end # module Depot
