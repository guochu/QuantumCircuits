# =============================================================================
# bits.jl — 比特与寄存器
#
# 约定：
#   * 量子比特（Qubit）为 1-based 虚拟索引（与 Julia 惯例一致）；设备定位交给
#     Layout / 下游包。
#   * 寄存器是纯元数据（服务序列化与可读性）。
#   * 寄存器内索引即全局比特编号：`r[i] == Qubit(i)`。
#   * QASM 读写层负责与 QASM 的 0-based 索引互转（见 io/qasm2.jl）。
# =============================================================================

"""虚拟量子比特：1-based 索引。"""
struct Qubit
    index::Int
end

Base.show(io::IO, q::Qubit) = print(io, "q[", q.index, "]")

"""量子寄存器（元数据）。`r[i]` 返回 `Qubit(i)`（1-based）。"""
struct QReg
    name::Symbol
    n::Int
end

Base.length(r::QReg) = r.n

function Base.getindex(r::QReg, i::Integer)
    1 <= i <= r.n || throw(BoundsError(r, i))
    Qubit(Int(i))
end
Base.getindex(r::QReg, rng::AbstractVector) = Qubit[r[Int(i)] for i in rng]
Base.show(io::IO, r::QReg) = print(io, r.name, "[", r.n, "]")

"""经典寄存器（元数据）。`r[i]`（1-based）返回经典位引用。"""
struct CReg
    name::Symbol
    n::Int
end

Base.length(r::CReg) = r.n

"""经典位引用：指向寄存器 `reg` 的第 `index` 位（1-based）。"""
struct ClbitRef
    reg::CReg
    index::Int
end

function Base.getindex(r::CReg, i::Integer)
    1 <= i <= r.n || throw(BoundsError(r, i))
    ClbitRef(r, Int(i))
end
Base.getindex(r::CReg, rng::AbstractVector) = ClbitRef[r[Int(i)] for i in rng]
Base.show(io::IO, c::ClbitRef) = print(io, c.reg.name, "[", c.index, "]")
Base.show(io::IO, r::CReg) = print(io, r.name, "[", r.n, "]")
