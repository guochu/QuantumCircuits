@testset "circuit DSL" begin
    c = Circuit(2)
    @test c.n == 2
    @test length(c.qregs) == 1 && c.qregs[1] == QReg(:q, 2)
    @test c.cregs[1] == CReg(:c, 2)
    push!(c, H(1))
    push!(c, H, 2)                       # 便利重载
    push!(c, RX, π/2, 3)                 # 参数门便利重载
    @test c[3] == GateOp(RX, [3], [Float64(π/2)])
    c << CX(1, 2)
    @test num_ops(c) == 4
    # 迭代 / 索引
    @test collect(c) == c.ops
    @test c[end] == GateOp(CX, [1, 2], [])
    # * 为纯函数 append
    c2 = Circuit(1)
    push!(c2, X(1))
    c3 = c * c2
    @test num_ops(c3) == 5
    @test num_ops(c) == 4
    @test num_ops(c3) == num_ops(c) + num_ops(c2)
    @test c3.ops[1:4] == c.ops
    @test c3.ops[5] == X(1)
    @test num_ops(c << c2) == 5
    # copy 独立
    c4 = copy(c)
    push!(c4, X(1))
    @test num_ops(c) == 5 && num_ops(c4) == 6
    # 由操作向量构造（推断 n）
    c5 = Circuit([X(0), CX(0, 1)])
    @test c5.n == 2
end

@testset "parameters & assign" begin
    c = Circuit(4)
    φ = params(:φ, 3)
    for q in 1:4
        push!(c, RX(:θ, q))
    end
    for q in 1:3
        push!(c, RZZ(φ[q], q, q + 1))
    end
    ps = parameters(c)
    @test ps == [Param(:θ), φ[1], φ[2], φ[3]]      # 去重 + 出现序
    # 未绑参数不能求矩阵
    @test_throws ArgumentError mat(c[1])
    # 绑定（纯函数）
    bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))
    @test parameters(bound) == Param[]
    @test bound[1].params == [0.3]
    @test bound[5].params == [Float64(π/4)]
    @test c[1].params == [Param(:θ)]               # 原线路不变
    # 单参数绑定 / assign!
    b2 = assign(c, :θ, 1.0)
    @test b2[1].params == [1.0] && b2[5].params == [Param(Symbol("φ[1]"))]
    b3 = copy(c)
    assign!(b3, φ[1], 2.0)
    @test b3[5].params == [2.0]
    # 数值正确性：绑参后矩阵可求
    m = mat(bound[1])
    @test approxeq(m' * m, I2; tol=1e-8)
end

@testset "analysis" begin
    c = Circuit(3)
    push!(c, H(0))
    push!(c, H(1))
    push!(c, CX(0, 1))
    push!(c, measure(2, c.cregs[1][1]))
    @test depth(c) == 2
    @test count_ops(c) == Dict(:H => 2, :CX => 1, :measure => 1)
    @test num_ops(c) == 4
    @test qubits_used(c) == [0, 1, 2]
    @test validate(c) === c
    # dagger：纯酉线路
    c2 = Circuit(3)
    push!(c2, H(0)); push!(c2, CX(0, 2)); push!(c2, RZ(0.4, 1))
    dg = dagger(c2)
    @test length(dg) == 3
    @test dg.ops[1] == GateOp(InvGate(RZ), [1], [0.4])
    @test dg.ops[3] == GateOp(InvGate(H), [0], [])
    @test approxeq(_compose_unitary(dg) * _compose_unitary(c2), Matrix{ComplexF64}(I, 8, 8); tol=1e-8)
    # 含测量的线路不可逆
    @test_throws ErrorException dagger(c)
    # validate 越界
    bad = Circuit(1)
    push!(bad, X(1))
    @test_throws ArgumentError validate(bad)
    # measure_all!
    c3 = Circuit(3)
    measure_all!(c3)
    @test count_ops(c3) == Dict(:measure => 3)
end

@testset "layout" begin
    c = Circuit(3)
    @test c.layout == Layout()
    c2 = Circuit(2; layout=Layout([5, 7], [5, 7]))
    @test c2.layout.initial == [5, 7]
end
