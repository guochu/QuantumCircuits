@testset "bits" begin
    q = QReg(:q, 4)
    @test q[1] == Qubit(0)
    @test q[4] == Qubit(3)
    @test q[1:2] == [Qubit(0), Qubit(1)]
    @test_throws BoundsError q[5]
    c = CReg(:c, 2)
    @test c[1] isa ClbitRef
    @test c[1].index == 1
    @test length(c) == 2
    @test c[1:2] == [c[1], c[2]]
end

@testset "params" begin
    φ = params(:φ, 3)
    @test φ[1] == Param(Symbol("φ[1]"))
    @test φ[2] == Param(Symbol("φ[2]"))
    @test collect(φ) == [φ[1], φ[2], φ[3]]
    @test length(φ) == 3
end
