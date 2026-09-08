@testset "classical control" begin
    creg = CReg(:syn, 2)
    @test (creg == 1) isa Cond
    @test (creg == 1) == Cond(creg, :(==), 1)
    @test (creg != 1) == Cond(creg, :≠, 1)
    @test (creg ≥ 1) == Cond(creg, :≥, 1)
    @test (creg ≤ 1) == Cond(creg, :≤, 1)
    # 按位条件：c[i] == v 记录位号，与整寄存器比较是不同的 Cond
    @test (creg[1] == 1) == Cond(creg, :(==), 1, 1)
    @test (creg[1] == 1) != Cond(creg, :(==), 1)
    @test (creg[2] ≠ 0) == Cond(creg, :≠, 0, 2)
    @test string(creg == 1) == "syn == 1"
    @test string(creg[1] == 1) == "syn[1] == 1"
    c = Circuit(2)
    then_c = Circuit([X(1)])
    if_then(c, c.cregs[1][1] == 1, then_c)
    @test c.ops[1] isa IfOp
    @test qubits(c.ops[1]) == [1]
    # 按位条件只依赖被比较的那一位
    @test clbits(c.ops[1]) == [c.cregs[1][1]]
    # else 分支
    c2 = Circuit(2)
    if_then(c2, c2.cregs[1] == 0, Circuit([X(1)]); otherwise=Circuit([Z(1)]))
    op = c2.ops[1]
    @test op.otherwise !== nothing
    # 整寄存器条件依赖全部位
    @test clbits(op) == c2.cregs[1][1:2]
    @test validate(c2) === c2
end
