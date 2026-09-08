# =============================================================================
# interface.jl — Interface 子模块（模拟后端契约）的测试
#
# 内置一个最小的稠密态矢量参考后端 DenseBackend，端到端验证：
#   * 后端只需 `<: Backend` + 实现 `simulate` 即可接入
#   * SimResult 的强/弱模拟两种返回
#   * counts_key 的键格式约定（小端序、x 填充、多寄存器）
#   * 能力查询与默认后端便利层
# 这个参考实现同时充当"后端作者如何接入"的文档示例。
# =============================================================================

using Test
using Random
using QuantumCircuits
using QuantumCircuits: _compose_unitary
using QuantumCircuits.Interface
using QuantumCircuits.Interface: Backend
using QuantumCircuits.Hamiltonian: PauliTerm, PauliSum
using LinearAlgebra: dot

"测试用参考后端：稠密态矢量（n ≤ 10），只支持末尾测量、不支持中途测量。"
struct DenseBackend <: Backend
    nmax::Int
end
DenseBackend() = DenseBackend(10)

QuantumCircuits.Interface.supports(::DenseBackend, cap::Symbol) = cap === :statevector
QuantumCircuits.Interface.max_qubits(b::DenseBackend) = b.nmax

function QuantumCircuits.Interface.simulate(c::Circuit, ::DenseBackend;
                                            shots::Int = 0,
                                            seed::Union{Nothing,Integer} = nothing,
                                            kwargs...)
    # 参考实现从简：只支持"全酉部分 + 末尾测量"
    meas = findlast(op -> op isa MeasOp, c.ops)
    if meas !== nothing && meas != lastindex(c.ops)
        throw(ArgumentError("DenseBackend supports only final measurements"))
    end
    n = c.n
    ops = Operation[]
    for op in c.ops
        op isa MeasOp && break
        push!(ops, op)
    end
    U = _compose_unitary(Circuit(ops; n = n, qregs = copy(c.qregs), cregs = copy(c.cregs)))
    psi = U * vec([i == 1 ? complex(1.0) : complex(0.0) for i in 1:(1 << n)])
    if shots == 0
        return SimResult(nothing, psi)
    end

    # 按振幅概率采样；基矢提取遵循小端序：qubit q = (idx-1) 的第 q-1 位
    rng = seed === nothing ? Random.default_rng() : MersenneTwister(seed)
    probs = abs2.(psi)
    probs ./= sum(probs)
    cdf = cumsum(probs)
    counts = Dict{String,Int}()
    for _ in 1:shots
        idx = min(searchsortedfirst(cdf, rand(rng)), lastindex(cdf))
        basis = idx - 1                     # 0-based 基矢标签；小端序：bit0 = qubit 1
        outcome = Dict{ClbitRef,Int}()
        for op in c.ops
            op isa MeasOp || continue
            for (q, cb) in zip(op.qubits, op.clbits)
                outcome[cb] = (basis >> (q - 1)) & 1
            end
        end
        k = counts_key(c, outcome)
        counts[k] = get(counts, k, 0) + 1
    end
    return SimResult(counts, nothing)
end

function QuantumCircuits.Interface.expectation(h::PauliSum, c::Circuit, ::DenseBackend;
                                               params = nothing, kwargs...)
    cc = params === nothing ? c : assign(c, params)
    psi = simulate(cc, DenseBackend()).state
    Hm = QuantumCircuits.mat(h, cc.n)
    return real(dot(psi, Hm * psi))
end

