# =============================================================================
# gates.jl — Gate 抽象 + 门库（可调用单例）
#
# 设计要点：
#   * Gate 是**不携带比特位置**的数学对象（定义层）；作用于比特后得到
#     `GateOp`（定位层，见 ops.jl）。调用即定位：`H(1)` => `GateOp(H, [1])`。
#   * 门库调用签名 = (参数…, 比特…)，与 Qiskit 线路方法一致：`RX(π/2, 3)`。
#   * 门矩阵约定：2^n × 2^n，门自身 qubit 列表中**第一个比特为矩阵最高位**
#     （Qiskit 兼容）；寄存器嵌入遵循小端序（qubit 0 = 最低有效位）。
# =============================================================================

"""Gate：不可定位的数学对象（定义层）。子类型：`ConstGate` / `ParamGate` / `UserGate` / `ModifiedGate`。"""
abstract type Gate end

# ── Gate 接口协议 ─────────────────────────────────────────────────────────────
"门作用的量子比特数。"
nqubits(g::Gate) = error("`nqubits` not implemented for $(typeof(g)).")

"门参数个数（0 = 固定门）。"
num_params(g::Gate) = error("`num_params` not implemented for $(typeof(g)).")

"门名（Symbol）。"
name(g::Gate) = error("`name` not implemented for $(typeof(g)).")

"按参数求门矩阵（固定门传空向量）。"
function mat(g::Gate, params::Vector{<:Real})
    error("`mat` not implemented for $(typeof(g)).")
end

"门的矩阵（固定门）。"
mat(g::Gate) = mat(g, Float64[])

"门的矩阵（变长参数便利形式）：`mat(RX, 0.5)`。"
mat(g::Gate, params::Real...) = mat(g, collect(Float64, params))

function _check_unitary(m::AbstractMatrix, tol::Real=1e-8)
    size(m, 1) == size(m, 2) || throw(ArgumentError("matrix must be square, got $(size(m))"))
    d = size(m, 1)
    d >= 2 && (d & (d - 1)) == 0 ||
        throw(ArgumentError("matrix dimension must be a power of two (>= 2), got $d"))
    dev = norm(adjoint(m) * m - I)
    dev <= tol || throw(ArgumentError("matrix is not unitary (‖U†U − I‖ = $dev)"))
    return nothing
end

# ── 固定矩阵门 ────────────────────────────────────────────────────────────────
"""
固定矩阵门（构造时校验酉性）。

类型参数：`N` = 比特数（下游可按 arity 静态分派）；`T` = 矩阵元素类型
（实数/复数均可；整数输入自动提升为 `Float64`）。
"""
struct ConstGate{N,T<:Number} <: Gate
    name::Symbol
    matrix::Matrix{T}

    function ConstGate(name::Symbol, matrix::AbstractMatrix)
        size(matrix, 1) == size(matrix, 2) || throw(ArgumentError("matrix must be square"))
        d = size(matrix, 1)
        d >= 2 && (d & (d - 1)) == 0 ||
            throw(ArgumentError("matrix dimension must be a power of two (>= 2), got $d"))
        T0 = eltype(matrix)
        T = T0 <: Integer ? Float64 : T0 <: Complex{<:Integer} ? ComplexF64 : T0
        m = T === T0 ? copy(matrix) : Matrix{T}(matrix)
        _check_unitary(m)
        new{Int(log2(d)),T}(name, m)
    end
end

nqubits(::ConstGate{N}) where {N} = N
num_params(::ConstGate) = 0
name(g::ConstGate) = g.name
mat(g::ConstGate, params::Vector{<:Real}) = (isempty(params) || throw(ArgumentError("$(g.name) takes no parameters")); g.matrix)

Base.:(==)(a::ConstGate, b::ConstGate) = a.name === b.name && a.matrix == b.matrix

# ── 参数化矩阵门 ──────────────────────────────────────────────────────────────
"""参数化矩阵门：`matrix_fn(θ...) -> AbstractMatrix`；比特数 `N` 为类型参数，参数个数为运行期字段。"""
struct ParamGate{N} <: Gate
    name::Symbol
    nparams::Int
    matrix_fn::Function

    function ParamGate(name::Symbol, n::Integer, nparams::Integer, matrix_fn::Function)
        n >= 1 || throw(ArgumentError("n must be >= 1"))
        nparams >= 1 || throw(ArgumentError("nparams must be >= 1"))
        new{Int(n)}(name, Int(nparams), matrix_fn)
    end
end

nqubits(::ParamGate{N}) where {N} = N
num_params(g::ParamGate) = g.nparams
name(g::ParamGate) = g.name
Base.:(==)(a::ParamGate, b::ParamGate) = a.name === b.name && a.matrix_fn === b.matrix_fn
function mat(g::ParamGate{N}, params::Vector{<:Real}) where {N}
    length(params) == g.nparams ||
        throw(ArgumentError("$(g.name) expects $(g.nparams) parameters, got $(length(params))"))
    m = g.matrix_fn(params...)
    m isa AbstractMatrix || throw(ArgumentError("$(g.name) matrix_fn must return a matrix"))
    size(m) == (1 << N, 1 << N) ||
        throw(ArgumentError("$(g.name) matrix_fn returned a matrix of size $(size(m))"))
    return m isa Matrix ? m : Matrix(m)
end

# ── 受控构造辅助 ──────────────────────────────────────────────────────────────
# 控制比特为门矩阵的最高位（与 qubit 列表中控制比特在前一致）。
function _controlled(u::AbstractMatrix)
    k = size(u, 1)
    size(u, 2) == k || throw(ArgumentError("matrix must be square"))
    T = promote_type(eltype(u), Float64)
    m = Matrix{T}(I, 2k, 2k)
    m[k+1:end, k+1:end] .= u
    return m
