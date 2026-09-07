# =============================================================================
# composite.jl — UserGate（定义层复合门）+ BlockOp（定位层结构块）
#
# 分工：
#   * UserGate 是**定义层**：无定位、必须全酉、可参数化、可被 ctrl/inv 修饰、
#     可复用（"定义一个新门"）。
#   * BlockOp 是**定位层**：已绑定具体比特、可含测量/屏障/经典控制、
#     用于命名分组 / 优化区域 / 重复轮次（"圈出一块并命名"）。
#
# 注：两者都持有 Circuit 字段，故定义在 circuit.jl 之后。
# =============================================================================

# ── 矩阵嵌入工具（小端序） ───────────────────────────────────────────────────
# 把 k 比特门矩阵 M（qs[1] 为矩阵最高位）嵌入 n 比特空间；
# 比特号为 1-based（qubit 1 为最低位，内部位移时减 1）。

_extract_bits(x::Int, qs::Vector{Int}, k::Int) = begin
    v = 0
    for j in 1:k
        v = (v << 1) | ((x >> (qs[j] - 1)) & 1)
    end
    v
end

_scatter_bits(v::Int, qs::Vector{Int}, k::Int) = begin
    x = 0
    for j in 1:k
        x |= ((v >> (k - j)) & 1) << (qs[j] - 1)
    end
    x
end

_clear_bits(x::Int, qs::Vector{Int}) = begin
    y = x
    for q in qs
        y &= ~(1 << (q - 1))
    end
    y
end

function _embed(M::AbstractMatrix, qs::Vector{Int}, n::Int)
    k = length(qs)
    size(M) == (1 << k, 1 << k) ||
        throw(ArgumentError("matrix size $(size(M)) does not match $(k) qubits"))
    length(unique(qs)) == k || throw(ArgumentError("qubits must be distinct"))
    all(q -> 1 <= q <= n, qs) || throw(ArgumentError("qubit index out of range for n=$n"))
    d = 1 << n
    out = zeros(ComplexF64, d, d)
    for gcol in 0:d-1
        lc = _extract_bits(gcol, qs, k)
        base = _clear_bits(gcol, qs)
        for lrow in 0:(1 << k)-1
            grow = base | _scatter_bits(lrow, qs, k)
            out[grow+1, gcol+1] = M[lrow+1, lc+1]
        end
    end
    return out
end

# ── UserGate ──────────────────────────────────────────────────────────────────
"""用户自定义门（定义层）：显式矩阵，或子线路定义（延迟分解）；比特数 `N` 为类型参数。

`T` 为矩阵元素类型（矩阵定义时由输入推断；子线路定义时为名义值 `ComplexF64`，
`mat` 返回按 body 实际提升的类型）。
"""
struct UserGate{N,T<:Number} <: Gate
    name::Symbol
    nparams::Int
    matrix::Union{Nothing,Matrix{T}}
    def::Union{Nothing,Circuit}

    function UserGate(name::Symbol, matrix::AbstractMatrix)
        size(matrix, 1) == size(matrix, 2) || throw(ArgumentError("matrix must be square"))
        d = size(matrix, 1)
        d >= 2 && (d & (d - 1)) == 0 ||
            throw(ArgumentError("matrix dimension must be a power of two (>= 2), got $d"))
        _check_unitary(matrix)
        T0 = eltype(matrix)
        T = T0 <: Integer ? Float64 : T0 <: Complex{<:Integer} ? ComplexF64 : T0
        m = T === T0 ? copy(matrix) : Matrix{T}(matrix)
        new{Int(log2(d)),T}(name, 0, m, nothing)
    end

    function UserGate(name::Symbol, n::Integer, def::Circuit)
        all(is_unitary, def.ops) ||
            throw(ArgumentError("UserGate definition must be fully unitary; use BlockOp for non-unitary grouping"))
        qmax = maximum(qubits_used(def); init=0)
        qmax <= n || throw(ArgumentError("definition uses qubit $qmax beyond declared n=$n"))
        new{Int(n),ComplexF64}(name, length(parameters(def)), nothing, def)
    end
end

"`usergate(name, matrix)(pos...)`：与旧包 `QuantumGate(pos, matrix)` 对应的糖。"
usergate(name::Symbol, matrix::AbstractMatrix) = UserGate(name, matrix)

