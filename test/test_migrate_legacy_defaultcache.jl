
# Temporary migration tests: v0.1.0 → v0.2.0
# Remove this file and its include() in runtests.jl once v0.1.0 is no longer supported.

@testset "migrate_legacy_defaultcache" begin

    # Helper: create the legacy default path under a given fake home dir and
    # populate it with a small DataCache containing one named entry.
    function _make_legacy_cache(fake_home)
        legacy = joinpath(fake_home, ".cache", "DataCaches", "_DEFAULT")
        mkpath(legacy)
        c = DataCache(legacy)
        write!(c, [1, 2, 3]; label = "legacy_entry")
        return legacy
    end

    @testset "returns false when legacy dir absent" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => joinpath(fake_new, "store")) do
                    @test DataCaches.migrate_legacy_defaultcache() == false
                end
            end
        end
    end

    @testset "wholesale move when new store does not exist" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                legacy = _make_legacy_cache(fake_home)
                new_store = joinpath(fake_new, "store")
                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => new_store) do
                    @test DataCaches.migrate_legacy_defaultcache() == true
                    @test !isdir(legacy)
                    @test isdir(new_store)
                    c = DataCache(new_store)
                    @test haskey(c, "legacy_entry")
                    @test read(c, "legacy_entry") == [1, 2, 3]
                end
            end
        end
    end

    @testset "merge when new store already exists" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                legacy = _make_legacy_cache(fake_home)
                new_store = joinpath(fake_new, "store")
                # Pre-populate the new store with a different entry.
                existing = DataCache(new_store)
                write!(existing, [9, 9]; label = "existing_entry")
                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => new_store) do
                    @test DataCaches.migrate_legacy_defaultcache() == true
                    @test !isdir(legacy)
                    c = DataCache(new_store)
                    @test haskey(c, "legacy_entry")
                    @test haskey(c, "existing_entry")
                    @test read(c, "legacy_entry") == [1, 2, 3]
                    @test read(c, "existing_entry") == [9, 9]
                end
            end
        end
    end

    @testset "conflict=:skip preserves current store entry on collision" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                legacy = joinpath(fake_home, ".cache", "DataCaches", "_DEFAULT")
                mkpath(legacy)
                legacy_c = DataCache(legacy)
                write!(legacy_c, [1, 1]; label = "shared")

                new_store = joinpath(fake_new, "store")
                new_c = DataCache(new_store)
                write!(new_c, [9, 9]; label = "shared")

                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => new_store) do
                    DataCaches.migrate_legacy_defaultcache(; conflict = :skip)
                    c = DataCache(new_store)
                    @test read(c, "shared") == [9, 9]  # current store wins
                end
            end
        end
    end

    @testset "conflict=:overwrite replaces current store entry on collision" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                legacy = joinpath(fake_home, ".cache", "DataCaches", "_DEFAULT")
                mkpath(legacy)
                legacy_c = DataCache(legacy)
                write!(legacy_c, [1, 1]; label = "shared")

                new_store = joinpath(fake_new, "store")
                new_c = DataCache(new_store)
                write!(new_c, [9, 9]; label = "shared")

                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => new_store) do
                    DataCaches.migrate_legacy_defaultcache(; conflict = :overwrite)
                    c = DataCache(new_store)
                    @test read(c, "shared") == [1, 1]  # legacy wins
                end
            end
        end
    end

    @testset "idempotent — second call returns false" begin
        mktempdir() do fake_home
            mktempdir() do fake_new
                _make_legacy_cache(fake_home)
                new_store = joinpath(fake_new, "store")
                withenv("HOME" => fake_home, "DATACACHES_DEFAULT_STORE" => new_store) do
                    @test DataCaches.migrate_legacy_defaultcache() == true
                    @test DataCaches.migrate_legacy_defaultcache() == false
                end
            end
        end
    end

end
