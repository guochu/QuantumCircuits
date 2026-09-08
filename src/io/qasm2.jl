# =============================================================================
# io/qasm2.jl — OpenQASM2 读写 + 共享解析器
#
# 写：qelib1 子集（含 Qiskit 扩展的 rxx/rzz）；块自动展开；
#     IfOp 仅支持单操作 then 分支（QASM2 语法限制）。
# 读：qreg/creg、gate 定义（递归展开）、measure/reset/barrier/if、
#     u1/u2/u3/cu1/cu3/crz/cu 等映射到内置门。
# =============================================================================

# ── 名称映射表 ────────────────────────────────────────────────────────────────
# 写出：Gate 名 → QASM2 名
const _QASM2_WRITE = Dict{Symbol,String}(
    :H => "h", :X => "x", :Y => "y", :Z => "z", :S => "s", :SDAG => "sdg",
    :T => "t", :TDAG => "tdg", :ID => "id", :SX => "sx",
    :CX => "cx", :CY => "cy", :CZ => "cz", :CH => "ch", :SWAP => "swap",
    :CCX => "ccx", :CSWAP => "cswap",
    :RX => "rx", :RY => "ry", :RZ => "rz", :PHASE => "u1", :CPHASE => "cu1",
    :RXX => "rxx", :RZZ => "rzz", :VirtualZ => "rz",
)

# 读入：QASM2/QASM3 门名 → Gate
const _QASM_READ = Dict{Symbol,Gate}(
    :x => X, :y => Y, :z => Z, :h => H, :s => S, :sdg => SDAG, :t => T, :tdg => TDAG,
    :id => ID, :sx => SX, :CX => CX,
    :cx => CX, :cy => CY, :cz => CZ, :ch => CH, :swap => SWAP, :ccx => CCX, :cswap => CSWAP,
    :iswap => ISWAP, :rxx => RXX, :ryy => _RYY, :rzz => RZZ, :ms => MS,
    :rx => RX, :ry => RY, :rz => RZ,
    :p => PHASE, :u1 => PHASE, :phase => PHASE, :cp => CPHASE, :cu1 => CPHASE, :cphase => CPHASE,
    :crx => CRX, :cry => _CRY, :crz => _CRZ,
    :u2 => _U2, :u3 => _U3, :cu3 => _CU3, :cu => _CU,
)

const _QASM_CUSTOM_DEFS = Dict{Symbol,String}(
    :rzz   => "gate rzz(theta) a, b { cx a, b; rz(theta) b; cx a, b; }",
    :rxx   => "gate rxx(theta) a, b { h a; h b; rzz(theta) a, b; h a; h b; }",
    :ryy   => "gate ryy(theta) a, b { rx(pi/2) a; rx(pi/2) b; rzz(theta) a, b; rx(-pi/2) a; rx(-pi/2) b; }",
    :iswap => "gate iswap a, b { rxx(-pi/2) a, b; ryy(-pi/2) a, b; }",
    :ms    => "gate ms(theta, phi) a, b { rxx(theta*cos(phi)) a, b; ryy(theta*sin(phi)) a, b; }",
)
const _QASM_CUSTOM_ORDER = (:rzz, :rxx, :ryy, :iswap, :ms)
const _CUSTOM_GATE_NAMES = Set{Symbol}((:RXX, :RYY, :RZZ, :ISWAP, :MS))

# ── 浮点格式化 ────────────────────────────────────────────────────────────────
_fmt_float(x::Real) = repr(Float64(x))

"导出前预处理：unroll 展开所有 BlockOp。"
function _unroll_for_export(c::Circuit)
    tmp = copy(c)
    unroll!(tmp)
    return tmp.ops
end

"寄存器名 → (全局偏移, 尺寸)。"
function _qasm_reg_offsets(regs::Vector{QReg}, n::Int)
    m = Dict{Symbol,Tuple{Int,Int}}()
    off = 1
    for r in regs
        haskey(m, r.name) && throw(ArgumentError("duplicate qreg name $(r.name)"))
        m[r.name] = (off, r.n)
        off += r.n
    end
    off - 1 == n || throw(ArgumentError("qreg sizes ($(off - 1)) must sum to circuit size ($n) for QASM export"))
    return m
end

