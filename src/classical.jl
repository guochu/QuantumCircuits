# =============================================================================
# classical.jl — 经典层一等公民：条件表达式 / IfOp
#
# 经典寄存器、测量写回、条件分支进 IR（QEC 综合与动态线路的硬前提）。
# v1 只做寄存器比较 + IfOp；while/for 留给 v2（类型层次开放，不破坏兼容）。
# =============================================================================

"""最小条件：寄存器值（或单个经典位）与整数的比较，
`op ∈ (:(==), :(≠), :(≥), :(≤))`。`bit = nothing` 比较整寄存器值；
`bit = i` 只比较第 `i` 位。"""
struct Cond
    reg::CReg
    op::Symbol
    value::Int
    bit::Union{Nothing,Int}

    Cond(reg::CReg, op::Symbol, value::Int) = new(reg, op, value, nothing)
    Cond(reg::CReg, op::Symbol, value::Int, bit::Union{Nothing,Int}) =
        new(reg, op, value, bit)
end

function Base.show(io::IO, c::Cond)
    c.bit === nothing ?
    print(io, c.reg.name, " ", c.op, " ", c.value) :
    print(io, c.reg.name, "[", c.bit, "] ", c.op, " ", c.value)
end

# 语法糖：c == 3、c ≠ 3、c ≥ 3、c ≤ 3；单个经典位 c[i] == 1 得到按位比较的 Cond。
# 注意：这使 CReg/ClbitRef 与 Int 的 `==` 返回 Cond 而非 Bool（有意为之）。
Base.:(==)(r::CReg, v::Integer) = Cond(r, :(==), Int(v))
Base.:(==)(v::Integer, r::CReg) = Cond(r, :(==), Int(v))
Base.:(≠)(r::CReg, v::Integer) = Cond(r, :≠, Int(v))
Base.:(≠)(v::Integer, r::CReg) = Cond(r, :≠, Int(v))
Base.:(≥)(r::CReg, v::Integer) = Cond(r, :≥, Int(v))
Base.:(≤)(r::CReg, v::Integer) = Cond(r, :≤, Int(v))
Base.:(==)(c::ClbitRef, v::Integer) = Cond(c.reg, :(==), Int(v), c.index)
Base.:(==)(v::Integer, c::ClbitRef) = Cond(c.reg, :(==), Int(v), c.index)
Base.:(≠)(c::ClbitRef, v::Integer) = Cond(c.reg, :≠, Int(v), c.index)

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
    out = ClbitRef[]
    if op.cond.bit === nothing
        # 整寄存器条件：条件寄存器全部位都参与依赖
        append!(out, ClbitRef(op.cond.reg, i) for i in 1:length(op.cond.reg))
    else
        # 按位条件：只依赖被比较的那一位
        push!(out, ClbitRef(op.cond.reg, op.cond.bit))
    end
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
