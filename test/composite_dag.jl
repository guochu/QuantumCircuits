@testset "composite" begin
    # UserGate：显式矩阵
    ug = usergate(:mygate, [0 1; 1 0])
    @test ug isa UserGate && nqubits(ug) == 1
    @test ug(3) == GateOp(ug, [3], [])
    @test approxeq(mat(ug), mat(X))
    @test_throws ArgumentError usergate(:bad, [1 0; 0 2])
    # UserGate：子线路定义（延迟分解）
    def = Circuit([H(0), CX(0, 1)])
    bell = UserGate(:bell, 2, def)
    @test nqubits(bell) == 2 && num_params(bell) == 0
    m = mat(bell)
    expected = _embed(mat(CX), [0, 1], 2) * _embed(mat(H), [0], 2)   # 先 H 后 CX
    @test approxeq(m, expected)
    # 参数化 UserGate
    defp = Circuit([RX(:θ, 0), RX(Param(:θ), 1)])    # 权重共享
    g2 = UserGate(:tworx, 2, defp)
    @test num_params(g2) == 1
    @test approxeq(mat(g2, [0.3]), _embed(mat(RX, 0.3), [0], 2) * _embed(mat(RX, 0.3), [1], 2))
    # BlockOp：命名 + 重复
    body = Circuit([H(0), CX(0, 1)])
    blk = block(body; name=:round, repeat=3)
    @test blk isa BlockOp && qubits(blk) == [0, 1]
    @test is_unitary(blk)
    fl = unroll(blk)
    @test length(fl) == 6
    @test fl[1] == H(0) && fl[3] == H(0) && fl[5] == H(0)
    @test fl[2] == CX(0, 1) && fl[6] == CX(0, 1)
    # 映射：body 局部 0..1 → 全局 [3, 4]
    blk2 = block(Circuit([H(0), CX(0, 1)]); at=[3, 4])
    @test qubits(blk2) == [3, 4]
    fl2 = unroll(blk2)
    @test fl2[1] == GateOp(H, [3], [])
    @test fl2[2] == GateOp(CX, [3, 4], [])
    # mat 一致性（含映射）：blk2 = 1 次 [H(0), CX(0,1)] 映射到 [3,4]
    expected = _embed(mat(CX), [0, 1], 2) * _embed(mat(H), [0], 2)
    @test approxeq(mat(blk2), expected)
    # unroll! 递归
    c = Circuit(5)
    push!(c, blk2)
    push!(c, X(0))
    unroll!(c)
    @test num_ops(c) == 3
    @test c.ops[1] == GateOp(H, [3], [])
    # 含测量的块（非酉）
    bm = block(Circuit([measure(0, CReg(:c, 1)[1])]))
    @test !is_unitary(bm)
    @test_throws ArgumentError mat(bm)
end

@testset "dag" begin
    c = Circuit(3)
    push!(c, H(0))            # 1
    push!(c, CX(0, 1))        # 2：依赖 1
    push!(c, X(1))            # 3：依赖 2
    push!(c, X(2))            # 4：独立
    d = dag(c)
    @test nodes(d) == c.ops
    @test dependencies(d, 1) == Int[]
    @test dependencies(d, 2) == [1]
    @test dependencies(d, 3) == [2]
    @test dependencies(d, 4) == Int[]
    # 经典依赖：measure → if
    c2 = Circuit(2)
    push!(c2, measure(0, c2.cregs[1][1]))
    if_then(c2, c2.cregs[1] == 1, Circuit([X(0)]))
    d2 = dag(c2)
    @test dependencies(d2, 2) == [1]
end
