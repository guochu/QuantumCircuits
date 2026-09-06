# =============================================================================
# io/io.jl — 序列化入口 + QASM 共享解析工具
#
# to_qasm(c; version=3) / write_qasm(path, c) / read_qasm(path)
# v1：QASM2 全集（qelib1）+ QASM3 增长子集（测量/分支/if-else/修饰符）。
# =============================================================================

"序列化为 OpenQASM 字符串。"
function to_qasm(c::Circuit; version::Integer=3)
    version == 2 && return _qasm2(c)
    version == 3 && return _qasm3(c)
    throw(ArgumentError("unsupported QASM version $version"))
end

"写入 QASM 文件。"
function write_qasm(path::AbstractString, c::Circuit; version::Integer=3)
    open(path, "w") do io
        write(io, to_qasm(c; version=version))
    end
    return path
end

"读取 QASM（参数为文件路径，或直接给出以 OPENQASM 开头的源码字符串）。"
function read_qasm(path_or_src::AbstractString)
    src = occursin(r"^\s*OPENQASM", path_or_src) ? String(path_or_src) : read(path_or_src, String)
    m = match(r"^\s*OPENQASM\s+([0-9]+(?:\.[0-9]+)?)", _strip_qasm_comments(src))
    m === nothing && throw(ArgumentError("not an OpenQASM file: missing OPENQASM header"))
    v = tryparse(Int, split(m.captures[1], '.')[1])
    v == 2 && return _parse_qasm2(src)
    v >= 3 && return _parse_qasm3(src)
    throw(ArgumentError("unsupported OpenQASM version $(m.captures[1])"))
end

# ── 共享工具 ──────────────────────────────────────────────────────────────────

"去掉 // 行注释与 /* */ 块注释。"
function _strip_qasm_comments(src::AbstractString)
    out = IOBuffer()
    i = firstindex(src)
    n = lastindex(src)
    while i <= n
        c = src[i]
        if c == '/' && i < n && src[nextind(src, i)] == '/'
            while i <= n && src[i] != '\n'
                i = nextind(src, i)
            end
        elseif c == '/' && i < n && src[nextind(src, i)] == '*'
            i = nextind(src, nextind(src, i))
            while i <= n && !(src[i] == '*' && i < n && src[nextind(src, i)] == '/')
                i = nextind(src, i)
            end
            i = i <= n ? nextind(src, nextind(src, i)) : i
        else
            print(out, c)
            i = nextind(src, i)
        end
    end
    return String(take!(out))
end

"按 ';' 切分语句；花括号内不切分；'}' 闭合时强制断句（if/gate 块）。"
function _qasm_statements(src::AbstractString)
    s = _strip_qasm_comments(src)
    stmts = String[]
    buf = IOBuffer()
    depth = 0
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if c == '{'
            depth += 1
        elseif c == '}'
            depth -= 1
            print(buf, c)
            if depth == 0
                stmt = strip(String(take!(buf)))
                isempty(stmt) || push!(stmts, stmt)
                i = nextind(s, i)
                continue
            end
        elseif c == ';' && depth == 0
            stmt = strip(String(take!(buf)))
            isempty(stmt) || push!(stmts, stmt)
            i = nextind(s, i)
            continue
        end
        print(buf, c)
        i = nextind(s, i)
    end
    stmt = strip(String(take!(buf)))
    isempty(stmt) || push!(stmts, stmt)
    return stmts
end

# —— 常量表达式求值：数字 / pi / + - * / ^ / 括号 / cos sin tan exp ln log sqrt ——
mutable struct _ExprParser
    s::String
    i::Int
    env::Dict{Symbol,Float64}    # 符号 → 值（门定义形参）
end

_expr_peek(p::_ExprParser) = p.i <= ncodeunits(p.s) ? p.s[p.i] : '\0'

function _expr_skipws!(p::_ExprParser)
    while p.i <= ncodeunits(p.s) && isspace(p.s[p.i])
        p.i = nextind(p.s, p.i)
    end
end

function _expr_expect!(p::_ExprParser, c::Char)
    _expr_skipws!(p)
    _expr_peek(p) == c || throw(ArgumentError("expected '$c' in expression \"$(p.s)\""))
    p.i = nextind(p.s, p.i)
    return nothing
end