nqubits(::UserGate{N}) where {N} = N
num_params(g::UserGate) = g.nparams
name(g::UserGate) = g.name

mat(g::UserGate{N}) where {N} = g.matrix !== nothing ? g.matrix :
    g.nparams == 0 ? _compose_unitary(g.def, N) :
    throw(ArgumentError("$(g.name) is parameterized; call mat(g, params)"))

function mat(g::UserGate{N}, params::Vector{<:Real}) where {N}
    g.matrix !== nothing && return g.matrix
    table = Dict{Param,Float64}(p => Float64(v) for (p, v) in zip(parameters(g.def), params))
    length(table) == g.nparams ||
        throw(ArgumentError("$(g.name) expects $(g.nparams) parameters, got $(length(params))"))
    return _compose_unitary(g.def, N; table=table)
end

Base.:(==)(a::UserGate, b::UserGate) =
    nqubits(a) == nqubits(b) && a.name == b.name && a.nparams == b.nparams &&
    isnothing(a.matrix) == isnothing(b.matrix) &&
    (isnothing(a.matrix) || a.matrix == b.matrix) &&
    isnothing(a.def) == isnothing(b.def) &&
    (isnothing(a.def) || a.def == b.def)

# ── BlockOp ───────────────────────────────────────────────────────────────────
"""
结构块（定位层）：命名子线路 + 重复次数 + 局部→全局比特映射。

* `mapping` 为 `nothing` 时，body 直接使用全局比特索引；
* 否则 body 使用局部索引 1..k，`mapping[i]` 给出局部比特 i 的全局位置。
* 经典位作用域全局共享：body 直接引用父线路的 CReg。
* 依赖图中 BlockOp 以 qubit 足迹作为**原子节点**；需要细粒度时先 `flatten!`。
"""
struct BlockOp <: Operation
    name::Symbol
    body::Circuit
    n::Int                                  # 重复次数
    mapping::Union{Nothing,Vector{Int}}

    function BlockOp(name::Symbol, body::Circuit, n::Integer, mapping::Union{Nothing,Vector{Int}})
        n >= 1 || throw(ArgumentError("repeat must be >= 1"))
        if mapping !== nothing
            qmax = maximum(qubits_used(body); init=0)
            qmax <= length(mapping) ||
                throw(ArgumentError("body uses local qubit $qmax beyond mapping size $(length(mapping))"))
            all(q -> q >= 1, mapping) || throw(ArgumentError("mapping entries must be positive"))
        end
        new(name, body, Int(n), mapping)
    end
end

"构造结构块：`block(body; name=:block, repeat=1, at=nothing)`。"
function block(body::Circuit; name::Symbol=:block, repeat::Int=1, at::Union{Nothing,Vector{Int}}=nothing)
    return BlockOp(name, body, repeat, at)
end

function qubits(op::BlockOp)
    qs = qubits_used(op.body)
    op.mapping === nothing && return qs
    return sort!(unique(Int[op.mapping[q] for q in qs]))
end

function clbits(op::BlockOp)
    out = ClbitRef[]
    for o in op.body.ops
        append!(out, clbits(o))
    end
    return unique(out)
end

is_unitary(op::BlockOp) = all(is_unitary, op.body.ops)

Base.:(==)(a::BlockOp, b::BlockOp) =
    a.name == b.name && a.body == b.body && a.n == b.n && isnothing(a.mapping) == isnothing(b.mapping) &&
    (isnothing(a.mapping) || a.mapping == b.mapping)

function Base.show(io::IO, op::BlockOp)
    print(io, "block :", op.name)
    op.n > 1 && print(io, " ×", op.n)
    op.mapping === nothing || print(io, " at ", op.mapping)
    print(io, " (", length(op.body.ops), " ops)")
end

function Base.show(io::IO, g::UserGate)
    print(io, "usergate :", g.name, " (", nqubits(g), " qubits, ", g.nparams, " params)")
end

