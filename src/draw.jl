# =============================================================================
# draw.jl — 线路文本图（ASCII / Unicode）
#
# `draw(c)` 把线路渲染为文本图（类似 Qiskit 的 text drawer）：
#
#     julia> print(draw(c))
#     q1: ──●──────
#           │
#     q2: ──X──[H]─
#
# 布局模型：每个操作占一列（`_DrawColumn`），列内记录各线上的符号（`_DrawCell`）
# 与连线跨度 [lo, hi]；`_layout` 先 `unroll!` 展开 BlockOp，再逐操作建列。
# Luxor 图形后端（包扩展）复用同一布局。
# =============================================================================

struct _DrawCell
    kind::Symbol   # :box :ctrl :negctrl :swap :measure :cltarget :barrier
    text::String
end

mutable struct _DrawColumn
    label::String
    cells::Dict{Int,_DrawCell}
    lo::Int
    hi::Int
end

_DrawColumn(label::AbstractString="") =
    _DrawColumn(String(label), Dict{Int,_DrawCell}(), typemax(Int), typemin(Int))

function _setcell!(col::_DrawColumn, wire::Int, kind::Symbol, text::AbstractString="")
    col.cells[wire] = _DrawCell(kind, String(text))
    _touch!(col, wire)
    return col
end

_touch!(col::_DrawColumn, wire::Int) =
    (col.lo = min(col.lo, wire); col.hi = max(col.hi, wire); col)

# ── 布局 ──────────────────────────────────────────────────────────────────────

"线路的线映射：量子比特 q（1-based）→ 线 q；经典位按 cregs 声明顺序线性排布。"
function _wire_maps(c::Circuit)
    coff = Dict{Symbol,Int}()
    off = 0
    for r in c.cregs
        coff[r.name] = off
        off += r.n
    end
    return c.n, coff, off
end

_param_text(p::Float64) = repr(p)
_param_text(p::Param) = string(":", p.name)
_param_text(params::Vector{GateParam}) =
    isempty(params) ? "" : string("(", join(_param_text.(params), ","), ")")

_gate_label(g::Gate, params::Vector{GateParam}) = string(name(g), _param_text(params))

function _gate_column(op::GateOp)
    col = _DrawColumn()
    qs = op.qubits
    gname = name(op.gate)
    if op.gate isa CtrlGate
        nb = nqubits(op.gate.g)
        k = length(qs) - nb
        for (j, cq) in enumerate(qs[1:k])
            _setcell!(col, cq, op.gate.negs[j] ? :negctrl : :ctrl)
        end
        _setcell!(col, qs[k+1], :box, _gate_label(op.gate.g, op.params))
        for q in qs[k+2:end]
            _touch!(col, q)
        end
    elseif gname in (:SWAP, :ISWAP)
        _setcell!(col, qs[1], :swap)
        _setcell!(col, qs[2], :swap)
    elseif gname in (:RXX, :RZZ, :MS, :CPHASE)
        col.label = _gate_label(op.gate, op.params)
        for q in qs
            _setcell!(col, q, :ctrl)
        end
    elseif gname in (:CX, :CY, :CZ, :CH)
        _setcell!(col, qs[1], :ctrl)
        _setcell!(col, qs[2], :box, string(gname)[2:2])
    elseif gname == :CCX
        _setcell!(col, qs[1], :ctrl)
        _setcell!(col, qs[2], :ctrl)
        _setcell!(col, qs[3], :box, "X")
    elseif gname == :CSWAP
        _setcell!(col, qs[1], :ctrl)
        _setcell!(col, qs[2], :swap)
        _setcell!(col, qs[3], :swap)
    elseif gname in (:CRX, :CRY, :CRZ)
        _setcell!(col, qs[1], :ctrl)
        _setcell!(col, qs[2], :box, string("R", gname[3]) * _param_text(op.params))
    else
        # 兜底：标签盒放首比特，其余比特用连线桥接
        _setcell!(col, qs[1], :box, _gate_label(op.gate, op.params))
        for q in qs[2:end]
            _touch!(col, q)
        end
    end
    return col
end

function _measure_column(op::MeasOp, nq::Int, coff::Dict{Symbol,Int})
    col = _DrawColumn()
    for (q, cb) in zip(op.qubits, op.clbits)
        _setcell!(col, q, :measure, "M")
        _setcell!(col, nq + coff[cb.reg.name] + cb.index, :cltarget)
    end
    return col
end

function _channel_text(ch::Channel)
    ch isa KrausChannel && return "K($(length(ch.ops)))"
    ch isa PauliChannel && return "P($(length(ch.paulis)))"
    ch isa UnitaryChannel && return "U($(length(ch.ops)))"
    return "N"
end