function _qasm_creg_offsets(cregs::Vector{CReg})
    m = Dict{Symbol,Tuple{Int,CReg}}()
    off = 0
    for r in cregs
        haskey(m, r.name) && throw(ArgumentError("duplicate creg name $(r.name)"))
        m[r.name] = (off, r)
        off += r.n
    end
    return m
end

"解析 GateOp 的具体参数值（未绑定符号参数时报错）。"
function _qasm_param_values(op::GateOp)
    isempty(op.params) && return Float64[]
    return Float64[_param_value(p, nothing) for p in op.params]
end

"写出比特地址 q[i]。"
_qasm_bit(io::IO, offsets::Dict{Symbol,Tuple{Int,Int}}, q::Int) = begin
    for (rname, (off, sz)) in offsets
        if off <= q < off + sz
            print(io, rname, "[", q - off, "]")
            return
        end
    end
    throw(ArgumentError("qubit $q not covered by any qreg"))
end

# ── QASM2 写出 ────────────────────────────────────────────────────────────────
function _qasm2(c::Circuit)
    ops = _unroll_for_export(c)
    qoff = _qasm_reg_offsets(c.qregs, c.n)
    coff = _qasm_creg_offsets(c.cregs)
    buf = IOBuffer()
    println(buf, "OPENQASM 2.0;")
    println(buf, "include \"qelib1.inc\";")
    for r in c.qregs
        r.n > 0 && println(buf, "qreg ", r.name, "[", r.n, "];")
    end
    for r in c.cregs
        r.n > 0 && println(buf, "creg ", r.name, "[", r.n, "];")
    end
    for op in ops
        _qasm2_op!(buf, op, qoff, coff)
    end
    return String(take!(buf))
end

function _qasm2_gateexpr(io::IO, op::GateOp, qoff)
    op.gate isa Gate && !(op.gate isa ModifiedGate) ||
        throw(ArgumentError("gate modifiers are not exportable to OpenQASM 2; use to_qasm(c; version=3)"))
    nm = get(_QASM2_WRITE, name(op.gate), nothing)
    nm === nothing &&
        throw(ArgumentError("gate $(name(op.gate)) is not exportable to OpenQASM 2 (not in qelib1); use to_qasm(c; version=3)"))
    print(io, nm)
    vals = _qasm_param_values(op)
    isempty(vals) || print(io, "(", join((_fmt_float(v) for v in vals), ","), ")")
    print(io, " ")
    for (i, q) in enumerate(op.qubits)
        i > 1 && print(io, ",")
        _qasm_bit(io, qoff, q)
    end
    return nothing
end

function _qasm2_op!(io::IO, op::Operation, qoff, coff)
    if op isa GateOp
        _qasm2_gateexpr(io, op, qoff)
        println(io, ";")
    elseif op isa ReinitOp
        for q in op.qubits
            print(io, "reset ")
            _qasm_bit(io, qoff, q)
            println(io, ";")
        end
    elseif op isa BarrierOp
        print(io, "barrier ")
        join(io, (sprint(_qasm_bit, qoff, q) for q in op.qubits), ",")
        println(io, ";")
    elseif op isa MeasOp
        for (q, cb) in zip(op.qubits, op.clbits)
            print(io, "measure ")
            _qasm_bit(io, qoff, q)
            print(io, " -> ", cb.reg.name, "[", cb.index - 1, "];")
            println(io)
        end
    elseif op isa IfOp
        op.cond.bit === nothing ||
            throw(ArgumentError("OpenQASM 2 if compares a whole register; per-bit conditions ($(op.cond)) are not exportable"))
        op.otherwise === nothing ||
            throw(ArgumentError("OpenQASM 2 has no else branch; use to_qasm(c; version=3)"))
        length(op.then.ops) == 1 ||
            throw(ArgumentError("OpenQASM 2 if applies to a single statement; use to_qasm(c; version=3)"))
        print(io, "if (", op.cond.reg.name, " ", _cond_symbol(op.cond.op), " ", op.cond.value, ") ")
        _qasm2_op!(io, op.then.ops[1], qoff, coff)
    elseif op isa ChannelOp
        throw(ArgumentError("noise channels are not serializable to OpenQASM (v1)"))
    else
        throw(ArgumentError("operation of type $(typeof(op)) is not serializable to OpenQASM 2"))
    end
    return nothing
end

_cond_symbol(s::Symbol) = s == :(==) ? "==" : s == :≠ ? "!=" : s == :≥ ? ">=" : s == :≤ ? "<=" :
    throw(ArgumentError("unsupported condition operator $s"))

