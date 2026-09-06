# =============================================================================
# io/qasm3.jl — OpenQASM3 写出 / 读取
#
# 写：stdgates 子集 + 自动生成 rzz/rxx/ryy/iswap/ms 门定义；
#     修饰符用 QASM3 原生语法（inv/pow/ctrl/negctrl @ gate）；
#     IfOp 导出为 if/else 块。
# 读：解析器与 QASM2 共享（见 qasm2.jl 的 _parse_qasm）。
# =============================================================================

const _QASM3_WRITE = Dict{Symbol,String}(
    :H => "h", :X => "x", :Y => "y", :Z => "z", :S => "s", :SDAG => "sdg",
    :T => "t", :TDAG => "tdg", :ID => "id", :SX => "sx",
    :CX => "cx", :CY => "cy", :CZ => "cz", :CH => "ch", :SWAP => "swap",
    :CCX => "ccx", :CSWAP => "cswap", :ISWAP => "iswap",
    :RX => "rx", :RY => "ry", :RZ => "rz", :PHASE => "p", :CPHASE => "cp",
    :CRX => "crx", :RXX => "rxx", :RYY => "ryy", :RZZ => "rzz", :MS => "ms",
    :VirtualZ => "rz",
)

"收集写出时需要自定义门定义的名字。"
function _collect_custom!(needed::Set{Symbol}, g::Gate)
    if g isa InvGate
        _collect_custom!(needed, g.g)
    elseif g isa PowGate
        _collect_custom!(needed, g.g)
    elseif g isa CtrlGate
        _collect_custom!(needed, g.g)
    else
        nm = name(g)
        nm == :RXX && push!(needed, :rxx)
        nm == :RYY && push!(needed, :ryy)
        nm == :RZZ && push!(needed, :rzz)
        nm == :ISWAP && push!(needed, :iswap)
        nm == :MS && push!(needed, :ms)
    end
    return needed
end

# 自定义门定义之间的传递依赖：iswap/ms → rxx/ryy → rzz
function _add_def_deps!(needed::Set{Symbol})
    changed = true
    while changed
        changed = false
        if (:ms in needed || :iswap in needed) && !(:rxx in needed && :ryy in needed)
            union!(needed, (:rxx, :ryy))
            changed = true
        end
        if (:rxx in needed || :ryy in needed) && !(:rzz in needed)
            push!(needed, :rzz)
            changed = true
        end
    end
    return needed
end

# ── QASM3 写出 ────────────────────────────────────────────────────────────────
function _qasm3(c::Circuit)
    ops = _unroll_for_export(c)
    qoff = _qasm_reg_offsets(c.qregs, c.n)
    coff = _qasm_creg_offsets(c.cregs)

    needed = Set{Symbol}()
    for op in ops
        op isa GateOp && _collect_custom!(needed, op.gate)
    end
    _add_def_deps!(needed)

    buf = IOBuffer()
    println(buf, "OPENQASM 3.0;")
    println(buf, "include \"stdgates.inc\";")
    for nm in _QASM_CUSTOM_ORDER
        nm in needed && println(buf, _QASM_CUSTOM_DEFS[nm])
    end
    println(buf)
    for r in c.qregs
        r.n > 0 && println(buf, "qubit[", r.n, "] ", r.name, ";")
    end
    for r in c.cregs
        r.n > 0 && println(buf, "bit[", r.n, "] ", r.name, ";")
    end
    for op in ops
        _qasm3_op!(buf, op, qoff, coff)
    end
    return String(take!(buf))
end

function _qasm3_gateexpr(io::IO, g::Gate)
    if g isa InvGate
        print(io, "inv @ ")
        _qasm3_gateexpr(io, g.g)
    elseif g isa PowGate
        print(io, "pow(", _fmt_float(g.k), ") @ ")
        _qasm3_gateexpr(io, g.g)
    elseif g isa CtrlGate
        all(g.negs) || all(!, g.negs) ||
            throw(ArgumentError("mixed-polarity controls are not expressible as a single QASM3 modifier"))
        all(g.negs) ? print(io, "negctrl") : print(io, "ctrl")
        k = nqubits(g) - nqubits(g.g)
        k > 1 && print(io, "(", k, ")")
        print(io, " @ ")
        _qasm3_gateexpr(io, g.g)
    else
        nm = name(g)
        if nm == :u3
            print(io, "u3")
        else
            s = get(_QASM3_WRITE, nm, nothing)
            s === nothing && throw(ArgumentError("gate $nm is not exportable to OpenQASM 3 (v1)"))
            print(io, s)
        end
    end
    return nothing
end

function _qasm3_op!(io::IO, op::Operation, qoff, coff)
    if op isa GateOp
        _qasm3_gateexpr(io, op.gate)
        vals = _qasm_param_values(op)
        isempty(vals) || print(io, "(", join((_fmt_float(v) for v in vals), ","), ")")
        print(io, " ")
        for (i, q) in enumerate(op.qubits)
            i > 1 && print(io, ", ")
            _qasm_bit(io, qoff, q)
        end
        println(io, ";")
    elseif op isa ResetOp
        for q in op.qubits
            print(io, "reset ")
            _qasm_bit(io, qoff, q)
            println(io, ";")
        end
    elseif op isa BarrierOp
        print(io, "barrier ")
        join(io, (sprint(_qasm_bit, qoff, q) for q in op.qubits), ", ")
        println(io, ";")
    elseif op isa MeasOp
        for (q, cb) in zip(op.qubits, op.clbits)
            print(io, cb.reg.name, "[", cb.index - 1, "] = measure ")
            _qasm_bit(io, qoff, q)
            println(io, ";")
        end
    elseif op isa IfOp
        print(io, "if (", op.cond.reg.name, " ", _cond_symbol(op.cond.op), " ", op.cond.value, ") {\n")
        for o in op.then.ops
            print(io, "  ")
            _qasm3_op!(io, o, qoff, coff)
        end
        print(io, "}")
        if op.otherwise !== nothing
            print(io, " else {\n")
            for o in op.otherwise.ops
                print(io, "  ")
                _qasm3_op!(io, o, qoff, coff)
            end
            print(io, "}")
        end
        println(io)
    elseif op isa ChannelOp
        throw(ArgumentError("noise channels are not serializable to OpenQASM (v1)"))
    else
        throw(ArgumentError("operation of type $(typeof(op)) is not serializable to OpenQASM 3"))
    end
    return nothing
end
