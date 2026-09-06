# =============================================================================
# modifiers.jl — 修饰符：inv / pow / ctrl / negctrl
#
# 四个惰性、可组合的包装，取代"每种变体一个类型"的枚举式设计。
# 规范化顺序：negctrl → ctrl → pow → inv（mat() 惰性求值时应用）。
#
# 典型用法：
#     ctrl(H(1), 2)          # = CX(2, 1)：新控制比特**前置**（control-first 约定）
#     negctrl(H(3), 1, 2)    # 双负控 H
#     inv(RZZ(θ, 1, 2))      # 逆 ZZ 门
#     pow(H(1), 2)           # = ID
# =============================================================================

"""修饰符包装的 Gate（可嵌套）；类型参数携带内部门类型/控制数，支持静态分派。"""
abstract type ModifiedGate <: Gate end

"""逆门：`inv(g)`。"""
struct InvGate{G<:Gate} <: ModifiedGate
    g::G
end

"""幂门：`pow(g, k)`（k = -1 等价 inv）。"""
struct PowGate{G<:Gate} <: ModifiedGate
    g::G
    k::Float64
end

"""受控门：`ctrl(g, ctrls...)` / `negctrl(g, ctrls...)`；控制数 `K` 为类型参数，负控极性由 `negs` 记录。"""
struct CtrlGate{G<:Gate,K} <: ModifiedGate
    g::G
    negs::Vector{Bool}

    function CtrlGate(g::Gate, nctrls::Integer, negs::AbstractVector{Bool})
        nctrls >= 1 || throw(ArgumentError("need at least one control qubit"))
        length(negs) == nctrls ||
            throw(ArgumentError("negs must have length $nctrls, got $(length(negs))"))
        new{typeof(g),Int(nctrls)}(g, Vector{Bool}(negs))
    end
end

# ── Gate 层（未定位） ─────────────────────────────────────────────────────────
Base.inv(g::Gate) = InvGate(g)

"幂门：`pow(g, k)`。"
pow(g::Gate, k::Real) = PowGate(g, Float64(k))

"增加 `length(ctrls)` 个（正）控制比特。"
ctrl(g::Gate, ctrls::Int...) = CtrlGate(g, length(ctrls), falses(length(ctrls)))

"增加 `length(ctrls)` 个（负）控制比特。"
negctrl(g::Gate, ctrls::Int...) = CtrlGate(g, length(ctrls), trues(length(ctrls)))

# ── GateOp 层（已定位；新控制比特前置） ──────────────────────────────────────
Base.inv(op::GateOp) = GateOp(InvGate(op.gate), op.qubits, op.params)

pow(op::GateOp, k::Real) = GateOp(PowGate(op.gate, Float64(k)), op.qubits, op.params)

function ctrl(op::GateOp, ctrls::Int...)
    length(ctrls) >= 1 || throw(ArgumentError("need at least one control qubit"))
    GateOp(CtrlGate(op.gate, length(ctrls), falses(length(ctrls))), vcat(collect(Int, ctrls), op.qubits), op.params)
end

function negctrl(op::GateOp, ctrls::Int...)
    length(ctrls) >= 1 || throw(ArgumentError("need at least one control qubit"))
    GateOp(CtrlGate(op.gate, length(ctrls), trues(length(ctrls))), vcat(collect(Int, ctrls), op.qubits), op.params)
end

# ── 接口实现 ──────────────────────────────────────────────────────────────────
Base.:(==)(a::InvGate, b::InvGate) = a.g == b.g
Base.:(==)(a::PowGate, b::PowGate) = a.g == b.g && a.k == b.k
Base.:(==)(a::CtrlGate, b::CtrlGate) = a.g == b.g && a.negs == b.negs

nqubits(g::InvGate) = nqubits(g.g)
nqubits(g::PowGate) = nqubits(g.g)
nqubits(g::CtrlGate{G,K}) where {G,K} = nqubits(g.g) + K

num_params(g::ModifiedGate) = num_params(g.g)

name(g::InvGate) = Symbol("inv(", name(g.g), ")")
name(g::PowGate) = Symbol("pow(", name(g.g), ")")
name(g::CtrlGate) = (all(g.negs) ? Symbol("negctrl(", name(g.g), ")") : Symbol("ctrl(", name(g.g), ")"))

mat(g::InvGate, params::Vector{<:Real}) = adjoint(mat(g.g, params))

function mat(g::PowGate, params::Vector{<:Real})
    _matrix_pow(mat(g.g, params), g.k)
end

function mat(g::CtrlGate, params::Vector{<:Real})
    _controlled_matrix(mat(g.g, params), g.negs)
end

# U^k：整数幂用矩阵幂；否则用谱分解（酉矩阵的特征分解）。
function _matrix_pow(U::AbstractMatrix, k::Real)
    isinteger(k) && return Matrix{ComplexF64}(U^Int(k))
    k == -1 && return adjoint(U)
    E = eigen(Matrix{ComplexF64}(U))
    V = Matrix{ComplexF64}(E.vectors)
    vals = ComplexF64.(E.values)   # eigen 对实谱可能返回实数，需提升为复数
    return V * Diagonal(vals .^ Float64(k)) / V
end

# 受控矩阵：控制比特为最高位；negs[j] == true 表示第 j 个控制按 0 极性触发。
function _controlled_matrix(U::AbstractMatrix, negs::Vector{Bool})
    d = size(U, 1)
    k = length(negs)
    T = promote_type(eltype(U), Float64)
    M = zeros(T, d << k, d << k)
    for cbits in 0:(1 << k)-1
        # 最高位控制在前；正控在比特为 1 时触发，负控在比特为 0 时触发
        active = all(negs[j] != (((cbits >> (k - j)) & 1) == 1) for j in 1:k)
        base = cbits * d
        if active
            M[base+1:base+d, base+1:base+d] .= U
        else
            for i in 1:d
                M[base+i, base+i] = 1
            end
        end
    end
    return M
end
