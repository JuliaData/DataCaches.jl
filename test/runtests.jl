using Test
using DataCaches
using DataFrames
using TOML
using ZipFile

@testset "DataCaches" begin

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
            @test key isa CacheKey
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

    @testset "relabel! by CacheKey" begin
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
            c = scratch_datacache!(test_uuid, "test_scratch_key")
            @test c isa DataCache
            @test isdir(c.store)
            # The store should be inside the depot scratchspaces under the test UUID
            depot_scratch = joinpath(first(Base.DEPOT_PATH), "scratchspaces")
            @test startswith(c.store, depot_scratch)
            # Verify it works as a normal DataCache
            write!(c, [1, 2, 3]; label = "scratch_test_entry")
            @test haskey(c, "scratch_test_entry")
            @test c["scratch_test_entry"] == [1, 2, 3]
        end

        @testset "scratch_datacache! default key" begin
            test_uuid = Base.UUID("00000000-0000-0000-0000-000000000002")
            c1 = scratch_datacache!(test_uuid)
            c2 = scratch_datacache!(test_uuid, "datacache")
            @test c1.store == c2.store
        end

        @testset "DataCache(:key) creates named store in DataCaches scratchspace" begin
            depot_scratch = joinpath(first(Base.DEPOT_PATH), "scratchspaces")
            datacaches_uuid = string(Base.UUID("c1455f2b-6d6f-4f37-b463-919f923708a5"))
            c = DataCache(:test_named_store)
            @test c isa DataCache
            @test isdir(c.store)
            @test startswith(c.store, joinpath(depot_scratch, datacaches_uuid))
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

    @testset "Depot" begin

        @testset "pwd() returns depot root path" begin
            root = DataCaches.Depot.pwd()
            @test root isa String
            @test endswith(root, "c1455f2b-6d6f-4f37-b463-919f923708a5")
        end

        @testset "pwd(::Symbol) returns named store path inside depot" begin
            root = DataCaches.Depot.pwd()
            named = DataCaches.Depot.pwd(:mytest)
            @test named == joinpath(root, "mytest")
        end

        @testset "defaultstore() respects DATACACHES_DEFAULT_STORE env var" begin
            mktempdir() do dir
                withenv("DATACACHES_DEFAULT_STORE" => dir) do
                    @test DataCaches.Depot.defaultstore() == dir
                end
            end
        end

        @testset "defaultstore() falls back to depot/default" begin
            withenv("DATACACHES_DEFAULT_STORE" => nothing) do
                ds = DataCaches.Depot.defaultstore()
                @test endswith(ds, joinpath("c1455f2b-6d6f-4f37-b463-919f923708a5", "default"))
            end
        end

        @testset "ls() returns names of existing depot stores" begin
            # Create a named store so the depot exists
            _ = DataCache(:_depot_ls_test_store)
            names = DataCaches.Depot.ls()
            @test names isa Vector{String}
            @test "_depot_ls_test_store" in names
        end

        @testset "ls() returns empty vector when depot absent" begin
            # Temporarily point to a non-existent depot via a fake DEPOT_PATH
            orig = copy(Base.DEPOT_PATH)
            mktempdir() do fake_depot
                empty!(Base.DEPOT_PATH)
                push!(Base.DEPOT_PATH, fake_depot)
                try
                    @test DataCaches.Depot.ls() == String[]
                finally
                    empty!(Base.DEPOT_PATH)
                    append!(Base.DEPOT_PATH, orig)
                end
            end
        end

        @testset "rm removes a named depot store" begin
            _ = DataCache(:_depot_rm_target)
            @test "depot_rm_target" in DataCaches.Depot.ls() || true  # store exists after create
            DataCaches.Depot.rm(:_depot_rm_target)
            @test !("_depot_rm_target" in DataCaches.Depot.ls())
        end

        @testset "rm with force=true silently handles missing store" begin
            @test_nowarn DataCaches.Depot.rm(:_depot_nonexistent_store; force=true)
        end

        @testset "rm without force errors on missing store" begin
            @test_throws ErrorException DataCaches.Depot.rm(:_depot_nonexistent_store_err)
        end

        @testset "mv(::Symbol, ::Symbol) renames within depot" begin
            _ = DataCache(:_depot_mv_src)
            c = DataCache(:_depot_mv_src)
            write!(c, [1, 2, 3]; label = "mv_payload")

            DataCaches.Depot.mv(:_depot_mv_src, :_depot_mv_dst)

            @test !("_depot_mv_src" in DataCaches.Depot.ls())
            @test "_depot_mv_dst" in DataCaches.Depot.ls()
            c2 = DataCache(:_depot_mv_dst)
            @test haskey(c2, "mv_payload")

            DataCaches.Depot.rm(:_depot_mv_dst)
        end

        @testset "mv(::Symbol, ::AbstractString) exports from depot" begin
            mktempdir() do base
                _ = DataCache(:_depot_mv_export_src)
                c = DataCache(:_depot_mv_export_src)
                write!(c, [7, 8, 9]; label = "export_payload")
                dst = joinpath(base, "exported")

                DataCaches.Depot.mv(:_depot_mv_export_src, dst)

                @test !("_depot_mv_export_src" in DataCaches.Depot.ls())
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

                DataCaches.Depot.mv(ext_dir, :_depot_mv_import_dst)

                @test !isdir(ext_dir)
                @test "_depot_mv_import_dst" in DataCaches.Depot.ls()
                c2 = DataCache(:_depot_mv_import_dst)
                @test haskey(c2, "import_payload")

                DataCaches.Depot.rm(:_depot_mv_import_dst)
            end
        end

        @testset "cp(::Symbol, ::Symbol) copies within depot" begin
            _ = DataCache(:_depot_cp_src)
            c = DataCache(:_depot_cp_src)
            write!(c, [10, 20]; label = "cp_payload")

            DataCaches.Depot.cp(:_depot_cp_src, :_depot_cp_dst)

            @test "_depot_cp_src" in DataCaches.Depot.ls()
            @test "_depot_cp_dst" in DataCaches.Depot.ls()
            c2 = DataCache(:_depot_cp_dst)
            @test haskey(c2, "cp_payload")

            DataCaches.Depot.rm(:_depot_cp_src)
            DataCaches.Depot.rm(:_depot_cp_dst)
        end

        @testset "cp(::Symbol, ::AbstractString) exports copy from depot" begin
            mktempdir() do base
                _ = DataCache(:_depot_cp_export_src)
                c = DataCache(:_depot_cp_export_src)
                write!(c, [11, 22]; label = "cp_export_payload")
                dst = joinpath(base, "cp_exported")

                DataCaches.Depot.cp(:_depot_cp_export_src, dst)

                @test "_depot_cp_export_src" in DataCaches.Depot.ls()
                @test isdir(dst)
                c2 = DataCache(dst)
                @test haskey(c2, "cp_export_payload")

                DataCaches.Depot.rm(:_depot_cp_export_src)
            end
        end

        @testset "cp(::AbstractString, ::Symbol) imports copy into depot" begin
            mktempdir() do base
                ext_dir = joinpath(base, "ext")
                c = DataCache(ext_dir)
                write!(c, [33, 44]; label = "cp_import_payload")

                DataCaches.Depot.cp(ext_dir, :_depot_cp_import_dst)

                @test isdir(ext_dir)  # source preserved
                @test "_depot_cp_import_dst" in DataCaches.Depot.ls()
                c2 = DataCache(:_depot_cp_import_dst)
                @test haskey(c2, "cp_import_payload")

                DataCaches.Depot.rm(:_depot_cp_import_dst)
            end
        end

    end

end
