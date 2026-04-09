using Test
using DataCaches
using DataFrames
using TOML

# Helpers that strip the "format" field from every entry in a cache_index.toml,
# simulating a cache that was written before the format field was introduced.
function _strip_format_field!(index_path::String)
    index = TOML.parsefile(index_path)
    for entry in values(index["entries"])
        delete!(entry, "format")
    end
    open(index_path, "w") do io
        TOML.print(io, index)
    end
end

@testset "Legacy migration — TOML entries without format field" begin

    @testset ".csv entry → format inferred as \"csv\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            df = DataFrame(x=[1, 2, 3])
            write!(c, df; label="legacy_csv")
            _strip_format_field!(joinpath(dir, "cache_index.toml"))

            c2 = DataCache(dir)
            result = Base.read(c2, "legacy_csv")
            @test result isa DataFrame
            @test nrow(result) == 3
            key = only(filter(k -> k.label == "legacy_csv", collect(values(c2._index))))
            @test key.format == "csv"
        end
    end

    @testset ".jls entry → format inferred as \"jls\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, [7, 8, 9]; label="legacy_jls")
            _strip_format_field!(joinpath(dir, "cache_index.toml"))

            c2 = DataCache(dir)
            @test Base.read(c2, "legacy_jls") == [7, 8, 9]
            key = only(filter(k -> k.label == "legacy_jls", collect(values(c2._index))))
            @test key.format == "jls"
        end
    end

    @testset ".json entry → format inferred as \"json\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, (a=1, b="x"); label="legacy_json")
            _strip_format_field!(joinpath(dir, "cache_index.toml"))

            c2 = DataCache(dir)
            result = Base.read(c2, "legacy_json")
            @test result.a == 1
            @test result.b == "x"
            key = only(filter(k -> k.label == "legacy_json", collect(values(c2._index))))
            @test key.format == "json"
        end
    end

    @testset "Mixed-format cache — all entries load after format field stripped" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, DataFrame(x=[1]); label="df_entry")
            write!(c, (a=1,);           label="nt_entry")
            write!(c, [1, 2, 3];        label="jls_entry")
            _strip_format_field!(joinpath(dir, "cache_index.toml"))

            c2 = DataCache(dir)
            @test Base.read(c2, "df_entry")  isa DataFrame
            @test Base.read(c2, "nt_entry")  isa NamedTuple
            @test Base.read(c2, "jls_entry") == [1, 2, 3]
        end
    end

    @testset "Legacy reload re-persists inferred format to TOML" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, DataFrame(x=[1]); label="df")
            _strip_format_field!(joinpath(dir, "cache_index.toml"))

            # Loading triggers format inference; any subsequent write! persists new format
            c2 = DataCache(dir)
            _ = Base.read(c2, "df")   # triggers access-time update → _save_index
            index = TOML.parsefile(joinpath(dir, "cache_index.toml"))
            formats = Dict(e["label"] => get(e, "format", nothing)
                           for e in values(index["entries"]))
            @test formats["df"] == "csv"
        end
    end

end
