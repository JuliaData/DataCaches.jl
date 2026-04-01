using Test
using DataCaches
using DataFrames
using TOML

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

end
