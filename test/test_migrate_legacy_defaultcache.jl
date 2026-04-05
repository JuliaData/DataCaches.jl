
# Migration tests.
# migrate_legacy_defaultcache : v0.1.0 → v0.2.0  (remove once v0.1.0 unsupported)
# migrate_v020_defaultcache   : v0.2.0 → v0.3.0+

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

@testset "migrate_v020_defaultcache" begin

    # All tests redirect DEPOT_PATH so the v0.2.0 legacy path
    # (<depot>/caches/defaultcache/) is isolated to a temp dir.

    @testset "returns false when v0.2.0 directory absent" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                mktempdir() do new_base
                    withenv("DATACACHES_DEFAULT_STORE" => joinpath(new_base, "store")) do
                        @test DataCaches.migrate_v020_defaultcache() == false
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

    @testset "wholesale move when new store does not exist" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                old_path = joinpath(DataCaches.Depot._caches_dir(), "defaultcache")
                mkpath(old_path)
                old_c = DataCache(old_path)
                write!(old_c, [1, 2, 3]; label = "v020_entry")

                mktempdir() do new_base
                    new_store = joinpath(new_base, "store")
                    withenv("DATACACHES_DEFAULT_STORE" => new_store) do
                        @test DataCaches.migrate_v020_defaultcache() == true
                        @test !isdir(old_path)
                        @test isdir(new_store)
                        c = DataCache(new_store)
                        @test haskey(c, "v020_entry")
                        @test read(c, "v020_entry") == [1, 2, 3]
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

    @testset "merge when new store already exists" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                old_path = joinpath(DataCaches.Depot._caches_dir(), "defaultcache")
                mkpath(old_path)
                old_c = DataCache(old_path)
                write!(old_c, [1, 2, 3]; label = "v020_entry")

                mktempdir() do new_base
                    new_store = joinpath(new_base, "store")
                    existing = DataCache(new_store)
                    write!(existing, [9, 9]; label = "existing_entry")
                    withenv("DATACACHES_DEFAULT_STORE" => new_store) do
                        @test DataCaches.migrate_v020_defaultcache() == true
                        @test !isdir(old_path)
                        c = DataCache(new_store)
                        @test haskey(c, "v020_entry")
                        @test haskey(c, "existing_entry")
                        @test read(c, "v020_entry") == [1, 2, 3]
                        @test read(c, "existing_entry") == [9, 9]
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

    @testset "conflict=:skip preserves new store entry on collision" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                old_path = joinpath(DataCaches.Depot._caches_dir(), "defaultcache")
                mkpath(old_path)
                old_c = DataCache(old_path)
                write!(old_c, [1, 1]; label = "shared")

                mktempdir() do new_base
                    new_store = joinpath(new_base, "store")
                    new_c = DataCache(new_store)
                    write!(new_c, [9, 9]; label = "shared")
                    withenv("DATACACHES_DEFAULT_STORE" => new_store) do
                        DataCaches.migrate_v020_defaultcache(; conflict = :skip)
                        c = DataCache(new_store)
                        @test read(c, "shared") == [9, 9]  # new store wins
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

    @testset "conflict=:overwrite replaces new store entry on collision" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                old_path = joinpath(DataCaches.Depot._caches_dir(), "defaultcache")
                mkpath(old_path)
                old_c = DataCache(old_path)
                write!(old_c, [1, 1]; label = "shared")

                mktempdir() do new_base
                    new_store = joinpath(new_base, "store")
                    new_c = DataCache(new_store)
                    write!(new_c, [9, 9]; label = "shared")
                    withenv("DATACACHES_DEFAULT_STORE" => new_store) do
                        DataCaches.migrate_v020_defaultcache(; conflict = :overwrite)
                        c = DataCache(new_store)
                        @test read(c, "shared") == [1, 1]  # v0.2.0 data wins
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

    @testset "idempotent — second call returns false" begin
        mktempdir() do fake_depot
            _orig = copy(Base.DEPOT_PATH)
            empty!(Base.DEPOT_PATH); push!(Base.DEPOT_PATH, fake_depot)
            try
                old_path = joinpath(DataCaches.Depot._caches_dir(), "defaultcache")
                mkpath(old_path)
                old_c = DataCache(old_path)
                write!(old_c, [7, 8, 9]; label = "idem_entry")

                mktempdir() do new_base
                    new_store = joinpath(new_base, "store")
                    withenv("DATACACHES_DEFAULT_STORE" => new_store) do
                        @test DataCaches.migrate_v020_defaultcache() == true
                        @test DataCaches.migrate_v020_defaultcache() == false
                    end
                end
            finally
                empty!(Base.DEPOT_PATH); append!(Base.DEPOT_PATH, _orig)
            end
        end
    end

end
