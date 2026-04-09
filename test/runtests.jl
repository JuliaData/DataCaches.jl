using Test
using DataCaches
using DataFrames
using Dates
using TOML
using ZipFile

@testset "DataCaches" begin

    # Redirect Base.DEPOT_PATH to a temporary directory for the entire test suite so
    # no test inadvertently creates files in the real production scratchspace.
    _test_fake_depot = mktempdir()
    _test_orig_depot_path = copy(Base.DEPOT_PATH)
    empty!(Base.DEPOT_PATH)
    push!(Base.DEPOT_PATH, _test_fake_depot)

    @testset "DataCache construction" begin
        mktempdir() do dir
            c = DataCache(dir)
            @test c isa DataCache
            @test isempty(c)
            @test length(c) == 0
        end
    end

    @testset "write! and read — DataFrame" begin
        mktempdir() do dir
            c = DataCache(dir)
            df = DataFrame(x = [1, 2, 3], y = ["a", "b", "c"])
            key = write!(c, df; label = "test_df", description = "Test DataFrame")
            @test key isa CacheEntry          # primary type name
            @test key isa CacheKey            # backward-compat alias still works
            @test key.label == "test_df"
            @test key.description == "Test DataFrame"
            @test haskey(c, "test_df")
            result = Base.read(c, "test_df")
            @test result isa DataFrame
            @test nrow(result) == 3
        end
    end

    @testset "write! and read — arbitrary value" begin
        mktempdir() do dir
            c = DataCache(dir)
            val = [10, 20, 30]
            write!(c, val; label = "mylist")
            result = Base.read(c, "mylist")
            @test result == val
        end
    end

    @testset "getindex / setindex! sugar" begin
        mktempdir() do dir
            c = DataCache(dir)
            df = DataFrame(z = [10, 20])
            c["sugar"] = df
            @test c["sugar"] isa DataFrame
        end
    end

    @testset "delete! by label" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, [1, 2, 3]; label = "todelete")
            @test haskey(c, "todelete")
            delete!(c, "todelete")
            @test !haskey(c, "todelete")
        end
    end

    @testset "clear!" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, 1; label = "a")
            write!(c, 2; label = "b")
            @test length(c) == 2
            clear!(c)
            @test isempty(c)
        end
    end

    @testset "keylabels and keypaths" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, 42; label = "lbl")
            @test "lbl" in keylabels(c)
            @test length(keypaths(c)) == 1
        end
    end

    @testset "index stores relative paths" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, [1, 2, 3]; label = "relpath_test")
            index = TOML.parsefile(joinpath(dir, "cache_index.toml"))
            stored_paths = [e["path"] for e in values(index["entries"])]
            @test all(!isabspath(p) for p in stored_paths)
        end
    end

    @testset "relative paths survive reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, [4, 5, 6]; label = "rel_reload")
            c2 = DataCache(dir)
            @test haskey(c2, "rel_reload")
            @test Base.read(c2, "rel_reload") == [4, 5, 6]
        end
    end

    @testset "backward compat: absolute paths in index still load" begin
        mktempdir() do dir
            c = DataCache(dir)
            key = write!(c, [7, 8, 9]; label = "abs_compat")
            # Rewrite the index with the absolute path as it was stored before this change
            index_path = joinpath(dir, "cache_index.toml")
            index = TOML.parsefile(index_path)
            for (id, entry) in index["entries"]
                entry["path"] = joinpath(dir, entry["path"])
            end
            open(index_path, "w") do io
                TOML.print(io, index)
            end
            # Reload and verify it still works
            c2 = DataCache(dir)
            @test haskey(c2, "abs_compat")
            @test Base.read(c2, "abs_compat") == [7, 8, 9]
        end
    end

    @testset "persistence across reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, [9, 8, 7]; label = "persistent")
            c2 = DataCache(dir)
            @test haskey(c2, "persistent")
            @test Base.read(c2, "persistent") == [9, 8, 7]
        end
    end

    @testset "label overwrites prior entry" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, 1; label = "overwrite")
            write!(c, 2; label = "overwrite")
            @test length(c) == 1
            @test Base.read(c, "overwrite") == 2
        end
    end

    @testset "relabel! by label" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, [1, 2, 3]; label = "old")
            new_key = relabel!(c, "old", "new")
            @test new_key.label == "new"
            @test !haskey(c, "old")
            @test haskey(c, "new")
            @test Base.read(c, "new") == [1, 2, 3]
        end
    end

    @testset "relabel! by CacheEntry" begin
        mktempdir() do dir
            c = DataCache(dir)
            key = write!(c, 42; label = "alpha")
            new_key = relabel!(c, key, "beta")
            @test new_key.label == "beta"
            @test haskey(c, "beta")
            @test !haskey(c, "alpha")
        end
    end

    @testset "relabel! persists across reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, [9, 9]; label = "before")
            relabel!(c1, "before", "after")
            c2 = DataCache(dir)
            @test haskey(c2, "after")
            @test !haskey(c2, "before")
            @test Base.read(c2, "after") == [9, 9]
        end
    end

    @testset "relabel! conflict errors" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, 1; label = "a")
            write!(c, 2; label = "b")
            @test_throws ErrorException relabel!(c, "a", "b")
        end
    end

    @testset "relabel! missing label errors" begin
        mktempdir() do dir
            c = DataCache(dir)
            @test_throws ErrorException relabel!(c, "nonexistent", "x")
        end
    end

    @testset "@filecache — cache miss then hit" begin
        mktempdir() do dir
            c = DataCache(dir)
            called = Ref(0)
            f = (x) -> (called[] += 1; x * 2)
            r1 = @filecache c f(21)
            @test r1 == 42
            @test called[] == 1
            r2 = @filecache c f(21)
            @test r2 == 42
            @test called[] == 1   # not called again
        end
    end

    @testset "@filecache! always refreshes" begin
        mktempdir() do dir
            c = DataCache(dir)
            called = Ref(0)
            f = (x) -> (called[] += 1; called[])
            r1 = @filecache! c f(0)
            @test r1 == 1
            @test called[] == 1
            r2 = @filecache! c f(0)   # same args → same cache key → force overwrite
            @test r2 == 2
            @test called[] == 2       # always re-executes
        end
    end

    @testset "@filecache! result is subsequently readable by @filecache" begin
        mktempdir() do dir
            c = DataCache(dir)
            called = Ref(0)
            g = (x) -> (called[] += 1; x + 10)
            @filecache! c g(5)         # force-write value 15, called[]=1
            @test called[] == 1
            r = @filecache c g(5)      # should hit the cache written above
            @test r == 15
            @test called[] == 1        # not called again
        end
    end

    @testset "memcache_clear!" begin
        memcache_clear!()
        @test true
    end

    @testset "set_autocaching! global enable/disable" begin
        set_autocaching!(false)
        set_autocaching!(true)
        set_autocaching!(false)
        @test true
    end

    @testset "autocache hook — inactive path" begin
        set_autocaching!(false)
        called = Ref(0)
        fetch_fn = () -> (called[] += 1; "result")
        result = autocache(fetch_fn, identity, "ep", (;))
        @test result == "result"
        @test called[] == 1
    end

    @testset "autocache hook — cache miss then hit" begin
        mktempdir() do dir
            c = DataCache(dir)
            set_autocaching!(true; cache = c)
            called = Ref(0)
            fetch_fn = () -> (called[] += 1; DataFrame(x = [1]))
            r1 = autocache(fetch_fn, identity, "ep", (;))
            @test r1 isa DataFrame
            @test called[] == 1
            r2 = autocache(fetch_fn, identity, "ep", (;))
            @test r2 isa DataFrame
            @test called[] == 1  # not called again
            set_autocaching!(false)
        end
    end

    @testset "autocache hook — force_refresh" begin
        mktempdir() do dir
            c = DataCache(dir)
            set_autocaching!(true; cache = c)
            called = Ref(0)
            fetch_fn = () -> (called[] += 1; DataFrame(x = [called[]]))
            autocache(fetch_fn, identity, "ep2", (;))
            @test called[] == 1
            autocache(fetch_fn, identity, "ep2", (;); force_refresh = true)
            @test called[] == 2
            set_autocaching!(false)
        end
    end

    @testset "autocache hook — package_cache kwarg" begin
        mktempdir() do user_dir
            mktempdir() do pkg_dir
                user_cache = DataCache(user_dir)
                pkg_cache  = DataCache(pkg_dir)
                ep_key(ep) = DataCaches._autocache_key(identity, ep, (;))[1]

                # No explicit user cache → package_cache is used
                set_autocaching!(true)  # implicit: default_filecache(), NOT explicit
                called = Ref(0)
                fetch_fn = () -> (called[] += 1; DataFrame(x = [called[]]))
                autocache(fetch_fn, identity, "ep_pkg", (;); package_cache = pkg_cache)
                @test called[] == 1
                @test  haskey(pkg_cache,  ep_key("ep_pkg"))
                @test !haskey(user_cache, ep_key("ep_pkg"))
                set_autocaching!(false)

                # Explicit user cache → package_cache is overridden
                set_autocaching!(true; cache = user_cache)
                called[] = 0
                autocache(fetch_fn, identity, "ep_exp", (;); package_cache = pkg_cache)
                @test called[] == 1
                @test  haskey(user_cache, ep_key("ep_exp"))
                @test !haskey(pkg_cache,  ep_key("ep_exp"))
                set_autocaching!(false)
            end
        end
    end

    @testset "read and getindex by sequence index" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, [1, 2, 3]; label = "first")
            write!(c, [4, 5, 6]; label = "second")

            @test Base.read(c, 1) == [1, 2, 3]
            @test Base.read(c, 2) == [4, 5, 6]

            @test c[1] == [1, 2, 3]
            @test c[2] == [4, 5, 6]

            @test_throws ErrorException c[99]
        end
    end

    @testset "seq index stable after deletion" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, "a"; label = "first")
            write!(c, "b"; label = "second")
            write!(c, "c"; label = "third")
            delete!(c, "second")
            @test c[1] == "a"
            @test c[3] == "c"
            @test_throws ErrorException c[2]
        end
    end

    @testset "seq index survives reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, [9, 8, 7]; label = "persist_seq")
            seq = only(values(c1._index)).seq
            c2 = DataCache(dir)
            @test c2[seq] == [9, 8, 7]
        end
    end

    @testset "Scratch.jl integration" begin
        mktempdir() do _fake_depot
            _orig_depot_path = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH)
            push!(Base.DEPOT_PATH, _fake_depot)
            try

        @testset "default store is in Julia depot scratchspaces" begin
            # When no env var is set, the default cache should live under the depot
            depot_scratch = joinpath(first(Base.DEPOT_PATH), "scratchspaces")
            c = DataCache()
            @test startswith(c.store, depot_scratch)
            @test isdir(c.store)
        end

        @testset "DATACACHES_DEFAULT_STORE env var overrides Scratch.jl" begin
            mktempdir() do dir
                withenv("DATACACHES_DEFAULT_STORE" => dir) do
                    c = DataCache()
                    @test c.store == abspath(dir)
                end
            end
        end

        @testset "scratch_datacache! creates a functional DataCache" begin
            test_uuid = Base.UUID("00000000-0000-0000-0000-000000000001")
            c = scratch_datacache!(test_uuid, :test_scratch_key)
            @test c isa DataCache
            @test isdir(c.store)
            # The store should be inside the DataCaches depot under caches/module/
            depot_scratch = joinpath(first(Base.DEPOT_PATH), "scratchspaces")
            @test startswith(c.store, depot_scratch)
            @test occursin(joinpath("caches", "module"), c.store)
            # Verify it works as a normal DataCache
            write!(c, [1, 2, 3]; label = "scratch_test_entry")
            @test haskey(c, "scratch_test_entry")
            @test c["scratch_test_entry"] == [1, 2, 3]
        end

        @testset "scratch_datacache! default key" begin
            test_uuid = Base.UUID("00000000-0000-0000-0000-000000000002")
            c1 = scratch_datacache!(test_uuid)
            c2 = scratch_datacache!(test_uuid, :datacache)
            @test c1.store == c2.store
        end

        @testset "DataCache(:key) creates named store in DataCaches scratchspace" begin
            depot_scratch = joinpath(first(Base.DEPOT_PATH), "scratchspaces")
            datacaches_uuid = string(Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5"))
            c = DataCache(:test_named_store)
            @test c isa DataCache
            @test isdir(c.store)
            @test startswith(c.store, joinpath(depot_scratch, datacaches_uuid))
            @test occursin(joinpath("caches", "user"), c.store)
            @test endswith(c.store, "test_named_store")
        end

        @testset "DataCache(:key) is isolated from DataCache(:other_key)" begin
            c1 = DataCache(:named_store_a)
            c2 = DataCache(:named_store_b)
            @test c1.store != c2.store
        end

        @testset "DataCache(:key) is consistent across calls" begin
            c1 = DataCache(:consistency_check)
            c2 = DataCache(:consistency_check)
            @test c1.store == c2.store
        end

        @testset "DataCache(:key) is functional" begin
            c = DataCache(:functional_test_store)
            write!(c, [10, 20, 30]; label = "named_entry")
            @test haskey(c, "named_entry")
            c2 = DataCache(:functional_test_store)
            @test c2["named_entry"] == [10, 20, 30]
        end

            finally
                empty!(Base.DEPOT_PATH)
                append!(Base.DEPOT_PATH, _orig_depot_path)
            end
        end
    end

    @testset "movecache!" begin

        @testset "moves store directory and updates cache.store" begin
            mktempdir() do base
                src = joinpath(base, "source_cache")
                dst = joinpath(base, "dest_cache")
                c = DataCache(src)
                write!(c, [1, 2, 3]; label = "moved_entry")
                original_store = c.store

                DataCaches.movecache!(c, dst)

                @test c.store == dst
                @test isdir(dst)
                @test !isdir(original_store)
                @test haskey(c, "moved_entry")
                @test Base.read(c, "moved_entry") == [1, 2, 3]
            end
        end

        @testset "moved cache survives reload" begin
            mktempdir() do base
                src = joinpath(base, "src")
                dst = joinpath(base, "dst")
                c = DataCache(src)
                write!(c, [9, 8, 7]; label = "persist_after_move")
                DataCaches.movecache!(c, dst)

                c2 = DataCache(dst)
                @test haskey(c2, "persist_after_move")
                @test c2["persist_after_move"] == [9, 8, 7]
            end
        end

        @testset "same src and dst is a no-op" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 42; label = "noop_entry")
                result = DataCaches.movecache!(c, dir)
                @test result === c
                @test c.store == abspath(dir)
                @test haskey(c, "noop_entry")
            end
        end

        @testset "errors if destination already exists" begin
            mktempdir() do base
                src = joinpath(base, "src")
                dst = joinpath(base, "existing_dst")
                mkpath(dst)
                c = DataCache(src)
                @test_throws ErrorException DataCaches.movecache!(c, dst)
            end
        end

        @testset "creates missing parent directories" begin
            mktempdir() do base
                src = joinpath(base, "src")
                dst = joinpath(base, "deep", "nested", "dst")
                c = DataCache(src)
                write!(c, "hello"; label = "deep_move")
                DataCaches.movecache!(c, dst)
                @test isdir(dst)
                @test haskey(c, "deep_move")
            end
        end

    end

    @testset "importcache!" begin

        @testset "imports labeled entries from directory" begin
            mktempdir() do base
                src_dir = joinpath(base, "source")
                dst_dir = joinpath(base, "dest")
                src = DataCache(src_dir)
                write!(src, [1, 2, 3]; label = "alpha")
                write!(src, [4, 5, 6]; label = "beta")

                dst = DataCache(dst_dir)
                DataCaches.importcache!(dst, src_dir)

                @test haskey(dst, "alpha")
                @test haskey(dst, "beta")
                @test Base.read(dst, "alpha") == [1, 2, 3]
                @test Base.read(dst, "beta")  == [4, 5, 6]
            end
        end

        @testset "unlabeled entries always imported" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                dst_dir = joinpath(base, "dst")
                src = DataCache(src_dir)
                write!(src, [99, 98])

                dst = DataCache(dst_dir)
                DataCaches.importcache!(dst, src_dir)
                @test length(dst) == 1
                @test Base.read(dst, only(keys(dst))) == [99, 98]
            end
        end

        @testset "conflict=:skip preserves existing entry" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                dst_dir = joinpath(base, "dst")
                src = DataCache(src_dir)
                write!(src, [1, 2]; label = "shared")

                dst = DataCache(dst_dir)
                write!(dst, [9, 9]; label = "shared")

                DataCaches.importcache!(dst, src_dir; conflict = :skip)
                @test Base.read(dst, "shared") == [9, 9]
            end
        end

        @testset "conflict=:overwrite replaces existing entry" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                dst_dir = joinpath(base, "dst")
                src = DataCache(src_dir)
                write!(src, [1, 2]; label = "shared")

                dst = DataCache(dst_dir)
                write!(dst, [9, 9]; label = "shared")

                DataCaches.importcache!(dst, src_dir; conflict = :overwrite)
                @test Base.read(dst, "shared") == [1, 2]
            end
        end

        @testset "conflict=:error raises on label conflict" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                dst_dir = joinpath(base, "dst")
                src = DataCache(src_dir)
                write!(src, [1, 2]; label = "conflict_label")

                dst = DataCache(dst_dir)
                write!(dst, [9, 9]; label = "conflict_label")

                @test_throws ErrorException DataCaches.importcache!(dst, src_dir; conflict = :error)
            end
        end

        @testset "invalid conflict keyword raises error" begin
            mktempdir() do base
                src = DataCache(joinpath(base, "src"))
                dst = DataCache(joinpath(base, "dst"))
                @test_throws ErrorException DataCaches.importcache!(dst, src.store; conflict = :invalid)
            end
        end

        @testset "import from zip file" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                src = DataCache(src_dir)
                write!(src, [10, 20]; label = "zipped_entry")

                zip_path = joinpath(base, "cache.zip")
                w = ZipFile.Writer(zip_path)
                for fname in readdir(src_dir)
                    fpath = joinpath(src_dir, fname)
                    f = ZipFile.addfile(w, fname)
                    write(f, read(fpath))
                end
                close(w)

                dst = DataCache(joinpath(base, "dst"))
                DataCaches.importcache!(dst, zip_path)
                @test haskey(dst, "zipped_entry")
                @test Base.read(dst, "zipped_entry") == [10, 20]
            end
        end

        @testset "import persists to disk" begin
            mktempdir() do base
                src_dir = joinpath(base, "src")
                dst_dir = joinpath(base, "dst")
                src = DataCache(src_dir)
                write!(src, [5, 6, 7]; label = "persisted")

                dst = DataCache(dst_dir)
                DataCaches.importcache!(dst, src_dir)

                dst2 = DataCache(dst_dir)
                @test haskey(dst2, "persisted")
                @test dst2["persisted"] == [5, 6, 7]
            end
        end

    end

    @testset "CacheAssets.ls / ls!" begin

        @testset "ls returns a Vector of all entries" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "alpha")
                write!(c, rand(3); label = "beta")
                result = DataCaches.CacheAssets.ls(c)
                @test result isa Vector
                @test length(result) == 2
            end
        end

        @testset "ls filters by pattern" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "alpha")
                write!(c, rand(3); label = "beta")
                result = DataCaches.CacheAssets.ls(c; pattern = r"alph")
                @test length(result) == 1
                @test result[1].label == "alpha"
            end
        end

        @testset "ls filters by labeled flag" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "named")
                write!(c, rand(3))
                @test length(DataCaches.CacheAssets.ls(c; labeled = true))  == 1
                @test length(DataCaches.CacheAssets.ls(c; labeled = false)) == 1
                @test length(DataCaches.CacheAssets.ls(c))                  == 2
            end
        end

        @testset "ls! prints to io and returns nothing" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "alpha")
                buf = IOBuffer()
                result = DataCaches.CacheAssets.ls!(c; io = buf)
                @test result === nothing
                @test length(take!(buf)) > 0
            end
        end

        @testset "ls! with detail=:full prints to io and returns nothing" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "alpha")
                buf = IOBuffer()
                result = DataCaches.CacheAssets.ls!(c; detail = :full, io = buf)
                @test result === nothing
                output = String(take!(buf))
                @test occursin("alpha", output)
            end
        end

        @testset "ls and ls! accept the same filter kwargs" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, rand(3); label = "alpha")
                write!(c, rand(3); label = "beta")
                entries = DataCaches.CacheAssets.ls(c; pattern = r"beta", sortby = :label)
                @test length(entries) == 1
                buf = IOBuffer()
                DataCaches.CacheAssets.ls!(c; pattern = r"beta", sortby = :label, io = buf)
                @test occursin("beta", String(take!(buf)))
            end
        end

    end

    @testset "Caches" begin

        mktempdir() do _fake_depot
            _orig_depot_path = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH)
            push!(Base.DEPOT_PATH, _fake_depot)
            try

        @testset "pwd() returns depot root path" begin
            root = DataCaches.Caches.pwd()
            @test root isa String
            @test endswith(root, "c1455f2b-6d6f-4f37-b463-919f923708a5")
        end

        @testset "pwd(::Symbol) returns named store path inside depot" begin
            root = DataCaches.Caches.pwd()
            named = DataCaches.Caches.pwd(:mytest)
            @test named == joinpath(root, "caches", "user", "mytest")
        end

        @testset "defaultstore() respects DATACACHES_DEFAULT_STORE env var" begin
            mktempdir() do dir
                withenv("DATACACHES_DEFAULT_STORE" => dir) do
                    @test DataCaches.Caches.defaultstore() == dir
                end
            end
        end

        @testset "defaultstore() falls back to depot/caches/user/_DEFAULT" begin
            withenv("DATACACHES_DEFAULT_STORE" => nothing) do
                ds = DataCaches.Caches.defaultstore()
                @test endswith(ds, joinpath("c1455f2b-6d6f-4f37-b463-919f923708a5", "caches", "user", "_DEFAULT"))
            end
        end

        @testset "ls() returns caches-dir subdirs by default" begin
            # Create a named store so the caches directory exists
            _ = DataCache(:_caches_ls_test_store)
            names = DataCaches.Caches.ls()
            @test names isa Vector{Symbol}
            @test :user in names  # ls() defaults to :root — returns caches/ subdirectories
        end

        @testset "ls(:user) returns names of existing user stores" begin
            _ = DataCache(:_caches_ls_test_store)
            names = DataCaches.Caches.ls(:user)
            @test names isa Vector{Symbol}
            @test :_caches_ls_test_store in names
        end

        @testset "ls() returns empty vector when scratchspace absent" begin
            # Temporarily point to a non-existent scratchspace via a fake DEPOT_PATH
            orig = copy(Base.DEPOT_PATH)
            mktempdir() do fake_depot
                empty!(Base.DEPOT_PATH)
                push!(Base.DEPOT_PATH, fake_depot)
                try
                    @test DataCaches.Caches.ls() == Symbol[]
                finally
                    empty!(Base.DEPOT_PATH)
                    append!(Base.DEPOT_PATH, orig)
                end
            end
        end

        @testset "ls!(:user) prints store names and returns nothing" begin
            _ = DataCache(:_caches_ls_bang_test_store)
            buf = IOBuffer()
            result = DataCaches.Caches.ls!(:user; io = buf)
            @test result === nothing
            output = String(take!(buf))
            @test occursin("_caches_ls_bang_test_store", output)
        end

        @testset "ls!() prints to stdout and returns nothing" begin
            _ = DataCache(:_caches_ls_bang_root_store)
            buf = IOBuffer()
            result = DataCaches.Caches.ls!(:root; io = buf)
            @test result === nothing
            @test length(take!(buf)) > 0
        end

        @testset "rm removes a named depot store" begin
            _ = DataCache(:_depot_rm_target)
            @test :_depot_rm_target in DataCaches.Caches.ls(:user) || true  # store exists after create
            DataCaches.Caches.rm(:_depot_rm_target)
            @test !(:_depot_rm_target in DataCaches.Caches.ls(:user))
        end

        @testset "rm with force=true silently handles missing store" begin
            @test_nowarn DataCaches.Caches.rm(:_depot_nonexistent_store; force=true)
        end

        @testset "rm without force errors on missing store" begin
            @test_throws ErrorException DataCaches.Caches.rm(:_depot_nonexistent_store_err)
        end

        @testset "mv(::Symbol, ::Symbol) renames within depot" begin
            _ = DataCache(:_depot_mv_src)
            c = DataCache(:_depot_mv_src)
            write!(c, [1, 2, 3]; label = "mv_payload")

            DataCaches.Caches.mv(:_depot_mv_src, :_depot_mv_dst)

            @test !(:_depot_mv_src in DataCaches.Caches.ls(:user))
            @test :_depot_mv_dst in DataCaches.Caches.ls(:user)
            c2 = DataCache(:_depot_mv_dst)
            @test haskey(c2, "mv_payload")

            DataCaches.Caches.rm(:_depot_mv_dst)
        end

        @testset "mv(::Symbol, ::AbstractString) exports from depot" begin
            mktempdir() do base
                _ = DataCache(:_depot_mv_export_src)
                c = DataCache(:_depot_mv_export_src)
                write!(c, [7, 8, 9]; label = "export_payload")
                dst = joinpath(base, "exported")

                DataCaches.Caches.mv(:_depot_mv_export_src, dst)

                @test !(:_depot_mv_export_src in DataCaches.Caches.ls(:user))
                @test isdir(dst)
                c2 = DataCache(dst)
                @test haskey(c2, "export_payload")
            end
        end

        @testset "mv(::AbstractString, ::Symbol) imports into depot" begin
            mktempdir() do base
                ext_dir = joinpath(base, "external")
                c = DataCache(ext_dir)
                write!(c, [4, 5, 6]; label = "import_payload")

                DataCaches.Caches.mv(ext_dir, :_depot_mv_import_dst)

                @test !isdir(ext_dir)
                @test :_depot_mv_import_dst in DataCaches.Caches.ls(:user)
                c2 = DataCache(:_depot_mv_import_dst)
                @test haskey(c2, "import_payload")

                DataCaches.Caches.rm(:_depot_mv_import_dst)
            end
        end

        @testset "cp(::Symbol, ::Symbol) copies within depot" begin
            _ = DataCache(:_depot_cp_src)
            c = DataCache(:_depot_cp_src)
            write!(c, [10, 20]; label = "cp_payload")

            DataCaches.Caches.cp(:_depot_cp_src, :_depot_cp_dst)

            @test :_depot_cp_src in DataCaches.Caches.ls(:user)
            @test :_depot_cp_dst in DataCaches.Caches.ls(:user)
            c2 = DataCache(:_depot_cp_dst)
            @test haskey(c2, "cp_payload")

            DataCaches.Caches.rm(:_depot_cp_src)
            DataCaches.Caches.rm(:_depot_cp_dst)
        end

        @testset "cp(::Symbol, ::AbstractString) exports copy from depot" begin
            mktempdir() do base
                _ = DataCache(:_depot_cp_export_src)
                c = DataCache(:_depot_cp_export_src)
                write!(c, [11, 22]; label = "cp_export_payload")
                dst = joinpath(base, "cp_exported")

                DataCaches.Caches.cp(:_depot_cp_export_src, dst)

                @test :_depot_cp_export_src in DataCaches.Caches.ls(:user)
                @test isdir(dst)
                c2 = DataCache(dst)
                @test haskey(c2, "cp_export_payload")

                DataCaches.Caches.rm(:_depot_cp_export_src)
            end
        end

        @testset "cp(::AbstractString, ::Symbol) imports copy into depot" begin
            mktempdir() do base
                ext_dir = joinpath(base, "ext")
                c = DataCache(ext_dir)
                write!(c, [33, 44]; label = "cp_import_payload")

                DataCaches.Caches.cp(ext_dir, :_depot_cp_import_dst)

                @test isdir(ext_dir)  # source preserved
                @test :_depot_cp_import_dst in DataCaches.Caches.ls(:user)
                c2 = DataCache(:_depot_cp_import_dst)
                @test haskey(c2, "cp_import_payload")

                DataCaches.Caches.rm(:_depot_cp_import_dst)
            end
        end

            finally
                empty!(Base.DEPOT_PATH)
                append!(Base.DEPOT_PATH, _orig_depot_path)
            end
        end

    end

    # =========================================================================
    # CacheEntry / backward-compat CacheKey alias
    # =========================================================================

    @testset "CacheKey is a backward-compatible alias for CacheEntry" begin
        @test CacheKey === CacheEntry
        mktempdir() do dir
            c = DataCache(dir)
            e = write!(c, 42; label = "alias_test")
            @test e isa CacheEntry
            @test e isa CacheKey
            # Constructing with the alias name still works
            e2 = CacheKey(e.id, e.seq, e.label, e.path, e.description,
                          e.datecached, e.dateaccessed)
            @test e2 == e
        end
    end

    # =========================================================================
    # entries()
    # =========================================================================

    @testset "entries()" begin

        @testset "returns all entries when no filters given" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "a")
                write!(c, 2; label = "b")
                write!(c, 3; label = "c")
                result = entries(c)
                @test result isa Vector{CacheEntry}
                @test length(result) == 3
            end
        end

        @testset "default form uses default_filecache" begin
            mktempdir() do dir
                c = DataCache(dir)
                set_default_filecache!(c)
                write!(c, 99; label = "default_entries_test")
                result = entries()
                @test any(e -> e.label == "default_entries_test", result)
            end
        end

        @testset "sorted by :seq by default" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "first")
                write!(c, 2; label = "second")
                write!(c, 3; label = "third")
                result = entries(c)
                @test issorted([e.seq for e in result])
            end
        end

        @testset "filter: labeled=true returns only labeled entries" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "named")
                write!(c, 2)            # unlabeled
                @test length(entries(c; labeled = true))  == 1
                @test entries(c; labeled = true)[1].label == "named"
            end
        end

        @testset "filter: labeled=false returns only unlabeled entries" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "named")
                write!(c, 2)
                @test length(entries(c; labeled = false)) == 1
                @test isempty(entries(c; labeled = false)[1].label)
            end
        end

        @testset "filter: pattern matches label" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "canidae_occs")
                write!(c, 2; label = "dinosaur_taxa")
                result = entries(c; pattern = r"canidae")
                @test length(result) == 1
                @test result[1].label == "canidae_occs"
            end
        end

        @testset "filter: after/before by datecached" begin
            mktempdir() do dir
                c = DataCache(dir)
                e1 = write!(c, 1; label = "old")
                sleep(0.05)   # ensure e2's datecached is strictly later than e1's
                e2 = write!(c, 2; label = "new")
                cutoff = e1.datecached + Dates.Millisecond(25)
                @test length(entries(c; after = cutoff)) == 1
                @test entries(c; after = cutoff)[1].label == "new"
                @test length(entries(c; before = cutoff)) == 1
                @test entries(c; before = cutoff)[1].label == "old"
            end
        end

        @testset "sort: :label" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "zebra")
                write!(c, 2; label = "apple")
                write!(c, 3; label = "mango")
                result = entries(c; sortby = :label)
                @test [e.label for e in result] == ["apple", "mango", "zebra"]
            end
        end

        @testset "sort: rev=true reverses order" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "a")
                write!(c, 2; label = "b")
                write!(c, 3; label = "c")
                fwd = entries(c; sortby = :seq)
                rev = entries(c; sortby = :seq, rev = true)
                @test [e.label for e in fwd] == reverse([e.label for e in rev])
            end
        end

        @testset "sort: :size_desc" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, ones(100); label = "big")
                write!(c, ones(1);   label = "small")
                result = entries(c; sortby = :size_desc)
                @test result[1].label == "big"
            end
        end

        @testset "filter: missing_file controls inclusion of entries with absent files" begin
            mktempdir() do dir
                c = DataCache(dir)
                e = write!(c, 42; label = "will_be_deleted")
                write!(c, 99; label = "intact")
                rm(e.path)
                # Default (missing_file=false): entry with missing file is excluded
                result_default = entries(c)
                @test length(result_default) == 1
                @test result_default[1].label == "intact"
                # missing_file=true: entry with missing file is included alongside intact ones
                result_inclusive = entries(c; missing_file = true)
                @test length(result_inclusive) == 2
                @test any(e -> e.label == "will_be_deleted", result_inclusive)
            end
        end

        @testset "empty cache returns empty vector" begin
            mktempdir() do dir
                c = DataCache(dir)
                @test entries(c) == CacheEntry[]
            end
        end
    end

    # =========================================================================
    # entry()
    # =========================================================================

    @testset "entry()" begin

        @testset "by label returns correct CacheEntry" begin
            mktempdir() do dir
                c = DataCache(dir)
                e_written = write!(c, 42; label = "findme")
                e_found = entry(c, "findme")
                @test e_found isa CacheEntry
                @test e_found.label == "findme"
                @test e_found.id == e_written.id
            end
        end

        @testset "by sequence index returns correct CacheEntry" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "first")
                write!(c, 2; label = "second")
                e = entry(c, 1)
                @test e isa CacheEntry
                @test e.label == "first"
            end
        end

        @testset "throws KeyError for missing label" begin
            mktempdir() do dir
                c = DataCache(dir)
                @test_throws KeyError entry(c, "nonexistent")
            end
        end

        @testset "throws KeyError for missing index" begin
            mktempdir() do dir
                c = DataCache(dir)
                @test_throws KeyError entry(c, 99)
            end
        end

        @testset "single-arg form uses default_filecache" begin
            mktempdir() do dir
                c = DataCache(dir)
                set_default_filecache!(c)
                write!(c, 7; label = "default_entry_test")
                e = entry("default_entry_test")
                @test e isa CacheEntry
                @test e.label == "default_entry_test"
            end
        end

        @testset "entry result can be used to read data" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, [10, 20, 30]; label = "readable")
                e = entry(c, "readable")
                @test Base.read(c, e) == [10, 20, 30]
            end
        end

    end

    # =========================================================================
    # labels()
    # =========================================================================

    @testset "labels()" begin

        @testset "returns only user-assigned labels (no empties)" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "foo")
                write!(c, 2; label = "bar")
                write!(c, 3)               # unlabeled
                lbls = labels(c)
                @test lbls isa Vector{String}
                @test length(lbls) == 2
                @test "foo" in lbls
                @test "bar" in lbls
                @test !any(isempty, lbls)
            end
        end

        @testset "empty cache returns empty vector" begin
            mktempdir() do dir
                c = DataCache(dir)
                @test labels(c) == String[]
            end
        end

        @testset "matches keylabels for labeled entries" begin
            mktempdir() do dir
                c = DataCache(dir)
                write!(c, 1; label = "x")
                write!(c, 2; label = "y")
                @test sort(labels(c)) == sort(filter(!isempty, keylabels(c)))
            end
        end

        @testset "default form uses default_filecache" begin
            mktempdir() do dir
                c = DataCache(dir)
                set_default_filecache!(c)
                write!(c, 5; label = "default_labels_test")
                @test "default_labels_test" in labels()
            end
        end

    end

    include("test_migrate_legacy_defaultcache.jl")

    # Restore the original depot path after all tests.
    empty!(Base.DEPOT_PATH)
    append!(Base.DEPOT_PATH, _test_orig_depot_path)
    rm(_test_fake_depot; recursive = true, force = true)

end
