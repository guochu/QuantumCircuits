# =============================================================================
# ops.jl — Operation 抽象 + 内置指令 + 门调用定位
#
# Operation 是**开放扩展点**：下游（QCCD 编译器、QEC）自定义新指令只需实现
# 最小协议（4.10 节）：
#     qubits(op)             # 必实现
#     clbits(op)             # 默认 []
#     is_unitary(op)         # 默认 false
#     mat(op)                # 仅酉操作需要
# =============================================================================

"""Operation：线路中**已定位**的指令（IR 的基本单元，开放类型）。"""
abstract type Operation end

# ── Operation 最小协议 ────────────────────────────────────────────────────────
"操作涉及的量子比特（最小契约：每个 Operation 必须实现）。"
qubits(op::Operation) = error("qubits(op::$(typeof(op))) not implemented; every Operation must implement the `qubits` protocol")

"操作涉及的经典位（默认空）。"
clbits(::Operation) = ClbitRef[]

"是否酉操作（默认 false；GateOp 为 true）。"
is_unitary(::Operation) = false

"酉操作的矩阵（仅酉操作需要实现）。"
mat(op::Operation) = error("`mat` not defined for $(typeof(op)); only unitary operations have matrices.")

Base.:(==)(a::Operation, b::Operation) = isequal(a, b)

# ── GateOp：酉门（Gate + qubits + params） ───────────────────────────────────
const GateParam = Union{Float64,Param}

"""酉门操作：`GateOp(gate, qubits, params)`；通常由门调用产生（`H(1)`、`RX(π/2, 3)`）。"""
struct GateOp <: Operation
    gate::Gate
    qubits::Vector{Int}
    params::Vector{GateParam}

    function GateOp(gate::Gate, qubits::Vector{Int}, params::Vector)
        length(qubits) == nqubits(gate) ||
            throw(ArgumentError("$(name(gate)) acts on $(nqubits(gate)) qubits, got $(length(qubits))"))
        # convert（而非推导式）对自动微分友好
        new(gate, qubits, convert(Vector{GateParam}, params))
    end
end

GateOp(g::Gate, qubits::Vector{Int}) = GateOp(g, qubits, GateParam[])
GateOp(g::Gate, qubits::Vector{<:Integer}, params::Vector=GateParam[]) =
    GateOp(g, collect(Int, qubits), params)

qubits(op::GateOp) = op.qubits
is_unitary(::GateOp) = true
name(op::GateOp) = name(op.gate)

"按符号参数求矩阵；`table`（Param/Symbol => 值）可选。未绑定参数时报错。"
function mat(op::GateOp, table::Union{Nothing,AbstractDict}=nothing)
    isempty(op.params) && return mat(op.gate)
    vals = Float64[_param_value(p, table) for p in op.params]
    return mat(op.gate, vals)
end

"按位置参数求矩阵（顺序与 parameters(op) 一致）。"
function mat(op::GateOp, vals::Vector{<:Real})
    isempty(op.params) && return mat(op.gate)
    return mat(op.gate, collect(Float64, vals))
end

_param_value(p::Float64, ::Union{Nothing,AbstractDict}) = p
_param_value(p::Param, ::Nothing) =
    throw(ArgumentError("unbound parameter $(p.name); use `bind` or pass a parameter table to `mat`"))
_param_value(p::Param, table::AbstractDict) =
    haskey(table, p) ? Float64(table[p]) :
    haskey(table, p.name) ? Float64(table[p.name]) :
    throw(ArgumentError("unbound parameter $(p.name)"))

"操作中的符号参数（按序）。"
parameters(op::GateOp) = Param[p for p in op.params if p isa Param]

# ── 门调用即定位（统一处理：参数…, 比特…） ───────────────────────────────────
_param_of_gate(a::Symbol, g::Gate) = Param(a)
_param_of_gate(a::Param, g::Gate) = a
_param_of_gate(a::Real, g::Gate) = Float64(a)
_param_of_gate(a, g::Gate) =
    throw(ArgumentError("invalid parameter type $(typeof(a)) for $(name(g))"))

function (g::Gate)(args::Union{Real,Param,Symbol,Integer}...)
    np, nq = num_params(g), nqubits(g)
    length(args) == np + nq ||
        throw(ArgumentError("$(name(g)) expects $np parameter(s) and $nq qubit(s), got $(length(args)) arguments"))
    # 无 push!/setindex!/推导式的构造（对自动微分友好）
    ps = Base.vect(map(a -> _param_of_gate(a, g), args[1:np])...)
    qs = Base.vect(map(a -> Int(a), args[np+1:end])...)
    GateOp(g, qs, ps)
end

Base.:(==)(a::GateOp, b::GateOp) = a.gate == b.gate && a.qubits == b.qubits && a.params == b.params

