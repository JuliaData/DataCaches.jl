using Test
using DataCaches
using DataFrames
using Tables
using TOML

@testset "Serializer dispatch (serializer_for)" begin

    @testset "DataFrame → CSVSerializer" begin
        @test DataCaches.serializer_for(DataFrame(x=[1])) isa DataCaches.CSVSerializer
    end

    @testset "NamedTuple → JSONSerializer" begin
        @test DataCaches.serializer_for((a=1, b="x")) isa DataCaches.JSONSerializer
    end

    @testset "NamedTuple overrides Tables.jl trait" begin
        # NamedTuple IS Tables.jl-compatible, but must dispatch to JSON, not CSV
        nt = (a=1, b=2)
        @test DataCaches.serializer_for(nt) isa DataCaches.JSONSerializer
        @test !(DataCaches.serializer_for(nt) isa DataCaches.CSVSerializer)
    end

    @testset "Vector{NamedTuple} (Tables-compatible, not a NamedTuple) → CSVSerializer" begin
        v = [(a=1, b="x"), (a=2, b="y")]
        @test DataCaches.serializer_for(v) isa DataCaches.CSVSerializer
    end

    @testset "Arbitrary values → OpaqueSerializer" begin
        @test DataCaches.serializer_for([1, 2, 3])      isa DataCaches.OpaqueSerializer
        @test DataCaches.serializer_for(Dict("a" => 1)) isa DataCaches.OpaqueSerializer
        @test DataCaches.serializer_for(42)              isa DataCaches.OpaqueSerializer
        @test DataCaches.serializer_for("hello")         isa DataCaches.OpaqueSerializer
    end

end

@testset "Serializer protocol (format_tag, file_extension)" begin

    @test DataCaches.format_tag(DataCaches.CSVSerializer())    == "csv"
    @test DataCaches.format_tag(DataCaches.JSONSerializer())   == "json"
    @test DataCaches.format_tag(DataCaches.OpaqueSerializer()) == "jls"

    @test DataCaches.file_extension(DataCaches.CSVSerializer())    == ".csv"
    @test DataCaches.file_extension(DataCaches.JSONSerializer())   == ".json"
    @test DataCaches.file_extension(DataCaches.OpaqueSerializer()) == ".jls"

end

@testset "CacheEntry.format field" begin

    @testset "DataFrame → format == \"csv\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            key = write!(c, DataFrame(x=[1, 2]); label="df")
            @test key.format == "csv"
        end
    end

    @testset "NamedTuple → format == \"json\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            key = write!(c, (a=1, b="hello"); label="nt")
            @test key.format == "json"
        end
    end

    @testset "Arbitrary value → format == \"jls\"" begin
        mktempdir() do dir
            c = DataCache(dir)
            key = write!(c, [1, 2, 3]; label="list")
            @test key.format == "jls"
        end
    end

end

@testset "Format persisted to TOML index" begin

    mktempdir() do dir
        c = DataCache(dir)
        write!(c, DataFrame(x=[1]); label="df")
        write!(c, (a=1,);           label="nt")
        write!(c, [1, 2, 3];        label="jls")
        index = TOML.parsefile(joinpath(dir, "cache_index.toml"))
        formats = Dict(e["label"] => e["format"] for e in values(index["entries"]))
        @test formats["df"]  == "csv"
        @test formats["nt"]  == "json"
        @test formats["jls"] == "jls"
    end

    @testset "format survives reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, (x=42,); label="nt")
            c2 = DataCache(dir)
            key = only(filter(k -> k.label == "nt", collect(values(c2._index))))
            @test key.format == "json"
        end
    end

end