@testset "Interface" begin
    @testset "能力查询" begin
        b = DenseBackend()
        @test supports(b, :statevector)
        @test !supports(b, :mid_measure)
        @test !supports(b, :noise)
        @test max_qubits(b) == 10
        # 契约默认值：未覆盖的能力一律 false，qubit 上限 typemax
        struct StubBackend <: Backend end
        s = StubBackend()
        @test !supports(s, :statevector)
        @test max_qubits(s) == typemax(Int)
    end

    @testset "counts_key 约定" begin
        reg = CReg(:c, 3)
        # 右端是 index 1（最低有效位）
        @test counts_key(reg, Dict(ClbitRef(reg, 1) => 0,
                                   ClbitRef(reg, 2) => 1,
                                   ClbitRef(reg, 3) => 1)) == "c:110"
        # 未测量位填 'x'：只测了 index 1 = 1，在串的右端
        @test counts_key(reg, Dict(ClbitRef(reg, 1) => 1)) == "c:xx1"
        # 向量形式（按 index 1..n 给出）
        @test counts_key(reg, [1, 0, 0]) == "c:001"
        # 多寄存器：按 c.cregs 声明顺序连接
        c = Circuit(3, cregs = [CReg(:c, 3), CReg(:anc, 2)])
        outcome = Dict(ClbitRef(c.cregs[1], 1) => 0, ClbitRef(c.cregs[1], 2) => 1,
                       ClbitRef(c.cregs[1], 3) => 1,
                       ClbitRef(c.cregs[2], 1) => 1, ClbitRef(c.cregs[2], 2) => 0)
        @test counts_key(c, outcome) == "c:110,anc:01"
        # 只测 anc：c 寄存器被跳过（anc[1]=1 在右端）
        only_anc = Dict(ClbitRef(c.cregs[2], 1) => 1)
        @test counts_key(c, only_anc) == "anc:x1"
        # 空结果报错
        @test_throws ArgumentError counts_key(c, Dict{ClbitRef,Int}())
    end

    @testset "默认后端便利层" begin
        @test default_backend() === nothing
        c = Circuit(2)
        push!(c, H(1))
        push!(c, CX(1, 2))
        measure_all!(c)
        @test_throws ArgumentError simulate(c; shots = 10)
        b = set_default_backend!(DenseBackend())
        @test default_backend() === b
        r = simulate(c; shots = 100, seed = 7)
        @test sum(values(r.counts)) == 100
        clear_default_backend!()
        @test default_backend() === nothing
    end

    @testset "simulate：强/弱模拟" begin
        b = DenseBackend()
        bell = Circuit(2)
        push!(bell, H(1))
        push!(bell, CX(1, 2))
        measure_all!(bell)

        # 强模拟：态矢量（小端序：|q2 q1⟩ 的 00 与 11 叠加）
        r0 = simulate(bell, b)
        @test r0.counts === nothing
        @test r0.state ≈ [1, 0, 0, 1] ./ √2 atol = 1e-12

        # 弱模拟：计数
        r = simulate(bell, b; shots = 4096, seed = 42)
        @test r.state === nothing
        @test sum(values(r.counts)) == 4096
        @test Set(keys(r.counts)) == Set(["c:00", "c:11"])   # Bell 态不会出 01/10
        @test r["c:11"] + r["c:00"] == 4096                  # SimResult 的 getindex 便利
        @test haskey(r, "c:00")

        # 同种子可复现（契约约定）
        r2 = simulate(bell, b; shots = 512, seed = 1)
        r3 = simulate(bell, b; shots = 512, seed = 1)
        @test r2.counts == r3.counts

        # 未实现 simulate 的后端给出可读错误
        struct NoSim <: Backend end
        @test_throws ArgumentError simulate(bell, NoSim())
    end

    @testset "expectation 契约" begin
        b = DenseBackend()
        hz = PauliSum(PauliTerm(1.0, 1 => :Z))
        hx = PauliSum(PauliTerm(1.0, 1 => :X))
        c0 = Circuit(1)
        @test expectation(hz, c0, b) ≈ 1.0 atol = 1e-12   # |0⟩ 的 ⟨Z⟩ = 1
        @test expectation(hx, c0, b) ≈ 0.0 atol = 1e-12
        cplus = Circuit(1)
        push!(cplus, H(1))
        @test expectation(hx, cplus, b) ≈ 1.0 atol = 1e-12  # |+⟩ 的 ⟨X⟩ = 1
        @test expectation(hz, cplus, b) ≈ 0.0 atol = 1e-12
        # 带参数线路：params 经 assign 绑定后计算
        vqe = Circuit(1)
        push!(vqe, RX(:θ, 1))
        # ⟨0| RX(θ)† Z RX(θ) |0⟩ = cos θ
        @test expectation(hz, vqe, b; params = Dict(:θ => 0.0)) ≈ 1.0 atol = 1e-12
        @test expectation(hz, vqe, b; params = Dict(:θ => π)) ≈ -1.0 atol = 1e-12
    end
end