# 全酉块的矩阵：body 局部合成 → 映射到 qubit 足迹 → 幂次。
function mat(op::BlockOp)
    is_unitary(op) || throw(ArgumentError("non-unitary block has no matrix"))
    span = qubits(op)                       # 升序全局足迹
    k = length(span)
    rank = Dict{Int,Int}(q => i for (i, q) in enumerate(span))   # 1-based 局部位置
    M = Matrix{ComplexF64}(I, 1 << k, 1 << k)
    for o in op.body.ops
        if op.mapping === nothing
            pos = Int[rank[q] for q in qubits(o)]
        else
            pos = Int[rank[op.mapping[q]] for q in qubits(o)]
        end
        M = _embed(mat(o), pos, k) * M
    end
    return M^op.n
end

"求逆（要求全酉）：body 逐操作逆 + 逆序，重复次数不变。"
function Base.inv(op::BlockOp)
    is_unitary(op) || throw(ArgumentError("cannot invert non-unitary block"))
    return BlockOp(op.name, dagger(op.body), op.n, op.mapping)
end

# ── 接入 circuit.jl 的通用协议 ────────────────────────────────────────────────
_collect_params!(acc::Vector{Param}, op::BlockOp) = _collect_params!(acc, op.body)

_assign_op(op::BlockOp, t::Dict{Param,Float64}) =
    BlockOp(op.name, assign!(copy(op.body), t), op.n, op.mapping)

_op_kind(::BlockOp) = :block

function _validate_block(op::BlockOp)
    bodymax = maximum(qubits_used(op.body); init=0)
    if op.mapping === nothing
        bodymax <= op.body.n || throw(ArgumentError("block body uses qubit $bodymax beyond its size $(op.body.n)"))
    else
        bodymax <= length(op.mapping) ||
            throw(ArgumentError("block body uses local qubit $bodymax beyond mapping size $(length(op.mapping))"))
        all(q -> q >= 1, op.mapping) || throw(ArgumentError("block mapping entries must be positive"))
    end
    return nothing
end

# ── 展开原语（编译器 unroll / 不支持块的后端使用） ───────────────────────────
"展开 BlockOp：应用映射并重复 n 次。"
function unroll(op::BlockOp)
    ops = Operation[]
    for _ in 1:op.n
        for o in op.body.ops
            push!(ops, op.mapping === nothing ? o : _map_positions(o, op.mapping))
        end
    end
    return ops
end

_map_positions(op::GateOp, m::Vector{Int}) =
    GateOp(op.gate, Int[m[q] for q in op.qubits], op.params)
_map_positions(op::MeasOp, m::Vector{Int}) =
    MeasOp(Int[m[q] for q in op.qubits], op.clbits)
_map_positions(op::ReinitOp, m::Vector{Int}) = ReinitOp(Int[m[q] for q in op.qubits])
_map_positions(op::BarrierOp, m::Vector{Int}) = BarrierOp(Int[m[q] for q in op.qubits])
_map_positions(op::ChannelOp, m::Vector{Int}) = ChannelOp(op.channel, Int[m[q] for q in op.qubits])
_map_positions(op::IfOp, m::Vector{Int}) =
    IfOp(op.cond, _map_circuit(op.then, m),
         op.otherwise === nothing ? nothing : _map_circuit(op.otherwise, m))
_map_positions(op::BlockOp, m::Vector{Int}) = begin
    # 嵌套块：内层 mapping（内层局部 → 外层局部）再经 m（外层局部 → 全局）复合
    inner = op.mapping
    combined = inner === nothing ? m : Int[m[inner[i]] for i in 1:length(inner)]
    BlockOp(op.name, op.body, op.n, combined)
end

_map_circuit(c::Circuit, m::Vector{Int}) =
    Circuit(Operation[_map_positions(o, m) for o in c.ops]; n=c.n,
            qregs=copy(c.qregs), cregs=copy(c.cregs), layout=c.layout)

"""
就地递归展开线路中的所有 BlockOp（IfOp 分支内的块同样展开）。
UserGate 属于定义层（门），不展开。
"""
function unroll!(c::Circuit)
    i = 1
    while i <= length(c.ops)
        op = c.ops[i]
        if op isa BlockOp
            splice!(c.ops, i:i, unroll(op))
        elseif op isa IfOp
            unroll!(op.then)
            op.otherwise === nothing || unroll!(op.otherwise)
            i += 1
        else
            i += 1
        end
    end
    return c
end
