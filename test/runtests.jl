using DataCaches
using Test
using Aqua
using JET

@testset "DataCaches.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(DataCaches)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(DataCaches; target_defined_modules = true)
    end
    # Write your tests here.
end