# ── 统一解析器 ────────────────────────────────────────────────────────────────
mutable struct _QASMParseState
    version::Int
    nq::Int
    qmap::Dict{Symbol,Tuple{Int,Int}}       # qreg name => (offset, size)
    cmap::Dict{Symbol,CReg}
    qregs::Vector{QReg}
    cregs::Vector{CReg}
    gate_defs::Dict{Symbol,Tuple{Vector{Symbol},Vector{Symbol},Vector{String}}}  # name => (形参, 形比特, 语句)
    ops::Vector{Operation}
    last_if::Int
end

_QASMParseState(version::Int) = _QASMParseState(version, 0, Dict{Symbol,Tuple{Int,Int}}(),
    Dict{Symbol,CReg}(), QReg[], CReg[],
    Dict{Symbol,Tuple{Vector{Symbol},Vector{Symbol},Vector{String}}}(), Operation[], 0)

function _parse_qasm(src::AbstractString, version::Int)
    stmts = _qasm_statements(src)
    isempty(stmts) && throw(ArgumentError("empty QASM source"))
    m = match(r"^OPENQASM\s+([0-9]+)", stmts[1])
    m === nothing && throw(ArgumentError("missing OPENQASM header"))
    tryparse(Int, m[1]) == version ||
        throw(ArgumentError("expected OpenQASM $version source, got version $(m[1])"))
    st = _QASMParseState(version)
    for stmt in stmts[2:end]
        _parse_stmt!(st, stmt)
    end
    return Circuit(st.ops; n=st.nq, qregs=st.qregs, cregs=st.cregs)
end

_parse_qasm2(src::AbstractString) = _parse_qasm(src, 2)
_parse_qasm3(src::AbstractString) = _parse_qasm(src, 3)

_split_top(s::AbstractString, d::Char) = isempty(strip(s)) ? String[] :
    [strip(x) for x in split(s, d)]

function _parse_stmt!(st::_QASMParseState, stmt::AbstractString)
    # QASM3 赋值式测量（"c[0] = measure q[0]"）优先于关键字分发
    occursin(r"=\s*measure\s", stmt) && return _parse_measure!(st, stmt)
    kw = match(r"^[A-Za-z_]+", stmt)
    head = kw === nothing ? "" : lowercase(kw.match)
    if head == "include"
        file = match(r"\"([^\"]+)\"", stmt)
        (file !== nothing && file[1] in ("qelib1.inc", "stdgates.inc")) ||
            throw(ArgumentError("unsupported include in v1: $stmt"))
    elseif head == "qreg" || (head == "qubit" && st.version >= 3)
        _parse_decl!(st, stmt, true)
    elseif head == "creg" || (head == "bit" && st.version >= 3)
        _parse_decl!(st, stmt, false)
    elseif head == "gate"
        _parse_gatedef!(st, stmt)
    elseif head == "opaque"
        throw(ArgumentError("opaque gates are not supported (v1)"))
    elseif head == "barrier"
        push!(st.ops, BarrierOp(_resolve_barrier_bits(st, _argtail(stmt))))
    elseif head == "reset"
        for q in _resolve_operand_group(st, _argtail(stmt))
            push!(st.ops, ReinitOp(q))
        end
    elseif head == "measure"
        _parse_measure!(st, stmt)
    elseif head == "if"
        _parse_if!(st, stmt)
    elseif head == "else"
        _parse_else!(st, stmt)
    elseif head in ("input", "output", "const", "defcal", "def", "for", "while", "switch", "break", "continue", "duration", "stretch", "box")
        throw(ArgumentError("unsupported QASM3 feature (v1 subset): $stmt"))
    else
        _parse_apply!(st, stmt)
    end
    return nothing
end

# "name ..." → 去掉关键字后的内容
_argtail(stmt::AbstractString) = strip(replace(stmt, r"^[A-Za-z_]+\s*" => ""; count=1))