end

# ── 门库 ──────────────────────────────────────────────────────────────────────
# 单比特固定门
const ID   = ConstGate(:ID, Matrix{ComplexF64}(I, 2, 2))
const X    = ConstGate(:X, [0 1; 1 0])
const Y    = ConstGate(:Y, [0 -im; im 0])
const Z    = ConstGate(:Z, [1 0; 0 -1])
const H    = ConstGate(:H, [1 1; 1 -1]/sqrt(2))
const S    = ConstGate(:S, [1 0; 0 im])
const SDAG = ConstGate(:SDAG, [1 0; 0 -im])
const T    = ConstGate(:T, [1 0; 0 cis(π/4)])
const TDAG = ConstGate(:TDAG, [1 0; 0 cis(-π/4)])
const SX   = ConstGate(:SX, [1+im 1-im; 1-im 1+im]/2)   # √X

# 两比特固定门
const CX    = ConstGate(:CX, [1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0])
const CY    = ConstGate(:CY, _controlled(Y.matrix))
const CZ    = ConstGate(:CZ, [1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 -1])
const CH    = ConstGate(:CH, _controlled(H.matrix))
const SWAP  = ConstGate(:SWAP, [1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1])
const ISWAP = ConstGate(:ISWAP, [1 0 0 0; 0 0 im 0; 0 im 0 0; 0 0 0 1])

# 三比特固定门
const CCX    = ConstGate(:CCX, _controlled(_controlled(X.matrix)))
const CSWAP  = ConstGate(:CSWAP, _controlled(SWAP.matrix))
const TOFFOLI = CCX   # 别名

# 单比特旋转
const RX = ParamGate(:RX, 1, 1, θ -> ComplexF64[cos(θ/2) -im*sin(θ/2); -im*sin(θ/2) cos(θ/2)])
const RY = ParamGate(:RY, 1, 1, θ -> ComplexF64[cos(θ/2) -sin(θ/2); sin(θ/2) cos(θ/2)])
const RZ = ParamGate(:RZ, 1, 1, λ -> ComplexF64[cis(-λ/2) 0; 0 cis(λ/2)])
const PHASE = ParamGate(:PHASE, 1, 1, λ -> ComplexF64[1 0; 0 cis(λ)])
# 离子阱原生门：VirtualZ 是软件定义的帧变化（等价线路模型下的 RZ）
const VirtualZ = ParamGate(:VirtualZ, 1, 1, λ -> ComplexF64[cis(-λ/2) 0; 0 cis(λ/2)])

# 两比特旋转 / 受控门
const CRX = ParamGate(:CRX, 2, 1, θ -> _controlled(RX.matrix_fn(θ)))
const CPHASE = ParamGate(:CPHASE, 2, 1, λ -> ComplexF64[1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 cis(λ)])
const RXX = ParamGate(:RXX, 2, 1, θ -> begin
    c = cos(θ/2); s = sin(θ/2)
    ComplexF64[c 0 0 -im*s; 0 c -im*s 0; 0 -im*s c 0; -im*s 0 0 c]
end)
const RZZ = ParamGate(:RZZ, 2, 1, θ -> ComplexF64[cis(-θ/2) 0 0 0; 0 cis(θ/2) 0 0; 0 0 cis(θ/2) 0; 0 0 0 cis(-θ/2)])

# Mølmer–Sørensen 门（离子阱）：MS(θ, φ) = exp(-i θ/2 (cos φ X⊗X + sin φ Y⊗Y))
# φ=0 时退化为 RXX(θ)；θ=π/2 为最大纠缠门。
const MS = ParamGate(:MS, 2, 2, (θ, φ) -> begin
    c = cos(θ/2); s = sin(θ/2)
    a = cos(φ) - sin(φ); b = cos(φ) + sin(φ)
    ComplexF64[c 0 0 -im*s*a; 0 c -im*s*b 0; 0 -im*s*b c 0; -im*s*a 0 0 c]
end)

# ── 仅供 QASM 导入使用的内部门（不导出） ─────────────────────────────────────
# u3(θ,φ,λ) = [[cos θ/2, -e^{iλ} sin θ/2], [e^{iφ} sin θ/2, e^{i(φ+λ)} cos θ/2]]
const _U3 = ParamGate(:u3, 1, 3, (θ, φ, λ) -> ComplexF64[
    cos(θ/2)            -exp(im*λ)*sin(θ/2);
    exp(im*φ)*sin(θ/2)  exp(im*(φ+λ))*cos(θ/2)])
const _U2 = ParamGate(:u2, 1, 2, (φ, λ) -> _U3.matrix_fn(π/2, φ, λ))
const _CRZ = ParamGate(:crz, 2, 1, λ -> ComplexF64[1 0 0 0; 0 1 0 0; 0 0 cis(-λ/2) 0; 0 0 0 cis(λ/2)])
const _CRY = ParamGate(:cry, 2, 1, θ -> _controlled(RY.matrix_fn(θ)))
const _CU3 = ParamGate(:cu3, 2, 3, (θ, φ, λ) -> _controlled(_U3.matrix_fn(θ, φ, λ)))
const _CU = ParamGate(:cu, 2, 4, (θ, φ, λ, γ) -> cis(γ) * _controlled(_U3.matrix_fn(θ, φ, λ)))
const _RYY = ParamGate(:RYY, 2, 1, θ -> begin
    c = cos(θ/2); s = sin(θ/2)
    ComplexF64[c 0 0 im*s; 0 c -im*s 0; 0 -im*s c 0; im*s 0 0 c]
end)
