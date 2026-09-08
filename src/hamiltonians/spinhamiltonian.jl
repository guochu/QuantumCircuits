# =============================================================================
# spinhamiltonian.jl — 子模块 QuantumCircuits.Hamiltonian：自旋算符代数
#
# SpinOpTerm / SpinOpSum：Pauli 代数的推广——单个比特位上可以放任意单比特
# 算子（`Symbol` 简写或任意 `2×2` 矩阵），不限于 Pauli 矩阵。
#
#   SpinOpTerm(0.5, 1 => :Z, 2 => :Y)          # 0.5 · Z₁ Y₂
#   SpinOpTerm(1.0, 1 => [0 1; -1 0])          # 任意 2×2 矩阵
#   SpinOpTerm(0.1, 3 => :X) + SpinOpTerm(1.0, 2 => :Z)² ∈ SpinOpSum
#
# 乘积结构使后端 `apply` 无需构造大矩阵：逐位走局域 kernel，
# 复杂度 O(#ops · 2ⁿ · D_local)，可直接用于高效本征态求解
# （Lanczos / DMRG 的作用算符）与时间演化（Trotter 步）。
# （状态相关方法由各模拟器后端实现，如 VQC 的扩展。）
# =============================================================================

const _SPIN1 = Dict{Symbol,Matrix{ComplexF64}}(
    :I => Matrix{ComplexF64}(I, 2, 2),
    :X => [0.0 1.0; 1.0 0.0],
    :Y => [0.0 -im; im 0.0],
    :Z => [1.0 0.0; 0.0 -1.0],
    :P => [0.0 1.0; 0.0 0.0],    # σ₊ = (X + iY) / 2
    :M => [0.0 0.0; 1.0 0.0],    # σ₋ = (X - iY) / 2
)

const _SPIN_ADJ = Dict(:I => :I, :X => :X, :Y => :Y, :Z => :Z, :P => :M, :M => :P)

"单比特算子：`Symbol` 简写或任意 `2×2` 矩阵（不限 Pauli / 厄米）。"
function _spin_matrix(op)
    if op isa Symbol
        haskey(_SPIN1, op) || throw(ArgumentError("unknown spin operator :$(op)"))
        return _SPIN1[op]
    elseif op isa AbstractMatrix
        size(op) == (2, 2) ||
            throw(ArgumentError("spin operator must be a 2×2 matrix, got $(size(op))"))
        return op
    end
    throw(ArgumentError("invalid spin operator $(typeof(op))"))
end

"""
    SpinOpTerm(coeff, ops...) -> SpinOpTerm

自旋算符乘积项：`coeff · A₁ A₂ …`，`Aᵢ` 作用在比特 `qᵢ` 上。
算子 `Aᵢ` 可以是 `Symbol` 简写（`:I / :X / :Y / :Z / :P / :M`）
或**任意 `2×2` 矩阵**（不限 Pauli / 厄米）。

* `SpinOpTerm(0.5, 1 => :Z, 2 => :Y)`
* `SpinOpTerm(1.0, 3 => [0 1; -1 0])`       # 任意 2×2 矩阵

位置自动排序；同一位重复出现按乘积顺序保留。
"""
struct SpinOpTerm
    coeff::Number
    ops::Vector{Pair{Int,Any}}
    function SpinOpTerm(coeff::Number, ops::Vector{<:Pair{Int}})
        isempty(ops) && throw(ArgumentError("SpinOpTerm requires at least one operator"))
        for p in ops
            _spin_matrix(last(p))          # 构造时校验算子合法性
        end
        new(coeff, sort(ops; by = first))
    end
end
SpinOpTerm(coeff::Number, ops::Pair{Int}...) = SpinOpTerm(coeff, collect(ops))

Base.copy(t::SpinOpTerm) = SpinOpTerm(t.coeff, copy(t.ops))
Base.:(==)(t1::SpinOpTerm, t2::SpinOpTerm) = t1.coeff == t2.coeff && t1.ops == t2.ops
Base.hash(t::SpinOpTerm, h::UInt) = hash(t.ops, hash(t.coeff, h))

