# =============================================================================
# classical.jl — 经典层一等公民：条件表达式 / IfOp
#
# 经典寄存器、测量写回、条件分支进 IR（QEC 综合与动态线路的硬前提）。
# v1 只做寄存器比较 + IfOp；while/for 留给 v2（类型层次开放，不破坏兼容）。
# =============================================================================

"""最小条件：寄存器值与整数的比较，`op ∈ (:(==), :(≠), :(≥), :(≤))`。"""
struct Cond
    reg::CReg
    op::Symbol
    value::Int
end

Base.show(io::IO, c::Cond) = print(io, c.reg.name, " ", c.op, " ", c.value)

# 语法糖：c == 3、c ≠ 3、c ≥ 3、c ≤ 3；单个经典位 c[0] == 1 同样得到 Cond。
# 注意：这使 CReg/ClbitRef 与 Int 的 `==` 返回 Cond 而非 Bool（有意为之）。
Base.:(==)(r::CReg, v::Integer) = Cond(r, :(==), Int(v))
Base.:(==)(v::Integer, r::CReg) = Cond(r, :(==), Int(v))
Base.:(≠)(r::CReg, v::Integer) = Cond(r, :≠, Int(v))
Base.:(≠)(v::Integer, r::CReg) = Cond(r, :≠, Int(v))
Base.:(≥)(r::CReg, v::Integer) = Cond(r, :≥, Int(v))
Base.:(≤)(r::CReg, v::Integer) = Cond(r, :≤, Int(v))
Base.:(==)(c::ClbitRef, v::Integer) = Cond(c.reg, :(==), Int(v))
Base.:(==)(v::Integer, c::ClbitRef) = Cond(c.reg, :(==), Int(v))
Base.:(≠)(c::ClbitRef, v::Integer) = Cond(c.reg, :≠, Int(v))

"""经典条件分支操作（then / else 子线路）。"""
struct IfOp <: Operation
    cond::Cond
    then::Circuit
    otherwise::Union{Nothing,Circuit}
end

function qubits(op::IfOp)
    s = Set{Int}(qubits_used(op.then))
    op.otherwise === nothing || union!(s, qubits_used(op.otherwise))
    return sort!(collect(s))
end

function clbits(op::IfOp)
    out = ClbitRef[ClbitRef(op.cond.reg, i) for i in 1:length(op.cond.reg)]
    append!(out, clbits_used(op.then))
    op.otherwise === nothing || append!(out, clbits_used(op.otherwise))
    return unique(out)
end

Base.:(==)(a::IfOp, b::IfOp) =
    a.cond == b.cond && a.then == b.then && isnothing(a.otherwise) == isnothing(b.otherwise) &&
    (isnothing(a.otherwise) || a.otherwise == b.otherwise)

Base.show(io::IO, op::IfOp) = begin
    print(io, "if (", op.cond, ") { ", op.then, " }")
    op.otherwise === nothing || print(io, " else { ", op.otherwise, " }")
end

"""
向线路追加 IfOp：

    if_then(c, cond, then; otherwise=nothing)
"""
function if_then(c::Circuit, cond::Cond, then::Circuit; otherwise::Union{Nothing,Circuit}=nothing)
    return push!(c, IfOp(cond, then, otherwise))
end

# ── 接入 circuit.jl 的通用协议 ────────────────────────────────────────────────
function _collect_params!(acc::Vector{Param}, op::IfOp)
    _collect_params!(acc, op.then)
    op.otherwise === nothing || _collect_params!(acc, op.otherwise)
    return acc
end

function _assign_op(op::IfOp, t::Dict{Param,Float64})
    then′ = assign!(copy(op.then), t)
    otherwise′ = op.otherwise === nothing ? nothing : assign!(copy(op.otherwise), t)
    IfOp(op.cond, then′, otherwise′)
end

_op_kind(::IfOp) = :if