# ── 测量 / 重置 / 屏障 ────────────────────────────────────────────────────────
"""测量：量子比特 → 经典位。"""
struct MeasOp <: Operation
    qubits::Vector{Int}
    clbits::Vector{ClbitRef}

    function MeasOp(qubits::Vector{Int}, clbits::Vector{ClbitRef})
        length(qubits) == length(clbits) ||
            throw(ArgumentError("number of qubits ($(length(qubits))) must match number of clbits ($(length(clbits)))"))
        new(qubits, clbits)
    end
end

"测量一组量子比特到一组经典位。"
function measure(qubits::AbstractVector{<:Integer}, clbits::AbstractVector{ClbitRef})
    MeasOp(collect(Int, qubits), collect(ClbitRef, clbits))
end

"测量单个量子比特到单个经典位。"
measure(q::Integer, c::ClbitRef) = MeasOp([Int(q)], [c])

qubits(op::MeasOp) = op.qubits
clbits(op::MeasOp) = op.clbits
Base.:(==)(a::MeasOp, b::MeasOp) = a.qubits == b.qubits && a.clbits == b.clbits

"""重置到 |0⟩。"""
struct ReinitOp <: Operation
    qubits::Vector{Int}
end

"""
    reinit(q)

构造把量子比特 `q`（1-based）重置到 |0⟩ 的 `ReinitOp`。
"""
reinit(q::Integer) = ReinitOp([Int(q)])

qubits(op::ReinitOp) = op.qubits
Base.:(==)(a::ReinitOp, b::ReinitOp) = a.qubits == b.qubits

"""屏障：调度/优化提示，无量子语义。"""
struct BarrierOp <: Operation
    qubits::Vector{Int}
end

"屏障：`barrier(0, 1, 2)`。"
barrier(qubits::Int...) = BarrierOp(collect(qubits))

qubits(op::BarrierOp) = op.qubits
Base.:(==)(a::BarrierOp, b::BarrierOp) = a.qubits == b.qubits

# ── 噪声信道指令 ──────────────────────────────────────────────────────────────
"""噪声信道操作：信道 + 定位比特。由 `KrausOp` / `PauliError` / `Depolarizing` 等产生。"""
struct ChannelOp <: Operation
    channel::Channel
    qubits::Vector{Int}
end

"将信道定位到比特上。"
KrausOp(ch::Channel, qubits::AbstractVector{<:Integer}) = ChannelOp(ch, collect(Int, qubits))
KrausOp(ch::Channel, q::Integer) = ChannelOp(ch, [Int(q)])

qubits(op::ChannelOp) = op.qubits
kraus(op::ChannelOp) = kraus(op.channel)
Base.:(==)(a::ChannelOp, b::ChannelOp) = a.qubits == b.qubits && _channel_eq(a.channel, b.channel)

function _channel_eq(a::Channel, b::Channel)
    a === b && return true
    kraus(a) == kraus(b)
end

# ── 通用求逆（dagger 用） ────────────────────────────────────────────────────
Base.inv(op::Operation) = error("cannot invert operation of type $(typeof(op)); only unitary operations can be inverted.")

# ── 显示 ─────────────────────────────────────────────────────────────────────
function _show_params(io::IO, params::Vector{GateParam})
    isempty(params) && return
    print(io, "(")
    for (i, p) in enumerate(params)
        i > 1 && print(io, ", ")
        p isa Param ? print(io, ":", p.name) : print(io, p)
    end
    print(io, ")")
end

function _gate_expr(io::IO, g::Gate)
    if g isa InvGate
        print(io, "inv("); _gate_expr(io, g.g); print(io, ")")
    elseif g isa PowGate
        print(io, "pow("); _gate_expr(io, g.g); print(io, ", ", g.k, ")")
    elseif g isa CtrlGate
        print(io, all(g.negs) ? "negctrl(" : "ctrl(")
        _gate_expr(io, g.g); print(io, ")")
    else
        print(io, name(g))
    end
end

function Base.show(io::IO, op::GateOp)
    _gate_expr(io, op.gate)
    _show_params(io, op.params)
    join(io, ["q[$q]" for q in op.qubits], ", ")
end

function Base.show(io::IO, op::MeasOp)
    print(io, "measure ")
    join(io, ["q[$q]→$(c.reg.name)[$(c.index-1)]" for (q, c) in zip(op.qubits, op.clbits)], ", ")
end

Base.show(io::IO, op::ReinitOp) = (print(io, "reset "); join(io, ["q[$q]" for q in op.qubits], ", "))
Base.show(io::IO, op::BarrierOp) = (print(io, "barrier "); join(io, ["q[$q]" for q in op.qubits], ", "))
Base.show(io::IO, op::ChannelOp) = (print(io, "channel(", length(kraus(op.channel)), " ops) "); join(io, ["q[$q]" for q in op.qubits], ", "))
