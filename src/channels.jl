# =============================================================================
# channels.jl — 噪声信道指令（Stim 先例：噪声即指令）
#
# 信道由 Kraus 算子集描述（CPTP 映射）；`kraus(ch)` 给出算子集。
# 噪声进 IR：含噪实验由线路自描述，而非在模拟器层外挂噪声模型。
# =============================================================================

"""量子信道抽象：由 Kraus 算子集描述的 CPTP 映射。"""
abstract type Channel end

"信道的 Kraus 算子集。"
function kraus(ch::Channel)
    error("`kraus` not implemented for $(typeof(ch)).")
end

function _check_probs(probs::Vector{Float64}; tol::Real=1e-6)
    all(p -> p >= 0, probs) || throw(ArgumentError("probabilities must be non-negative"))
    abs(sum(probs) - 1) <= tol ||
        throw(ArgumentError("probabilities must sum to 1 (got $(sum(probs)))"))
    return nothing
end

"""通用 Kraus 信道（构造时校验完全正迹 TP：Σ K†K = I）。"""
struct KrausChannel <: Channel
    ops::Vector{Matrix{ComplexF64}}

    function KrausChannel(ops::Vector{<:AbstractMatrix})
        isempty(ops) && throw(ArgumentError("KrausChannel needs at least one operator"))
        ms = Matrix{ComplexF64}[Matrix{ComplexF64}(m) for m in ops]
        d = size(ms[1], 1)
        all(m -> size(m) == (d, d), ms) || throw(ArgumentError("all Kraus operators must share the same shape"))
        acc = zeros(ComplexF64, d, d)
        for m in ms
            acc += adjoint(m) * m
        end
        norm(acc - I) <= 1e-6 ||
            throw(ArgumentError("Kraus operators are not trace-preserving (Σ K†K ≠ I)"))
        new(ms)
    end
end

kraus(ch::KrausChannel) = ch.ops

const _PAULI1 = Dict{Symbol,Matrix{ComplexF64}}(
    :I => Matrix{ComplexF64}(I, 2, 2),
    :X => ComplexF64[0 1; 1 0],
    :Y => ComplexF64[0 -im; im 0],
    :Z => ComplexF64[1 0; 0 -1],
)

# Pauli 乘法表：(a, b) => (结果, 相位)
const _PAULI_MUL = Dict{Tuple{Symbol,Symbol},Tuple{Symbol,ComplexF64}}(
    (:I, :I) => (:I, 1), (:I, :X) => (:X, 1), (:I, :Y) => (:Y, 1), (:I, :Z) => (:Z, 1),
    (:X, :I) => (:X, 1), (:X, :X) => (:I, 1), (:X, :Y) => (:Z, im), (:X, :Z) => (:Y, -im),
    (:Y, :I) => (:Y, 1), (:Y, :X) => (:Z, -im), (:Y, :Y) => (:I, 1), (:Y, :Z) => (:X, im),
    (:Z, :I) => (:Z, 1), (:Z, :X) => (:Y, im), (:Z, :Y) => (:X, -im), (:Z, :Z) => (:I, 1),
)

"单比特 Pauli 符号乘法：返回 (结果符号, 相位)。"
_pauli_mul(a::Symbol, b::Symbol) = _PAULI_MUL[(a, b)]

# 小端序：ps[1] 是最低有效位（qubit 1），kron 展开时排在最右。
function _pauli_string_matrix(ps::Vector{Symbol})
    m = _PAULI1[ps[end]]
    for i in length(ps)-1:-1:1
        m = kron(m, _PAULI1[ps[i]])
    end
    return m
end

"""Pauli 信道：以概率 `probs[i]` 施加 Pauli 串 `paulis[i]`（如 `[:X, :Y]`）。"""
struct PauliChannel <: Channel
    paulis::Vector{Vector{Symbol}}
    probs::Vector{Float64}

    function PauliChannel(paulis::Vector{Vector{Symbol}}, probs::Vector{<:Real})
        isempty(paulis) && throw(ArgumentError("PauliChannel needs at least one Pauli string"))
        length(paulis) == length(probs) ||
            throw(ArgumentError("paulis and probs must have the same length"))
        n = length(paulis[1])
        for ps in paulis
            length(ps) == n || throw(ArgumentError("all Pauli strings must have the same length"))
            all(s -> s in (:I, :X, :Y, :Z), ps) ||
                throw(ArgumentError("invalid Pauli symbol; allowed: :I :X :Y :Z"))
        end
        p = Float64.(probs)
        _check_probs(p)
        new(paulis, p)
    end
