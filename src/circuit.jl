# =============================================================================
# circuit.jl — Circuit 容器 + 构造 DSL + 分析 + 参数绑定
#
# 线路 = Operation 的有序序列 + 寄存器元数据 + 布局信息。
# 有序 Vector 表示，按需 dag()（原生 DAG 容器留给分析/编译时转换）。
# =============================================================================

"""布局（一等公民）：线路比特 → 设备比特的映射与输出置换。"""
struct Layout
    initial::Union{Nothing,Vector{Int}}   # circuit qubit → device qubit
    output::Union{Nothing,Vector{Int}}    # 输出置换（测量位置）
end

Layout() = Layout(nothing, nothing)

"""量子线路容器。"""
mutable struct Circuit
    ops::Vector{Operation}
    n::Int                                # 量子比特数
    qregs::Vector{QReg}
    cregs::Vector{CReg}
    layout::Layout
end

# ── 构造 ──────────────────────────────────────────────────────────────────────
"最常用构造：`Circuit(n)`；默认带 qreg :q 与 creg :c（尺寸均为 n）。"
function Circuit(n::Integer;
                 qregs::Vector{QReg}=[QReg(:q, Int(n))],
                 cregs::Vector{CReg}=[CReg(:c, Int(n))],
                 layout::Layout=Layout())
    n >= 0 || throw(ArgumentError("number of qubits must be non-negative"))
    return Circuit(Operation[], Int(n), qregs, cregs, layout)
end

"由操作序列构造（自动推断比特数，可用关键字覆盖）。"
function Circuit(ops::Vector{<:Operation};
                 n::Union{Nothing,Integer}=nothing,
                 qregs::Union{Nothing,Vector{QReg}}=nothing,
                 cregs::Union{Nothing,Vector{CReg}}=nothing,
                 layout::Layout=Layout())
    if n === nothing
        n = isempty(ops) ? 0 : maximum(maximum(qubits(op); init=-1) for op in ops) + 1
    end
    qregs === nothing && (qregs = [QReg(:q, Int(n))])
    cregs === nothing && (cregs = [CReg(:c, Int(n))])
    return Circuit(collect(Operation, ops), Int(n), qregs, cregs, layout)
end

nqubits(c::Circuit) = c.n

# ── 容器接口 ──────────────────────────────────────────────────────────────────
Base.length(c::Circuit) = length(c.ops)
Base.isempty(c::Circuit) = isempty(c.ops)
Base.empty!(c::Circuit) = (empty!(c.ops); c)
Base.getindex(c::Circuit, i::Integer) = c.ops[i]
Base.getindex(c::Circuit, rng) = c.ops[rng]
Base.setindex!(c::Circuit, v::Operation, i::Integer) = setindex!(c.ops, v, i)
Base.firstindex(c::Circuit) = firstindex(c.ops)
Base.lastindex(c::Circuit) = lastindex(c.ops)
Base.iterate(c::Circuit, state...) = iterate(c.ops, state...)
Base.eltype(::Type{Circuit}) = Operation
Base.copy(c::Circuit) = Circuit(copy(c.ops), c.n, copy(c.qregs), copy(c.cregs), c.layout)
Base.similar(c::Circuit) = Circuit(Int(c.n); qregs=copy(c.qregs), cregs=copy(c.cregs))
Base.reverse(c::Circuit) = Circuit(reverse(c.ops); n=c.n, qregs=copy(c.qregs), cregs=copy(c.cregs), layout=c.layout)

Base.:(==)(a::Circuit, b::Circuit) =
    a.ops == b.ops && a.n == b.n && a.qregs == b.qregs && a.cregs == b.cregs

# ── 构造 DSL ──────────────────────────────────────────────────────────────────
"追加操作（主入口）。"
Base.push!(c::Circuit, op::Operation) = (push!(c.ops, op); c)

"便利重载：`push!(c, H, 1)`、`push!(c, RX, π/2, 3)`。"
Base.push!(c::Circuit, g::Gate, args...) = push!(c, g(args...))

"拼接另一条线路（共享寄存器引用，不复制操作）。"
Base.append!(c::Circuit, other::Circuit) = (append!(c.ops, other.ops); c)
Base.append!(c::Circuit, ops::Vector{<:Operation}) = (append!(c.ops, ops); c)