"""
    SpinOpSum(terms...) -> SpinOpSum

厄米（或一般）算符 = 自旋算符项之和。
"""
struct SpinOpSum
    terms::Vector{SpinOpTerm}
end
SpinOpSum(terms::SpinOpTerm...) = SpinOpSum(collect(terms))
SpinOpSum() = SpinOpSum(SpinOpTerm[])

Base.copy(s::SpinOpSum) = SpinOpSum(copy(s.terms))
Base.push!(s::SpinOpSum, t::SpinOpTerm) = (push!(s.terms, t); s)
Base.append!(s::SpinOpSum, t::SpinOpSum) = (append!(s.terms, t.terms); s)

Base.:+(t1::SpinOpTerm, t2::SpinOpTerm) = SpinOpSum([t1, t2])
Base.:+(s::SpinOpSum, t::SpinOpTerm) = push!(copy(s), t)
Base.:+(t::SpinOpTerm, s::SpinOpSum) = push!(copy(s), t)
Base.:+(s1::SpinOpSum, s2::SpinOpSum) = append!(copy(s1), s2)
Base.:-(t::SpinOpTerm) = SpinOpTerm(-t.coeff, t.ops)
Base.:*(c::Real, t::SpinOpTerm) = SpinOpTerm(c * t.coeff, t.ops)
Base.:*(t::SpinOpTerm, c::Real) = c * t
Base.:*(c::Real, s::SpinOpSum) = SpinOpSum([c * t for t in s.terms])
Base.:*(s::SpinOpSum, c::Real) = c * s

function Base.adjoint(t::SpinOpTerm)
    ops = Pair{Int,Any}[first(p) => (last(p) isa Symbol ? _SPIN_ADJ[last(p)] :
                                     adjoint(_spin_matrix(last(p)))) for p in t.ops]
    return SpinOpTerm(conj(t.coeff), ops)
end
Base.adjoint(s::SpinOpSum) = SpinOpSum([adjoint(t) for t in s.terms])
LinearAlgebra.ishermitian(t::SpinOpTerm) = t == adjoint(t)
LinearAlgebra.ishermitian(s::SpinOpSum) = s == adjoint(s)

"""
    mat(t::SpinOpTerm, n::Int) -> Matrix
    mat(s::SpinOpSum, n::Int) -> Matrix

展开为 `n` 比特的稠密矩阵（小端序；仅供小规模验证 / 对拍，
大规模使用请走各后端 `apply` 的局域核路径）。
"""
function _embed_local(m::AbstractMatrix, key::NTuple{N,Int}, n::Int) where {N}
    d = 1 << n
    D = size(m, 1)
    full = zeros(ComplexF64, d, d)
    for col in 0:d-1
        lcol = 0
        ok = true
        for (j, b) in enumerate(key)
            lcol |= ((col >> b) & 1) << (j - 1)
        end
        for lrow in 0:D-1
            grow = col
            for (j, b) in enumerate(key)
                grow = (grow & ~(1 << b)) | (((lrow >> (j - 1)) & 1) << b)
            end
            full[grow+1, col+1] = m[lrow+1, lcol+1]
        end
    end
    return full
end

function mat(t::SpinOpTerm, n::Int)
    d = 1 << n
    acc = Matrix{ComplexF64}(I, d, d)          # 乘积项：按 ops 顺序右乘各因子的嵌入
    for (q, op) in t.ops
        m = _spin_matrix(op)
        1 <= q <= n || throw(ArgumentError("operator position $q out of range [1, $n]"))
        acc = acc * _embed_local(m, (q - 1,), n)
    end
    return t.coeff .* acc
end

function mat(s::SpinOpSum, n::Int)
    d = 1 << n
    acc = zeros(ComplexF64, d, d)
    for t in s.terms
        acc .+= mat(t, n)
    end
    return acc
end