# 声明：qreg q[4] / qubit[4] q / qubit q / creg c[2] / bit[2] c / bit c
function _parse_decl!(st::_QASMParseState, stmt::AbstractString, isq::Bool)
    m = match(r"^[A-Za-z_]+\s*(?:\[\s*([0-9]+)\s*\])?\s+([A-Za-z_]\w*)\s*(?:\[\s*([0-9]+)\s*\])?\s*$", stmt)
    m === nothing && throw(ArgumentError("invalid declaration: $stmt"))
    n = m[3] !== nothing ? parse(Int, m[3]) : m[1] !== nothing ? parse(Int, m[1]) : 1
    nm = Symbol(m[2])
    if isq
        haskey(st.qmap, nm) && throw(ArgumentError("duplicate qreg $nm"))
        st.qmap[nm] = (st.nq + 1, n)     # 内部 1-based 起始编号
        push!(st.qregs, QReg(nm, n))
        st.nq += n
    else
        haskey(st.cmap, nm) && throw(ArgumentError("duplicate creg $nm"))
        r = CReg(nm, n)
        st.cmap[nm] = r
        push!(st.cregs, r)
    end
    return nothing
end

# gate 定义
function _parse_gatedef!(st::_QASMParseState, stmt::AbstractString)
    bidx = findfirst('{', stmt)
    bidx === nothing && throw(ArgumentError("invalid gate definition (missing body): $stmt"))
    endswith(strip(stmt), '}') || throw(ArgumentError("invalid gate definition: $stmt"))
    header = strip(stmt[1:prevind(stmt, bidx)])
    body = strip(stmt[nextind(stmt, bidx):prevind(stmt, lastindex(stmt))])
    m = match(r"^gate\s+([A-Za-z_]\w*)\s*(?:\(([^)]*)\))?\s+(.*)$", header)
    m === nothing && throw(ArgumentError("invalid gate definition header: $header"))
    name = Symbol(m[1])
    params = m[2] === nothing ? Symbol[] : Symbol.(split(replace(m[2], r"\s+" => ""), ','; keepempty=false))
    args = Symbol.(split(replace(m[3], r"\s+" => ""), ','; keepempty=false))
    body_stmts = _qasm_statements(body)
    st.gate_defs[name] = (params, args, body_stmts)
    return nothing
end

# 操作数解析："q[0], q, r[2]" → Vector{Vector{Int}}（每个元素是一次应用的实际比特；整寄存器逐位展开）
function _resolve_operand_group(st::_QASMParseState, argstr::AbstractString)
    args = _split_top(argstr, ',')
    isempty(args) && throw(ArgumentError("missing operands"))
    per_arg = Vector{Vector{Vector{Int}}}([_resolve_one_operand(st, a) for a in args])
    if any(r -> length(r) > 1, per_arg)
        all(r -> length(r) == length(per_arg[1]), per_arg) ||
            throw(ArgumentError("register sizes must match for element-wise application"))
        return [collect(Iterators.flatten(per_arg[j][i] for j in 1:length(per_arg)))
                for i in 1:length(per_arg[1])]
    else
        return [collect(Iterators.flatten(r[1] for r in per_arg))]
    end
end

# 单个操作数 → 一次或多次应用的比特列表（整寄存器逐位）
function _resolve_one_operand(st::_QASMParseState, a::AbstractString)
    m = match(r"^([A-Za-z_]\w*)(?:\[(.+)\])?$", strip(a))
    m === nothing && throw(ArgumentError("invalid operand \"$a\""))
    nm = Symbol(m[1])
    haskey(st.qmap, nm) || throw(ArgumentError("unknown qubit register \"$nm\""))
    off, n = st.qmap[nm]
    if m[2] === nothing
        return Vector{Int}[[off + i] for i in 0:n-1]   # off 为内部 1-based 起始号
    end
    idx = _parse_expr(m[2])
    isinteger(idx) || throw(ArgumentError("qubit index must be an integer: $a"))
    idx = Int(idx)
    0 <= idx < n || throw(ArgumentError("qubit index out of range: $a"))
    return Vector{Int}[[off + idx]]   # QASM 0-based 索引 → 内部 1-based
end

"barrier 操作数：整寄存器展开进同一个 barrier。"
function _resolve_barrier_bits(st::_QASMParseState, argstr::AbstractString)
    args = _split_top(argstr, ',')
    isempty(args) && throw(ArgumentError("barrier needs operands"))
    bits = Int[]
    for a in args
        for ql in _resolve_one_operand(st, a)
            append!(bits, ql)
        end
    end
    return sort!(unique(bits))
end

