# =============================================================================
# hamiltonian.jl — 子模块 QuantumCircuits.Hamiltonian：Pauli 代数
#
# 用法：`using QuantumCircuits.Hamiltonian`
# 系数类型参数化：实数/复数均可（整数系数自动提升为 Float64）。
# 注意：`expectation` 由模拟器后端实现，本包不实现。
# =============================================================================

module Hamiltonian

using LinearAlgebra
using SparseArrays

export PauliTerm, PauliSum

# 与主模块共享同一个 mat 函数（mat(::PauliSum, n) 在下方扩展）
import QuantumCircuits: mat

"Pauli 单比特符号集合：`:I, :X, :Y, :Z`。"
const PAULIS = (:I, :X, :Y, :Z)

# 元素类型保持自然：I/X/Z 为实数，Y 为复数；kron 展开时按需提升。
const _P = Dict{Symbol,Matrix{<:Number}}(
    :I => Float64[1 0; 0 1],
    :X => Float64[0 1; 1 0],
    :Y => ComplexF64[0 -im; im 0],
    :Z => Float64[1 0; 0 -1],
)

const _PAULI_MUL = Dict{Tuple{Symbol,Symbol},Tuple{Symbol,ComplexF64}}(
    (:I, :I) => (:I, 1), (:I, :X) => (:X, 1), (:I, :Y) => (:Y, 1), (:I, :Z) => (:Z, 1),
    (:X, :I) => (:X, 1), (:X, :X) => (:I, 1), (:X, :Y) => (:Z, im), (:X, :Z) => (:Y, -im),
    (:Y, :I) => (:Y, 1), (:Y, :X) => (:Z, -im), (:Y, :Y) => (:I, 1), (:Y, :Z) => (:X, im),
    (:Z, :I) => (:Z, 1), (:Z, :X) => (:Y, im), (:Z, :Y) => (:X, -im), (:Z, :Z) => (:I, 1),
)

_pauli_mul(a::Symbol, b::Symbol) = _PAULI_MUL[(a, b)]

# 整数系数自动提升为 Float64
_numtype(::Type{T}) where {T<:Number} = T <: Integer ? Float64 : T

"""
Pauli 项：`coeff * P_{q1} ⊗ P_{q2} ⊗ …`

    PauliTerm(1.0, 1=>:Z, 2=>:X)

类型参数 `T<:Number`（实数/复数均可；整数系数自动提升为 `Float64`）。
构造时位置自动排序、同 qubit 项自动相乘合并（如 `X·X → I`）。
"""
struct PauliTerm{T<:Number}
    coeff::T
    ops::Vector{Pair{Int,Symbol}}   # 按 qubit 升序；每个 qubit 至多一项；不含 :I
end

# 规范化原始构造（校验符号 + 整数提升）；避免多重 callable 构造器定义
function _pauli_term(coeff::Number, ops::Vector{Pair{Int,Symbol}})
    for (_, s) in ops
        s in PAULIS || throw(ArgumentError("invalid Pauli symbol $s"))
    end
    T = _numtype(typeof(coeff))
    return PauliTerm{T}(T(coeff), ops)
end

function PauliTerm(coeff::Number, pairs::Pair{Int,Symbol}...)
    d = Dict{Int,Symbol}()
    phase = 1
    for (q, s) in pairs
        if haskey(d, q)
            s2, ph = _pauli_mul(d[q], s)
            phase *= ph
            if s2 == :I
                delete!(d, q)
            else
                d[q] = s2
            end
        elseif s != :I
            d[q] = s
        end
    end
    ops = sort!(collect(Pair{Int,Symbol}, d))
    return _pauli_term(coeff * phase, ops)
end

PauliTerm(pairs::Pair{Int,Symbol}...) = PauliTerm(1.0, pairs...)

"""
厄米算符 = Pauli 项之和；`+` 自动合并同类项、去掉零系数项，系数类型按需提升。

    PauliSum([PauliTerm(1.0, 1=>:Z), PauliTerm(0.5, 2=>:X)])
"""
struct PauliSum{T<:Number}
    terms::Vector{PauliTerm{T}}
end

PauliSum() = PauliSum(Vector{PauliTerm{Float64}}())
PauliSum(t::PauliTerm{T}) where {T} = PauliSum{T}([t])

function PauliSum(ts::PauliTerm...)
    T = Float64
    for t in ts
        T = promote_type(T, typeof(t.coeff))
    end
    return PauliSum{T}(PauliTerm{T}[PauliTerm(T(t.coeff), t.ops) for t in ts])
end

PauliSum(ts::Vector{<:PauliTerm}) = PauliSum(ts...)