"`c1 * c2`：`append!` 的纯函数版（先 c1 后 c2）。"
Base.:*(c1::Circuit, c2::Circuit) = append!(copy(c1), c2)

"管道糖：`c << H(1) << CX(1, 2)`。"
Base.:(<<)(c::Circuit, op::Operation) = push!(c, op)
Base.:(<<)(c::Circuit, other::Circuit) = append!(c, other)

# ── 参数 ──────────────────────────────────────────────────────────────────────
"收集线路中的符号参数（去重、按首次出现顺序；顺序确定性是契约）。"
function parameters(c::Circuit)
    seen = Param[]
    _collect_params!(seen, c)
    return seen
end

function _collect_params!(acc::Vector{Param}, c::Circuit)
    for op in c.ops
        _collect_params!(acc, op)
    end
    return acc
end

function _collect_params!(acc::Vector{Param}, op::GateOp)
    for p in op.params
        p isa Param || continue
        p in acc || push!(acc, p)
    end
    return acc
end
# BlockOp / IfOp 的收集方法见 composite.jl / classical.jl（类型定义在后者）
_collect_params!(acc::Vector{Param}, ::Operation) = acc

_param_key(p::Param) = p
_param_key(s::Symbol) = Param(s)

_param_table_entry!(t::Dict{Param,Float64}, k::Union{Param,Symbol,ParamVector}, v::Real) =
    (t[_param_key(k)] = Float64(v); t)
function _param_table_entry!(t::Dict{Param,Float64}, pv::ParamVector, vs::AbstractVector{<:Real})
    length(vs) == length(pv) ||
        throw(ArgumentError("ParamVector :$(pv.name) has $(pv.n) entries, got $(length(vs)) values"))
    for (i, v) in enumerate(vs)
        t[pv[i]] = Float64(v)
    end
    return t
end

function _param_table(table::AbstractDict)
    t = Dict{Param,Float64}()
    for (k, v) in table
        _param_table_entry!(t, k, v)
    end
    return t
end

"绑定单个参数（纯函数）：`assign(c, :θ, 0.3)` / `assign(c, Param(:θ), 0.3)`。"
assign(c::Circuit, p::Union{Param,Symbol}, value::Real) = assign!(copy(c), p, value)

"绑定参数向量（纯函数）：`assign(c, φ, [π/4, 0.5])`。"
assign(c::Circuit, pv::ParamVector, values::AbstractVector{<:Real}) = assign!(copy(c), pv, values)

"按参数表绑定（纯函数）：`assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5]))`。"
assign(c::Circuit, table::AbstractDict) = assign!(copy(c), table)

assign!(c::Circuit, p::Union{Param,Symbol}, value::Real) = assign!(c, Dict(p => value))
assign!(c::Circuit, pv::ParamVector, values::AbstractVector{<:Real}) = assign!(c, Dict(pv => values))

"就地绑定参数。"
function assign!(c::Circuit, table::AbstractDict)
    t = _param_table(table)
    isempty(t) && return c
    for i in eachindex(c.ops)
        c.ops[i] = _assign_op(c.ops[i], t)
    end
    return c
end

function _assign_op(op::GateOp, t::Dict{Param,Float64})
    any(p -> p isa Param && haskey(t, p), op.params) || return op
    ps = GateParam[p isa Param && haskey(t, p) ? t[p] : p for p in op.params]
    return GateOp(op.gate, op.qubits, ps)
end
# BlockOp / IfOp 的绑定方法见 composite.jl / classical.jl
_assign_op(op::Operation, ::Dict{Param,Float64}) = op

# ── 分析（IR 内只放最基础的） ─────────────────────────────────────────────────
"线路深度：量子比特 + 经典位依赖图上的最长链。"
function depth(c::Circuit)
    qlayer = Dict{Int,Int}()
    clayer = Dict{ClbitRef,Int}()
    d = 0
    for op in c.ops
        qs, cs = qubits(op), clbits(op)
        layer = 1 + max(
            maximum((get(qlayer, q, 0) for q in qs); init=0),
            maximum((get(clayer, cb, 0) for cb in cs); init=0),
        )
        for q in qs
            qlayer[q] = layer
        end
        for cb in cs
            clayer[cb] = layer
        end
        d = max(d, layer)
    end
    return d