# measure 两种语法：measure q[i] -> c[j]; 与 c[j] = measure q[i];
function _parse_measure!(st::_QASMParseState, stmt::AbstractString)
    m = match(r"^(.*?)=\s*measure\s+(.+)$", stmt)
    if m !== nothing
        cbs = _resolve_clbits(st, strip(m[1]))
        qs = _resolve_operand_group(st, strip(m[2]))
        _push_measure!(st, qs, cbs)
        return nothing
    end
    m = match(r"^measure\s+(.+?)\s*->\s*(.+)$", stmt)
    m === nothing && throw(ArgumentError("invalid measure statement: $stmt"))
    qs = _resolve_operand_group(st, strip(m[1]))
    cbs = _resolve_clbits(st, strip(m[2]))
    _push_measure!(st, qs, cbs)
    return nothing
end

function _push_measure!(st::_QASMParseState, qs::Vector{Vector{Int}}, cbs::Vector{ClbitRef})
    n = length(qs)
    length(cbs) == n ||
        throw(ArgumentError("measure: $n qubits vs $(length(cbs)) clbits"))
    for i in 1:n
        push!(st.ops, MeasOp(qs[i], [cbs[i]]))
    end
    return nothing
end

function _resolve_clbits(st::_QASMParseState, argstr::AbstractString)
    args = _split_top(argstr, ',')
    out = ClbitRef[]
    for a in args
        m = match(r"^([A-Za-z_]\w*)(?:\[(.+)\])?$", strip(a))
        m === nothing && throw(ArgumentError("invalid clbit operand \"$a\""))
        nm = Symbol(m[1])
        haskey(st.cmap, nm) || throw(ArgumentError("unknown creg \"$nm\""))
        r = st.cmap[nm]
        if m[2] === nothing
            append!(out, r[1:length(r)])
        else
            idx = Int(_parse_expr(m[2]))
            push!(out, r[idx+1])   # 0-based QASM 索引
        end
    end
    return out
end

# 条件："c == 3"、"c != 1"、"c >= 2"、"b == 1"
function _parse_cond(st::_QASMParseState, s::AbstractString)
    m = match(r"^\s*([A-Za-z_]\w*)(?:\[[0-9]+\])?\s*(==|!=|>=|<=)\s*([0-9]+)\s*$", s)
    m === nothing && throw(ArgumentError("unsupported condition expression: $s"))
    nm = Symbol(m[1])
    haskey(st.cmap, nm) || throw(ArgumentError("unknown creg in condition: $nm"))
    op = m[2] == "==" ? :(==) : m[2] == "!=" ? :≠ : m[2] == ">=" ? :≥ : :≤
    return Cond(st.cmap[nm], op, parse(Int, m[3]))
end

# if：单语句或花括号块
function _parse_if!(st::_QASMParseState, stmt::AbstractString)
    m = match(r"^if\s*\((.*)\)\s*(.*)$"s, stmt)
    m === nothing && throw(ArgumentError("invalid if statement: $stmt"))
    cond = _parse_cond(st, m[1])
    body = strip(m[2])
    ops = Operation[]
    if startswith(body, "{")
        (endswith(body, "}") && _braces_balanced(body)) ||
            throw(ArgumentError("invalid if body: $stmt"))
        inner = _qasm_statements(body[nextind(body, firstindex(body)):prevind(body, lastindex(body))])
        for s in inner
            _parse_sub!(st, s, ops)
        end
    else
        _parse_sub!(st, body, ops)
    end
    push!(st.ops, IfOp(cond, Circuit(ops; n=st.nq, qregs=copy(st.qregs), cregs=copy(st.cregs)), nothing))
    st.last_if = length(st.ops)
    return nothing
end

function _braces_balanced(s::AbstractString)
    depth = 0
    for c in s
        c == '{' && (depth += 1)
        c == '}' && (depth -= 1)
        depth < 0 && return false
    end
    return depth == 0
end

function _parse_else!(st::_QASMParseState, stmt::AbstractString)
    m = match(r"^else\s*\{(.*)\}$"s, strip(stmt))
    m === nothing && throw(ArgumentError("invalid else statement: $stmt"))
    (1 <= st.last_if <= length(st.ops) && st.ops[st.last_if] isa IfOp) ||
        throw(ArgumentError("else without preceding if"))
    ifop = st.ops[st.last_if]::IfOp
    ifop.otherwise === nothing || throw(ArgumentError("duplicate else branch"))
    ops = Operation[]
    for s in _qasm_statements(m[1])
        _parse_sub!(st, s, ops)
    end
    st.ops[st.last_if] = IfOp(ifop.cond, ifop.then,
        Circuit(ops; n=st.nq, qregs=copy(st.qregs), cregs=copy(st.cregs)))
    return nothing