function _merge_terms(ts)
    isempty(ts) && return PauliSum()
    T = Float64
    for t in ts
        T = promote_type(T, typeof(t.coeff))
    end
    coeffs = Dict{Tuple{Vararg{Pair{Int,Symbol}}},T}()
    order = Tuple{Vararg{Pair{Int,Symbol}}}[]
    for t in ts
        key = Tuple(t.ops)
        if haskey(coeffs, key)
            coeffs[key] = coeffs[key] + t.coeff
        else
            coeffs[key] = t.coeff
            push!(order, key)
        end
    end
    terms = PauliTerm{T}[]
    for key in order
        c = coeffs[key]
        iszero(c) || push!(terms, PauliTerm{T}(c, collect(Pair{Int,Symbol}, key)))
    end
    return PauliSum{T}(terms)
end

Base.:+(a::PauliTerm, b::PauliTerm) = _merge_terms([a, b])
Base.:+(a::PauliSum, b::PauliSum) = _merge_terms(vcat(a.terms, b.terms))
Base.:+(a::PauliSum, b::PauliTerm) = _merge_terms(vcat(a.terms, [b]))
Base.:+(a::PauliTerm, b::PauliSum) = _merge_terms(vcat([a], b.terms))
Base.:-(t::PauliTerm) = _pauli_term(-t.coeff, t.ops)
Base.:-(s::PauliSum) = PauliSum([-t for t in s.terms])
Base.:-(a::PauliSum, b::PauliSum) = a + (-b)
Base.:-(a::PauliTerm, b::PauliTerm) = a + (-b)

Base.:*(k::Number, t::PauliTerm) = _pauli_term(k * t.coeff, t.ops)
Base.:*(t::PauliTerm, k::Number) = k * t
Base.:*(k::Number, s::PauliSum) = PauliSum([k * t for t in s.terms])
Base.:*(s::PauliSum, k::Number) = k * s

"Pauli 代数乘法（同 qubit 按乘法表，跨 qubit 拼接）。"
function Base.:*(a::PauliTerm, b::PauliTerm)
    d = Dict{Int,Symbol}(q => s for (q, s) in a.ops)
    phase = a.coeff * b.coeff
    for (q, s) in b.ops
        if haskey(d, q)
            s2, ph = _pauli_mul(d[q], s)
            phase *= ph
            if s2 == :I
                delete!(d, q)
            else
                d[q] = s2
            end
        else
            d[q] = s
        end
    end
    return _pauli_term(phase, sort!(collect(Pair{Int,Symbol}, d)))
end

Base.:*(a::PauliSum, b::PauliSum) =
    _merge_terms([t1 * t2 for t1 in a.terms for t2 in b.terms])

"伴随：Pauli 串厄米，仅系数取共轭。"
Base.adjoint(t::PauliTerm) = _pauli_term(conj(t.coeff), t.ops)
Base.adjoint(s::PauliSum) = PauliSum([adjoint(t) for t in s.terms])

"""
展开为 `n` 比特空间的 `2^n × 2^n` 稀疏矩阵（小端序：qubit 0 = 最低有效位）。
结果元素类型随系数与 Pauli 串自然提升（全实项 ⇒ 实矩阵）。
"""
function mat(h::PauliSum{T}, n::Int) where {T}
    d = 1 << n
    M = spzeros(T, d, d)
    for t in h.terms
        M = M + t.coeff * sparse(_kron_term(t.ops, n))
    end
    return dropzeros!(M)
end

function _kron_term(ops::Vector{Pair{Int,Symbol}}, n::Int)
    for (q, _) in ops
        0 <= q < n || throw(ArgumentError("qubit $q out of range for n=$n"))
    end
    T = Float64
    for (q, s) in ops
        T = promote_type(T, eltype(_P[s]))
    end
    factors = Matrix{T}[_P[:I] for _ in 1:n]
    for (q, s) in ops
        factors[q+1] = convert(Matrix{T}, _P[s])
    end
    # 小端序：qubit 0 = 最低有效位 → 最高位因子在最左；kron(A, B) 中 A 更显著
    m = factors[end]
    for i in n-1:-1:1
        m = kron(m, factors[i])
    end
    return m
end

function Base.show(io::IO, t::PauliTerm)
    print(io, t.coeff, " * ")
    if isempty(t.ops)
        print(io, "I")
    else
        join(io, ["$s($q)" for (q, s) in t.ops], " ")
    end
end

Base.show(io::IO, s::PauliSum) = join(io, [string(t) for t in s.terms], " + ")

end # module Hamiltonian
