# variational.jl — 参数化线路示例（变分 ansatz）

@testset "variational" begin
    # ── 符号参数默认（先建线路、后绑参） ──
    c = variational_circuit_1d(2, 1)
    ps = parameters(c)
    @test length(ps) == 3 * 2 * 2                              # 3L(depth+1)
    @test ps == [Param(Symbol("θ[$i]")) for i in 1:12]         # θ[1]…θ[12] 按出现序
    @test count_ops(c) == Dict(:RZ => 8, :RY => 4, :CX => 1)   # 2 旋转层(每层 RZ=2L, RY=L) + 1 个 CX
    @test nqubits(c) == 2
    # 绑参：ParamVector 作 key 整向量绑定
    θ = params(:θ, 12)
    bound = assign(c, Dict(θ => collect(0.1:0.1:1.2)))
    @test parameters(bound) == Param[]
    @test bound[1].params == [0.1]
    @test c[1].params == [Param(Symbol("θ[1]"))]               # 原线路不变
    # 数值正确性：depth=0、L=1 即单比特 RZ-RY-RZ，酉性检查
    c0 = variational_circuit_1d(1, 0)
    m = mat(assign(c0, Dict(params(:θ, 3) => [0.2, 0.4, 0.6]))[1])
    @test m' * m ≈ [1 0; 0 1] atol = 1e-12

    # ── 直接数值参数 ──
    c2 = variational_circuit_1d(2, 2; θs = collect(1.0:18.0))
    @test parameters(c2) == Param[]
    @test count_ops(c2) == Dict(:RZ => 12, :RY => 6, :CX => 2)  # 3 旋转层(每层 RZ=2L, RY=L) + 2 纠缠层
    @test_throws ArgumentError variational_circuit_1d(2, 1; θs = rand(5))

    # ── 实参数版（仅 RY） ──
    r = real_variational_circuit_1d(3, 1)
    @test length(parameters(r)) == 3 * 2                        # L(depth+1)
    @test count_ops(r) == Dict(:RY => 6, :CX => 2)
    @test nqubits(r) == 3
    r2 = real_variational_circuit_1d(3, 1; θs = collect(1.0:6.0))
    @test parameters(r2) == Param[]
    @test_throws ArgumentError real_variational_circuit_1d(3, 1; θs = rand(3))

    # ── 纠缠层方向交替：depth=2 时第 2 层 CX 顺序倒排（push 序 (L-1)→1） ──
    c3 = real_variational_circuit_1d(4, 2)
    ops = [c3.ops[i] for i in eachindex(c3.ops)]
    cx_idx = findall(o -> o.gate === CX, ops)
    @test length(cx_idx) == 2 * 3
    @test [ops[i].qubits for i in cx_idx] ==                 # 奇数层正序 + 偶数层倒序
          [[1, 2], [2, 3], [3, 4], [3, 4], [2, 3], [1, 2]]
end