end

# 子语句（if/gate 块内）：仅允许门应用与 barrier
function _parse_sub!(st::_QASMParseState, stmt::AbstractString, out::Vector{Operation})
    kw = match(r"^[A-Za-z_]+", stmt)
    head = kw === nothing ? "" : lowercase(kw.match)
    if head == "barrier"
        push!(out, BarrierOp(_resolve_barrier_bits(st, _argtail(stmt))))
    elseif head in ("measure", "reset", "if", "else", "gate", "qreg", "creg", "qubit", "bit", "include")
        throw(ArgumentError("statement not allowed in this context: $stmt"))
    else
        _parse_apply!(st, stmt; out=out)
    end
    return nothing
end

# 门应用（可带 QASM3 修饰符链：inv @ pow(0.5) @ ctrl(2) @ g(...)）
function _parse_apply!(st::_QASMParseState, stmt::AbstractString; out::Union{Nothing,Vector{Operation}}=nothing)
    dst = out === nothing ? st.ops : out
    parts = split(stmt, '@')
    # 末段："name(params) args"
    m = match(r"^\s*([A-Za-z_]\w*)\s*(?:\(((?:[^()]|\([^()]*\))*)\))?\s+(.+)$", parts[end])
    m2 = m === nothing ? match(r"^\s*([A-Za-z_]\w*)\s*(?:\(((?:[^()]|\([^()]*\))*)\))?\s*$", parts[end]) : nothing
    if m === nothing && m2 === nothing
        throw(ArgumentError("invalid gate application: $stmt"))
    end
    gname = Symbol(m === nothing ? m2[1] : m[1])
    params_str = (m === nothing ? m2[2] : m[2])
    argstr = m === nothing ? "" : m[3]
    mods = length(parts) > 1 ? parts[1:end-1] : String[]

    if haskey(st.gate_defs, gname)
        isempty(mods) || throw(ArgumentError("cannot apply modifiers to user-defined gate $gname"))
        _expand_usergate!(st, gname, params_str, argstr, dst)
        return nothing
    end

    haskey(_QASM_READ, gname) || throw(ArgumentError("unknown gate \"$gname\""))
    g = _QASM_READ[gname]
    vals = params_str === nothing ? Float64[] :
        Float64[_parse_expr(s) for s in _split_top(params_str, ',')]
    for tok in reverse(mods)
        g = _apply_modifier(g, strip(String(tok)))
    end
    num_params(g) == length(vals) ||
        throw(ArgumentError("gate \"$gname\" expects $(num_params(g)) parameters, got $(length(vals))"))
    for qlist in _resolve_operand_group(st, argstr)
        length(qlist) == nqubits(g) ||
            throw(ArgumentError("gate \"$gname\" acts on $(nqubits(g)) qubits, got $(length(qlist))"))
        push!(dst, GateOp(g, qlist, vals))
    end
    return nothing
end

function _apply_modifier(g::Gate, tok::AbstractString)
    m = match(r"^(ctrl|negctrl|inv|pow)(?:\(([^)]*)\))?$", tok)
    m === nothing && throw(ArgumentError("invalid modifier \"$tok\""))
    kw = m[1]
    if kw == "inv"
        m[2] === nothing || throw(ArgumentError("inv takes no argument"))
        return InvGate(g)
    elseif kw == "pow"
        m[2] !== nothing || throw(ArgumentError("pow requires an exponent"))
        return PowGate(g, _parse_expr(m[2]))
    else
        n = m[2] === nothing ? 1 : Int(round(_parse_expr(m[2])))
        n >= 1 || throw(ArgumentError("modifier count must be >= 1"))
        return CtrlGate(g, n, kw == "negctrl" ? trues(n) : falses(n))
    end
end