end

"操作总数。"
num_ops(c::Circuit) = length(c.ops)

"按操作种类计数：`count_ops(c) -> Dict{Symbol,Int}`。"
count_ops(c::Circuit) = _count_ops(c.ops)

function _count_ops(ops::Vector{Operation})
    counts = Dict{Symbol,Int}()
    for op in ops
        k = _op_kind(op)
        counts[k] = get(counts, k, 0) + 1
    end
    return counts
end

_op_kind(op::GateOp) = name(op.gate)
_op_kind(::MeasOp) = :measure
_op_kind(::ResetOp) = :reset
_op_kind(::BarrierOp) = :barrier
_op_kind(::ChannelOp) = :channel
# IfOp / BlockOp 的分类方法见 classical.jl / composite.jl

"线路使用的量子比特（升序）。"
function qubits_used(c::Circuit)
    s = Set{Int}()
    for op in c.ops
        union!(s, qubits(op))
    end
    return sort!(collect(s))
end

"线路使用的经典位（首次出现序、去重）。"
function clbits_used(c::Circuit)
    out = ClbitRef[]
    for op in c.ops
        for cb in clbits(op)
            cb in out || push!(out, cb)
        end
    end
    return out
end

"逆线路：逆序 + 逐操作求逆（要求所有操作酉）。"
function dagger(c::Circuit)
    return Circuit(Operation[inv(op) for op in reverse(c.ops)];
                   n=c.n, qregs=copy(c.qregs), cregs=copy(c.cregs), layout=c.layout)
end

"把整条线路酉合成到一个矩阵（内部工具：UserGate 延迟分解 / 测试用）。"
function _compose_unitary(c::Circuit, n::Int=c.n; table::Union{Nothing,AbstractDict}=nothing)
    d = 1 << n
    M = Matrix{ComplexF64}(I, d, d)
    for op in c.ops
        is_unitary(op) || throw(ArgumentError("circuit contains non-unitary operation: $op"))
        M = _embed(mat(op, table), qubits(op), n) * M
    end
    return M
end

"合法性检查：索引越界 / 引用合法性。通过时返回线路本身。"
function validate(c::Circuit)
    for op in c.ops
        for q in qubits(op)
            0 <= q < c.n || throw(ArgumentError("qubit index $q out of range [0, $(c.n)) in $op"))
        end
        for cb in clbits(op)
            cb.reg in c.cregs ||
                throw(ArgumentError("clbit reference $(cb.reg.name) is not a register of this circuit"))
            1 <= cb.index <= length(cb.reg) ||
                throw(ArgumentError("clbit index $(cb.index) out of range in register $(cb.reg.name)"))
        end
        if op isa MeasOp
            length(op.qubits) == length(op.clbits) ||
                throw(ArgumentError("mismatched measure lengths"))
        end
        op isa BlockOp && _validate_block(op)
        if op isa IfOp
            validate(op.then)
            op.otherwise === nothing || validate(op.otherwise)
        end
    end
    return c
end

"全部测量到同尺寸 creg。"
function measure_all!(c::Circuit)
    cr = nothing
    for r in c.cregs
        if length(r) == c.n
            cr = r
            break
        end
    end
    cr === nothing && throw(ArgumentError("no creg of size $(c.n); construct with cregs=[CReg(:c, $c.n)]"))
    for q in 0:c.n-1
        push!(c, measure(q, cr[q+1]))
    end
    return c
end

# ── 显示 ──────────────────────────────────────────────────────────────────────
Base.show(io::IO, c::Circuit) = print(io, "Circuit(n=", c.n, ", ops=", length(c.ops), ")")

function Base.show(io::IO, ::MIME"text/plain", c::Circuit)
    print(io, "Circuit(n=", c.n, ", ops=", length(c.ops), ")")
    for (i, op) in enumerate(c.ops)
        print(io, "\n  ", i, ": ", op)
    end
end