end

function kraus(ch::PauliChannel)
    out = Matrix{ComplexF64}[]
    for (ps, p) in zip(ch.paulis, ch.probs)
        p > 0 || continue
        push!(out, sqrt(p) .* _pauli_string_matrix(ps))
    end
    return out
end

"""酉混合信道：以概率 `probs[i]` 施加酉矩阵 `ops[i]`。"""
struct UnitaryChannel <: Channel
    ops::Vector{Matrix{ComplexF64}}
    probs::Vector{Float64}

    function UnitaryChannel(ops::Vector{<:AbstractMatrix}, probs::Vector{<:Real})
        isempty(ops) && throw(ArgumentError("UnitaryChannel needs at least one operator"))
        length(ops) == length(probs) ||
            throw(ArgumentError("ops and probs must have the same length"))
        ms = Matrix{ComplexF64}[Matrix{ComplexF64}(m) for m in ops]
        for m in ms
            _check_unitary(m)
        end
        p = Float64.(probs)
        _check_probs(p)
        new(ms, p)
    end
end

kraus(ch::UnitaryChannel) = [sqrt(p) .* m for (m, p) in zip(ch.ops, ch.probs) if p > 0]

# ── 噪声指令构造（返回 ChannelOp，定义见 ops.jl；调用期解析） ────────────────

"""Pauli 误差（QEC 核心）：单量子比特，`PauliError(q, (px, py, pz))`。"""
function PauliError(q::Integer, probs::NTuple{3,Real})
    px, py, pz = probs
    px + py + pz <= 1 || throw(ArgumentError("px + py + pz must be ≤ 1"))
    ch = PauliChannel([[:I], [:X], [:Y], [:Z]], Float64[1 - px - py - pz, px, py, pz])
    return KrausOp(ch, [Int(q)])
end

"""去极化信道：`Depolarizing(qubits, p)` —— 以概率 p 施加均匀随机的非恒 Pauli。"""
function Depolarizing(qubits::Union{Integer,AbstractVector{<:Integer}}, p::Real)
    0 <= p <= 1 || throw(ArgumentError("p must be in [0, 1]"))
    qv = qubits isa Integer ? [Int(qubits)] : collect(Int, qubits)
    n = length(qv)
    d = 1 << n
    paulis = Vector{Vector{Symbol}}()
    probs = Float64[]
    # 所有 Pauli 串（含恒等，恒等概率 1-p）
    for code in 0:(4^n - 1)
        ps = Symbol[(:I, :X, :Y, :Z)[(code >> (2*j)) & 0x3 + 1] for j in 0:n-1]
        if all(==(:I), ps)
            push!(probs, 1 - p)
        else
            push!(probs, p / (d * d - 1))
        end
        push!(paulis, ps)
    end
    return KrausOp(PauliChannel(paulis, probs), qv)
end

"""振幅阻尼：`AmplitudeDamping(q, γ)`。"""
function AmplitudeDamping(q::Integer, γ::Real)
    0 <= γ <= 1 || throw(ArgumentError("γ must be in [0, 1]"))
    ch = KrausChannel([ComplexF64[1 0; 0 sqrt(1-γ)], ComplexF64[0 sqrt(γ); 0 0]])
    return KrausOp(ch, [Int(q)])
end

"""相位阻尼：`PhaseDamping(q, γ)`。"""
function PhaseDamping(q::Integer, γ::Real)
    0 <= γ <= 1 || throw(ArgumentError("γ must be in [0, 1]"))
    ch = KrausChannel([ComplexF64[1 0; 0 sqrt(1-γ)], ComplexF64[0 0; 0 sqrt(γ)]])
    return KrausOp(ch, [Int(q)])
end