# 用户 gate 定义展开（递归）
function _expand_usergate!(st::_QASMParseState, gname::Symbol, params_str::Union{Nothing,AbstractString}, argstr::AbstractString, out::Vector{Operation})
    pnames, anames, body = st.gate_defs[gname]
    vals = params_str === nothing ? Float64[] :
        Float64[_parse_expr(s) for s in _split_top(params_str, ',')]
    length(vals) == length(pnames) ||
        throw(ArgumentError("gate \"$gname\" expects $(length(pnames)) parameters, got $(length(vals))"))
    actuals = _split_top(argstr, ',')
    length(actuals) == length(anames) ||
        throw(ArgumentError("gate \"$gname\" expects $(length(anames)) qubit arguments, got $(length(actuals))"))
    env = Dict{Symbol,Float64}(p => v for (p, v) in zip(pnames, vals))
    qsub = Dict{Symbol,Int}()
    for (an, a) in zip(anames, actuals)
        resolved = _resolve_one_operand(st, a)
        (length(resolved) == 1 && length(resolved[1]) == 1) ||
            throw(ArgumentError("gate arguments must be single qubits inside application"))
        qsub[an] = resolved[1][1]
    end
    for s in body
        _expand_user_stmt!(st, gname, s, env, qsub, out)
    end
    return nothing
end

function _expand_user_stmt!(st::_QASMParseState, defname::Symbol, stmt::AbstractString,
                            env::Dict{Symbol,Float64}, qsub::Dict{Symbol,Int}, out::Vector{Operation})
    kw = match(r"^[A-Za-z_]+", stmt)
    head = kw === nothing ? "" : lowercase(kw.match)
    if head == "barrier"
        args = _split_top(_argtail(stmt), ',')
        push!(out, BarrierOp(sort!(unique(Int[only(_resolve_sub_operand(qsub, a)) for a in args]))))
        return nothing
    end
    head in ("measure", "reset", "if", "gate", "include") &&
        throw(ArgumentError("statement not allowed inside gate definition: $stmt"))
    m = match(r"^\s*([A-Za-z_]\w*)\s*(?:\(((?:[^()]|\([^()]*\))*)\))?\s+(.+)$", stmt)
    m === nothing && throw(ArgumentError("invalid statement in gate body: $stmt"))
    gname = Symbol(m[1])
    params_str = m[2]
    argstr = m[3]
    if haskey(st.gate_defs, gname)
        _expand_usergate_sub!(st, defname, gname, params_str, argstr, env, qsub, out)
        return nothing
    end
    haskey(_QASM_READ, gname) || throw(ArgumentError("unknown gate \"$gname\" in gate body"))
    g = _QASM_READ[gname]
    vals = params_str === nothing ? Float64[] :
        Float64[_parse_expr(s, env) for s in _split_top(params_str, ',')]
    num_params(g) == length(vals) ||
        throw(ArgumentError("gate \"$gname\" expects $(num_params(g)) parameters, got $(length(vals))"))
    qs = Int[only(_resolve_sub_operand(qsub, a)) for a in _split_top(argstr, ',')]
    length(qs) == nqubits(g) ||
        throw(ArgumentError("gate \"$gname\" acts on $(nqubits(g)) qubits, got $(length(qs))"))
    push!(out, GateOp(g, qs, vals))
    return nothing
end

function _expand_usergate_sub!(st, defname, gname, params_str, argstr, env, qsub, out)
    pnames, anames, body = st.gate_defs[gname]
    vals = params_str === nothing ? Float64[] :
        Float64[_parse_expr(s, env) for s in _split_top(params_str, ',')]
    length(vals) == length(pnames) ||
        throw(ArgumentError("gate \"$gname\" expects $(length(pnames)) parameters, got $(length(vals))"))
    actuals = _split_top(argstr, ',')
    length(actuals) == length(anames) ||
        throw(ArgumentError("gate \"$gname\" expects $(length(anames)) qubit arguments, got $(length(actuals))"))
    env2 = Dict{Symbol,Float64}(p => v for (p, v) in zip(pnames, vals))
    qsub2 = Dict{Symbol,Int}()
    for (an, a) in zip(anames, actuals)
        qsub2[an] = only(_resolve_sub_operand(qsub, a))
    end
    for s in body
        _expand_user_stmt!(st, defname, s, env2, qsub2, out)
    end
    return nothing
end

function _resolve_sub_operand(qsub::Dict{Symbol,Int}, a::AbstractString)
    s = strip(a)
    occursin('[', s) && throw(ArgumentError("indexing gate arguments is not allowed inside gate bodies: $s"))
    nm = Symbol(s)
    haskey(qsub, nm) || throw(ArgumentError("unknown gate argument \"$s\""))
    return Int[qsub[nm]]
end
