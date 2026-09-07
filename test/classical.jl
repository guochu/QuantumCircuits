@testset "classical control" begin
    creg = CReg(:syn, 2)
    @test (creg == 1) isa Cond
    @test (creg == 1) == Cond(creg, :(==), 1)
    @test (creg != 1) == Cond(creg, :≠, 1)
    @test (creg ≥ 1) == Cond(creg, :≥, 1)
    @test (creg ≤ 1) == Cond(creg, :≤, 1)
    @test (creg[1] == 1) == Cond(creg, :(==), 1)
    c = Circuit(2)
    then_c = Circuit([X(1)])
    if_then(c, c.cregs[1][1] == 1, then_c)
    @test c.ops[1] isa IfOp
    @test qubits(c.ops[1]) == [1]
    @test length(clbits(c.ops[1])) == 2
    # else 分支
    c2 = Circuit(2)
    if_then(c2, c2.cregs[1] == 0, Circuit([X(1)]); otherwise=Circuit([Z(1)]))
    op = c2.ops[1]
    @test op.otherwise !== nothing
    @test validate(c2) === c2
end
