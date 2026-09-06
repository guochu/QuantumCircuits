@testset "qasm2 roundtrip" begin
    c = Circuit(2)
    push!(c, H(0))
    push!(c, CX(0, 1))
    push!(c, measure([0, 1], c.cregs[1][1:2]))
    s = to_qasm(c; version=2)
    @test occursin("OPENQASM 2.0;", s)
    @test occursin("h q[0];", s)
    @test occursin("cx q[0],q[1];", s)
    @test occursin("measure q[0] -> c[0];", s)
    # roundtrip（两条 measure 语句读回为两个 MeasOp）
    c2 = read_qasm(write_qasm(tempname(), c; version=2))
    @test num_ops(c2) == 4
    @test c2.ops[1] == GateOp(H, [0], [])
    @test c2.ops[2] == GateOp(CX, [0, 1], [])
    # 参数门
    c3 = Circuit(2)
    push!(c3, RX(0.5, 1)); push!(c3, RZZ(1.2, 0, 1)); push!(c3, PHASE(0.3, 1))
    s3 = to_qasm(c3; version=2)
    @test occursin("rx(0.5) q[1];", s3)
    @test occursin("rzz(1.2) q[0],q[1];", s3)
    c4 = read_qasm(s3)
    @test c4.ops[1] == GateOp(RX, [1], [0.5])
    @test c4.ops[2] == GateOp(RZZ, [0, 1], [1.2])
    # u1/u3/cu1 映射
    src = """
    OPENQASM 2.0;
    include "qelib1.inc";
    qreg q[2];
    creg c[2];
    u3(0.1,0.2,0.3) q[0];
    cu1(0.5) q[0],q[1];
    """
    c5 = read_qasm(src)
    @test c5.ops[1].gate === _U3
    @test approxeq(mat(c5.ops[2]), mat(CPHASE, 0.5))
    # gate 定义展开
    src2 = """
    OPENQASM 2.0;
    include "qelib1.inc";
    gate mybell a, b { h a; cx a, b; }
    qreg q[2];
    creg c[2];
    mybell q[0], q[1];
    """
    c6 = read_qasm(src2)
    @test c6.ops == Operation[GateOp(H, [0], []), GateOp(CX, [0, 1], [])]
    # if 语句
    src3 = """
    OPENQASM 2.0;
    include "qelib1.inc";
    qreg q[1];
    creg c[1];
    if (c==3) x q[0];
    """
    c7 = read_qasm(src3)
    @test c7.ops[1] isa IfOp
    @test c7.ops[1].cond == Cond(c7.cregs[1], :(==), 3)
    # 未绑定符号参数不能导出
    c8 = Circuit(1)
    push!(c8, RX(:θ, 1))
    @test_throws ArgumentError to_qasm(c8; version=2)
end

@testset "qasm3 roundtrip" begin
    # Bell + 测量
    c = Circuit(2)
    push!(c, H(0))
    push!(c, CX(0, 1))
    push!(c, measure([0, 1], c.cregs[1][1:2]))
    s = to_qasm(c; version=3)
    @test occursin("OPENQASM 3.0;", s)
    @test occursin("qubit[2] q;", s)
    c2 = read_qasm(s)
    @test c2.ops[1:2] == c.ops[1:2]
    @test c2.ops[3] == MeasOp([0], [c.cregs[1][1]])
    @test c2.ops[4] == MeasOp([1], [c.cregs[1][2]])
    # 修饰符导出/回读
    c3 = Circuit(3)
    push!(c3, ctrl(H(1), 2))
    push!(c3, negctrl(X(1), 0, 2))
    push!(c3, inv(RX(0.4, 1)))
    push!(c3, pow(S(0), 2))
    s3 = to_qasm(c3; version=3)
    @test occursin("ctrl @ h q[2], q[1];", s3)
    c4 = read_qasm(s3)
    @test c4.ops[1] == c3.ops[1]
    @test c4.ops[2] == c3.ops[2]
    @test c4.ops[3] == c3.ops[3]
    @test c4.ops[4].gate isa PowGate && c4.ops[4].gate.k ≈ 2.0
    # 自定义门定义（rzz/iswap/ms）
    c5 = Circuit(3)
    push!(c5, RZZ(0.7, 0, 1))
    push!(c5, ISWAP(1, 2))
    push!(c5, MS(π/4, 0, 0, 1))
    s5 = to_qasm(c5; version=3)
    @test occursin("gate rzz(", s5)
    @test occursin("gate iswap", s5)
    c6 = read_qasm(s5)
    # 自定义门展开为基本门；验证合成矩阵与原线路一致（rzz/iswap/ms 定义数值正确）
    c6f = copy(c6)
    unroll!(c6f)
    @test approxeq(_compose_unitary(c6f, 3), _compose_unitary(c5, 3); tol=1e-9)
    # if-else
    round_i = Circuit(5; cregs=[CReg(:syn, 2)])
    push!(round_i, CX(0, 4))
    push!(round_i, CX(2, 4))
    if_then(round_i, round_i.cregs[1][1] == 1, Circuit([X(1)]); otherwise=Circuit([Z(1)]))
    s7 = to_qasm(round_i; version=3)
    @test occursin("if (syn == 1) {", s7)
    @test occursin("else {", s7)
    c8 = read_qasm(s7)
    @test c8.ops[3] isa IfOp
    @test c8.ops[3].otherwise !== nothing
    # barrier / reset
    c9 = Circuit(2)
    push!(c9, barrier(0, 1))
    push!(c9, reset(0))
    c10 = read_qasm(to_qasm(c9; version=3))
    @test c10.ops[1] == BarrierOp([0, 1])
    @test c10.ops[2] == ResetOp([0])
end