function _push_op!(cols::Vector{_DrawColumn}, op::Operation, nq::Int, coff::Dict{Symbol,Int})
    if op isa GateOp
        push!(cols, _gate_column(op))
    elseif op isa MeasOp
        push!(cols, _measure_column(op, nq, coff))
    elseif op isa ReinitOp
        col = _DrawColumn()
        for q in op.qubits
            _setcell!(col, q, :box, "|0>")
        end
        push!(cols, col)
    elseif op isa BarrierOp
        col = _DrawColumn()
        for q in op.qubits
            _setcell!(col, q, :barrier)
        end
        push!(cols, col)
    elseif op isa ChannelOp
        col = _DrawColumn()
        qs = qubits(op)
        _setcell!(col, qs[1], :box, _channel_text(op.channel))
        for q in qs[2:end]
            _touch!(col, q)
        end
        push!(cols, col)
    elseif op isa IfOp
        col = _DrawColumn("if (" * string(op.cond) * ")")
        for q in qubits(op)
            _setcell!(col, q, :box, "IF")
        end
        for i in 1:length(op.cond.reg)
            _touch!(col, nq + coff[op.cond.reg.name] + i)
        end
        push!(cols, col)
        for o in op.then.ops
            _push_op!(cols, o, nq, coff)
        end
        if op.otherwise !== nothing
            col2 = _DrawColumn("else")
            for q in qubits(op.otherwise)
                _setcell!(col2, q, :box, "ELSE")
            end
            push!(cols, col2)
            for o in op.otherwise.ops
                _push_op!(cols, o, nq, coff)
            end
        end
    elseif op isa BlockOp
        col = _DrawColumn(op.n > 1 ? string(op.name, " ×", op.n) : string(op.name))
        for q in qubits(op)
            _setcell!(col, q, :box, string(op.name))
        end
        push!(cols, col)
    else
        error("cannot draw operation of type $(typeof(op))")
    end
    return cols
end

function _layout(c::Circuit)
    nq, coff, ncl = _wire_maps(c)
    cols = _DrawColumn[]
    tmp = copy(c)
    unroll!(tmp)
    for op in tmp.ops
        _push_op!(cols, op, nq, coff)
    end
    return cols, nq, coff, ncl
end

# ── 文本渲染 ──────────────────────────────────────────────────────────────────

"""
    draw(c::Circuit; ascii::Bool=false) -> String

把线路渲染为文本图。默认使用 Unicode 符号（`● ● ✕ ░` 等）；
`ascii = true` 时使用纯 ASCII 符号。

```julia
julia> c = Circuit(2)
julia> push!(c, H(1))
julia> push!(c, CX(1, 2))
julia> print(draw(c))
q1: ─H──●─
     │
q2: ────X─
```
"""
function draw(c::Circuit; ascii::Bool=false)
    cols, nq, coff, ncl = _layout(c)
    uni = !ascii
    FQ = uni ? "─" : "-"
    FC = uni ? "═" : "="
    VL = uni ? "│" : "|"
    CTRL = uni ? "●" : "*"
    NEG = uni ? "○" : "o"
    SW = uni ? "✕" : "x"
    BA = uni ? "░" : "#"
    CLT = uni ? "╡" : ">"
    kindchar = Dict{Symbol,String}(
        :ctrl => CTRL, :negctrl => NEG, :swap => SW, :barrier => BA, :cltarget => CLT,
    )

    nw = nq + ncl
    widths = [3 for _ in cols]
    for (i, col) in enumerate(cols)
        w = 3
        isempty(col.label) || (w = max(w, textwidth(col.label) + 2))
        for cell in values(col.cells)
            w = max(w, textwidth(cell.text) + 2)
        end
        widths[i] = w
    end

    prefixes = String[]
    for i in 1:nq
        push!(prefixes, "q$i: ")
    end
    for r in c.cregs, j in 1:r.n
        push!(prefixes, string(r.name, "[", j, "]: "))
    end
    maxp = maximum(textwidth, prefixes; init=0)

    _center(s, w, f) = begin
        total = max(w - textwidth(s), 0)
        l = total ÷ 2
        repeat(f, l) * s * repeat(f, total - l)
    end

    io = IOBuffer()
    if any(!isempty(col.label) for col in cols)
        print(io, repeat(" ", maxp))
        for (i, col) in enumerate(cols)
            print(io, _center(col.label, widths[i], " "))
        end
        println(io)
    end
    for r in 1:nw
        if r > 1
            # 连接线行：位于线 r-1 与线 r 之间（无任何连线时跳过该行）
            row = String[]
            hasline = false
            for (i, col) in enumerate(cols)
                if col.lo < r <= col.hi
                    push!(row, _center(VL, widths[i], " "))
                    hasline = true
                else
                    push!(row, repeat(" ", widths[i]))
                end
            end
            hasline && (print(io, repeat(" ", maxp)); println(io, join(row)))
        end
        fill = r <= nq ? FQ : FC
        print(io, lpad(prefixes[r], maxp))
        for (i, col) in enumerate(cols)
            cell = get(col.cells, r, nothing)
            if cell === nothing
                print(io, repeat(fill, widths[i]))
            elseif cell.kind === :box || cell.kind === :measure
                print(io, _center(cell.text, widths[i], fill))
            else
                print(io, _center(kindchar[cell.kind], widths[i], fill))
            end
        end
        println(io)
    end
    return String(take!(io))
end

"""
    draw(io::IO, c::Circuit; ascii::Bool=false)

把文本图写入 `io`。
"""
draw(io::IO, c::Circuit; ascii::Bool=false) = print(io, draw(c; ascii=ascii))

Base.show(io::IO, ::MIME"text/plain", c::Circuit) = print(io, draw(c))