function _parse_expr(str::AbstractString, env::Dict{Symbol,Float64}=Dict{Symbol,Float64}())
    p = _ExprParser(String(str), firstindex(String(str)), env)
    v = _expr_add!(p)
    _expr_skipws!(p)
    p.i <= ncodeunits(p.s) && throw(ArgumentError("trailing characters in expression \"$(p.s)\""))
    return v
end

function _expr_add!(p::_ExprParser)
    v = _expr_mul!(p)
    while true
        _expr_skipws!(p)
        c = _expr_peek(p)
        if c == '+' || c == '-'
            p.i = nextind(p.s, p.i)
            rhs = _expr_mul!(p)
            v = c == '+' ? v + rhs : v - rhs
        else
            return v
        end
    end
end

function _expr_mul!(p::_ExprParser)
    v = _expr_unary!(p)
    while true
        _expr_skipws!(p)
        c = _expr_peek(p)
        if c == '*' || c == '/'
            p.i = nextind(p.s, p.i)
            rhs = _expr_unary!(p)
            v = c == '*' ? v * rhs : v / rhs
        elseif c == '^'
            p.i = nextind(p.s, p.i)
            rhs = _expr_unary!(p)
            v = v^rhs
        else
            return v
        end
    end
end

function _expr_unary!(p::_ExprParser)
    _expr_skipws!(p)
    c = _expr_peek(p)
    if c == '-'
        p.i = nextind(p.s, p.i)
        return -_expr_unary!(p)
    elseif c == '+'
        p.i = nextind(p.s, p.i)
        return _expr_unary!(p)
    end
    return _expr_primary!(p)
end

const _EXPR_FUNCS = Dict{String,Function}(
    "cos" => cos, "sin" => sin, "tan" => tan, "exp" => exp,
    "ln" => log, "log" => log, "sqrt" => sqrt, "abs" => abs,
)

const _EXPR_CONSTS = Dict{String,Float64}("pi" => π, "π" => π, "euler" => ℯ)

function _expr_primary!(p::_ExprParser)
    _expr_skipws!(p)
    i = p.i
    i <= ncodeunits(p.s) || throw(ArgumentError("unexpected end of expression \"$(p.s)\""))
    c = p.s[i]
    if c == '('
        p.i = nextind(p.s, i)
        v = _expr_add!(p)
        _expr_expect!(p, ')')
        return v
    elseif isdigit(c) || c == '.'
        j = i
        seen_exp = false
        while j <= ncodeunits(p.s)
            ch = p.s[j]
            if isdigit(ch) || ch == '.'
                j = nextind(p.s, j)
            elseif (ch == 'e' || ch == 'E') && !seen_exp && j > i
                k = nextind(p.s, j)
                if k <= ncodeunits(p.s) && (isdigit(p.s[k]) || p.s[k] == '+' || p.s[k] == '-')
                    seen_exp = true
                    j = nextind(p.s, k)   # 吃掉 e 与可选符号
                else
                    break
                end
            else
                break
            end
        end
        token = p.s[i:prevind(p.s, j)]
        v = tryparse(Float64, token)
        v === nothing && throw(ArgumentError("invalid number literal \"$token\" in expression \"$(p.s)\""))
        p.i = j
        return v
    elseif isletter(c) || c == '_'
        j = i
        while j <= ncodeunits(p.s) && (isletter(p.s[j]) || isdigit(p.s[j]) || p.s[j] == '_')
            j = nextind(p.s, j)
        end
        token = String(p.s[i:prevind(p.s, j)])
        p.i = j
        if haskey(_EXPR_FUNCS, token)
            _expr_expect!(p, '(')
            v = _expr_add!(p)
            _expr_expect!(p, ')')
            return _EXPR_FUNCS[token](v)
        elseif haskey(_EXPR_CONSTS, token)
            return _EXPR_CONSTS[token]
        elseif !isempty(p.env)
            sym = Symbol(token)
            haskey(p.env, sym) || throw(ArgumentError("unknown identifier \"$token\" in expression \"$(p.s)\""))
            return p.env[sym]
        else
            throw(ArgumentError("unknown identifier \"$token\" in expression \"$(p.s)\""))
        end
    else
        throw(ArgumentError("unexpected character '$c' in expression \"$(p.s)\""))
    end
end