@testset "Write/read roundtrips" begin

    @testset "DataFrame (CSV)" begin
        mktempdir() do dir
            c = DataCache(dir)
            df = DataFrame(x=[1, 2, 3], y=["a", "b", "c"])
            write!(c, df; label="df")
            result = Base.read(c, "df")
            @test result isa DataFrame
            @test result == df
            @test endswith(only(values(c._index)).path, ".csv")
        end
    end

    @testset "NamedTuple — primitives (JSON)" begin
        mktempdir() do dir
            c = DataCache(dir)
            nt = (a=1, b="hello", c=true)
            write!(c, nt; label="nt")
            result = Base.read(c, "nt")
            @test result isa NamedTuple
            @test result.a == 1
            @test result.b == "hello"
            @test result.c == true
            @test endswith(only(values(c._index)).path, ".json")
        end
    end

    @testset "NamedTuple — nested (JSON)" begin
        mktempdir() do dir
            c = DataCache(dir)
            nt = (outer=1, inner=(x=2, y=3))
            write!(c, nt; label="nested")
            result = Base.read(c, "nested")
            @test result.outer == 1
            @test result.inner.x == 2
            @test result.inner.y == 3
        end
    end

    @testset "NamedTuple — with array (JSON)" begin
        mktempdir() do dir
            c = DataCache(dir)
            nt = (vals=[1, 2, 3], name="test")
            write!(c, nt; label="arr")
            result = Base.read(c, "arr")
            @test result.vals == [1, 2, 3]
            @test result.name == "test"
        end
    end

    @testset "NamedTuple — Float32 widens to Float64 (documented)" begin
        mktempdir() do dir
            c = DataCache(dir)
            write!(c, (x=Float32(1.5),); label="f32")
            result = Base.read(c, "f32")
            @test result.x ≈ 1.5
            @test result.x isa Float64
        end
    end

    @testset "NamedTuple roundtrip across reload" begin
        mktempdir() do dir
            c1 = DataCache(dir)
            write!(c1, (a=1, b="x"); label="nt")
            c2 = DataCache(dir)
            result = Base.read(c2, "nt")
            @test result.a == 1
            @test result.b == "x"
        end
    end

    @testset "Vector{NamedTuple} Tables.jl → CSV → DataFrame" begin
        mktempdir() do dir
            c = DataCache(dir)
            v = [(a=1, b="x"), (a=2, b="y")]
            write!(c, v; label="tbl")
            result = Base.read(c, "tbl")
            @test result isa DataFrame
            @test nrow(result) == 2
            @test result.a == [1, 2]
        end
    end

    @testset "Opaque arbitrary value (JLS)" begin
        mktempdir() do dir
            c = DataCache(dir)
            val = Dict("key" => [1, 2, 3])
            write!(c, val; label="opaque")
            result = Base.read(c, "opaque")
            @test result == val
            @test endswith(only(values(c._index)).path, ".jls")
        end
    end

end

@testset "Explicit format= override on write!" begin

    @testset "DataFrame forced to JLS" begin
        mktempdir() do dir
            c = DataCache(dir)
            df = DataFrame(x=[1, 2])
            key = write!(c, df; label="forced_jls", format="jls")
            @test key.format == "jls"
            @test endswith(key.path, ".jls")
            result = Base.read(c, "forced_jls")
            @test result isa DataFrame
            @test result == df
        end
    end

    @testset "NamedTuple forced to JLS" begin
        mktempdir() do dir
            c = DataCache(dir)
            nt = (a=1, b=2)
            key = write!(c, nt; label="forced_jls_nt", format="jls")
            @test key.format == "jls"
            result = Base.read(c, "forced_jls_nt")
            @test result == nt
        end
    end

end

@testset "register_serializer! — custom serializer roundtrip" begin
    mktempdir() do dir
        c = DataCache(dir)

        # Minimal custom serializer: store a String as plain text
        struct _TestTextSerializer <: DataCaches.CacheSerializer end
        DataCaches.format_tag(::_TestTextSerializer)            = "txt"
        DataCaches.file_extension(::_TestTextSerializer)        = ".txt"
        DataCaches.write_data(::_TestTextSerializer, p, v)      = Base.write(p, string(v))
        DataCaches.read_data(::_TestTextSerializer, p)          = Base.read(p, String)

        DataCaches.register_serializer!("txt", _TestTextSerializer())

        key = write!(c, "hello world"; label="custom", format="txt")
        @test key.format == "txt"
        @test endswith(key.path, ".txt")
        result = Base.read(c, "custom")
        @test result == "hello world"

        delete!(DataCaches.SERIALIZER_REGISTRY, "txt")
    end
end

@testset "@filecache format dispatch" begin

    @testset "DataFrame-returning function stored as CSV" begin
        mktempdir() do dir
            c = DataCache(dir)
            f = () -> DataFrame(x=[1, 2, 3])
            @filecache c f()
            key = only(values(c._index))
            @test key.format == "csv"
            @test endswith(key.path, ".csv")
        end
    end

    @testset "NamedTuple-returning function stored as JSON" begin
        mktempdir() do dir
            c = DataCache(dir)
            f = () -> (a=1, b="hello")
            @filecache c f()
            key = only(values(c._index))
            @test key.format == "json"
            @test endswith(key.path, ".json")
        end
    end

    @testset "Arbitrary-returning function stored as JLS" begin
        mktempdir() do dir
            c = DataCache(dir)
            f = () -> [1, 2, 3]
            @filecache c f()
            key = only(values(c._index))
            @test key.format == "jls"
            @test endswith(key.path, ".jls")
        end
    end

end

@testset "autocache format dispatch" begin

    @testset "DataFrame-returning function stored as CSV" begin
        mktempdir() do dir
            c = DataCache(dir)
            set_autocaching!(true; cache=c)
            autocache(() -> DataFrame(x=[1]), identity, "ep_csv", (;))
            key = only(values(c._index))
            @test key.format == "csv"
            set_autocaching!(false)
        end
    end

    @testset "NamedTuple-returning function stored as JSON" begin
        mktempdir() do dir
            c = DataCache(dir)
            set_autocaching!(true; cache=c)
            autocache(() -> (a=1, b="x"), identity, "ep_json", (;))
            key = only(values(c._index))
            @test key.format == "json"
            set_autocaching!(false)
        end
    end

end
