# =============================================================================
# interface.jl — 模拟后端契约（Interface 子模块）
#
# IR 本身无执行语义；本模块只声明"可执行线路的引擎"必须满足的契约。
# 算法包（如 ShorAlgorithm）只依赖本契约 + IR，后端实例由调用方注入：
#
#     using QuantumCircuits
#     using QuantumCircuits.Interface: Backend, simulate
#
#     struct MyBackend <: Backend; end
#     function simulate(c::Circuit, ::MyBackend; shots::Int = 0,
#                       seed::Union{Nothing,Integer} = nothing)
#         ...
#     end
#
# 契约组成：
#   * `Backend`                        —— 后端标记抽象类型（唯一必依赖的类型）
#   * `simulate(c, b; shots, seed)`    —— 唯一必须实现的方法
#   * `expectation(h, b, c; params)`   —— 可选：PauliSum 期望值直算
#   * `supports` / `max_qubits`        —— 能力查询（算法包据此自保）
#   * `SimResult`                      —— 统一返回类型
#   * `counts_key`                     —— 计数键格式约定（跨后端可比的前提）
#   * `set_default_backend!` 等        —— 会话级默认后端（便利层，非必需）
# =============================================================================

module Interface

using QuantumCircuits: Circuit, CReg, ClbitRef
using ..Hamiltonian: PauliSum

export Backend, SimResult, simulate, simulate!, expectation,
       supports, max_qubits,
       set_default_backend!, default_backend, clear_default_backend!,
       counts_key

"""
    Backend <: Any

模拟后端抽象类型：一切可执行 `QuantumCircuits.Circuit` 的引擎的标记类型。

后端包（VQC / MPSSimulator / 稳定子后端等）定义 `<: Backend` 的具体类型，
并为 [`simulate`](@ref) 添加对应方法；算法包只依赖 `Backend` 抽象类型本身，
后端实例由调用方注入。

标准能力名（见 [`supports`](@ref)）：`:statevector`、`:mid_measure`（中途测量）、
`:noise`（信道指令）、`:adjoint`。
"""
abstract type Backend end

"""
    SimResult(counts, state; metadata = Dict{Symbol,Any}())

`simulate` 的统一返回类型。

* `counts::Union{Nothing,Dict{String,Int}}`——弱模拟（采样）结果，`shots > 0`
  时非空；键格式见 [`counts_key`](@ref)。
* `state::Any`——强模拟结果（后端私有的态表示），后端不支持时为 `nothing`。
* `metadata::Dict{Symbol,Any}`——附加信息（用时、截断误差、后端名等）。

便利方法：`r["c:011"]` 取单个计数（等价 `r.counts["c:011"]`）、`haskey(r, key)`。
"""
Base.@kwdef struct SimResult
    counts::Union{Nothing,Dict{String,Int}} = nothing
    state::Any = nothing
    metadata::Dict{Symbol,Any} = Dict{Symbol,Any}()
end

SimResult(counts::Union{Nothing,Dict{String,Int}}, state) =
    SimResult(; counts, state)

function Base.show(io::IO, r::SimResult)
    print(io, "SimResult(")
    print(io, "counts=", r.counts === nothing ? "nothing" : "$(length(r.counts)) keys")
    print(io, ", state=", r.state === nothing ? "nothing" : typeof(r.state))
    return print(io, ")")
end

Base.getindex(r::SimResult, key::AbstractString) = r.counts[key]
Base.haskey(r::SimResult, key::AbstractString) =
    r.counts !== nothing && haskey(r.counts, key)

# ── simulate：唯一必须实现的契约 ─────────────────────────────────────────────

"""
    simulate(c::Circuit, backend::Backend; shots = 0, seed = nothing, kwargs...)
        -> SimResult
    simulate(c::Circuit; shots = 0, seed = nothing, kwargs...)
        -> SimResult          # 使用 set_default_backend! 设置的默认后端

在线路 `c` 上执行 `backend`。这是后端**唯一必须实现**的契约方法。

* `shots = 0`：强模拟——`result.state` 给出后端态表示（不支持时为 `nothing`）。
* `shots > 0`：弱模拟——按测量规则采样 `shots` 次，`result.counts` 给出计数
  （键格式见 [`counts_key`](@ref)）。
* `seed`：采样随机种子的约定通道；支持的后端应保证同种子同结果。
"""
function simulate end

function simulate(c::Circuit, backend::Backend;
                  shots::Int = 0, seed::Union{Nothing,Integer} = nothing, kwargs...)
    return throw(ArgumentError("backend $(typeof(backend)) does not implement " *
        "simulate(::Circuit, ::$(typeof(backend))); " *
        "see QuantumCircuits.Interface for the contract"))
end

function simulate(c::Circuit;
                  shots::Int = 0, seed::Union{Nothing,Integer} = nothing, kwargs...)
    backend = default_backend()
    if backend === nothing
        return throw(ArgumentError(
            "no default backend set; call set_default_backend!(backend) " *
            "or pass a backend explicitly: simulate(c, backend)"))
    end
    return simulate(c, backend; shots, seed, kwargs...)
end

"""
    simulate!(c::Circuit, state; params = nothing) -> state

`simulate` 的就地版本：把线路演化作用到给定态上。
泛型由本模块声明；基于态的方法由各模拟器扩展提供
（如 VQC 的扩展；**不属于** `Backend` 契约的一部分）。
"""
function simulate! end

# ── expectation：可选契约 ────────────────────────────────────────────────────

"""
    expectation(h::Hamiltonian.PauliSum, c::Circuit, backend::Backend;
                params = nothing, kwargs...) -> Real
    expectation(h::Hamiltonian.PauliSum, state, backend::Backend) -> Real

 Pauli 和 `h` 在（绑参后的）线路 `c` 或后端态 `state` 上的期望值；
`backend` 置于最后一个参数位。
可选契约：不实现的算法不应依赖；后端可任选一种参数形式实现。
"""
function expectation end

function expectation(h::PauliSum, c::Circuit, backend::Backend;
                     params = nothing, kwargs...)
    return throw(ArgumentError("backend $(typeof(backend)) does not implement " *
        "expectation(::PauliSum, ::Circuit, ::$(typeof(backend)))"))
end

# ── 能力查询：算法包据此自保 ─────────────────────────────────────────────────

"""
    supports(backend::Backend, cap::Symbol) -> Bool
    max_qubits(backend::Backend) -> Int

能力查询。默认全部不支持 / 无上限；后端按需覆盖。

标准能力名：`:statevector`（可输出态矢量）、`:mid_measure`（支持中途测量与前馈）、
`:noise`（支持信道指令）、`:adjoint`（支持线路求逆）。

算法包应在执行前断言所需能力（如 Shor 的半经典 QFT 需要 `:mid_measure`），
比静默算错好。
"""
supports(backend::Backend, cap::Symbol) = false

max_qubits(backend::Backend) = typemax(Int)

# ── 会话级默认后端（便利层） ─────────────────────────────────────────────────

const DEFAULT_BACKEND = Ref{Union{Nothing,Backend}}(nothing)

"""设置会话级默认后端：之后 `simulate(c)` 无需再传后端。返回 `backend`。"""
set_default_backend!(backend::Backend) = (DEFAULT_BACKEND[] = backend; backend)

"""返回当前默认后端（未设置时为 `nothing`）。"""
default_backend() = DEFAULT_BACKEND[]

"""清除默认后端。"""
clear_default_backend!() = (DEFAULT_BACKEND[] = nothing; nothing)

# ── 计数键格式约定 ───────────────────────────────────────────────────────────

"""
    counts_key(reg::CReg, outcome) -> String
    counts_key(c::Circuit, outcome::AbstractDict{ClbitRef,<:Integer}) -> String

把一次测量的经典结果格式化为 [`SimResult`](@ref) 的统一计数键。
**这是跨后端可比的前提，所有后端必须用本函数（或同一约定）生成键。**

约定：

* 单寄存器键形如 `"name:bits"`；`bits` 串**右端是寄存器 index 1（最低有效位）**，
  与主模块的小端序约定一致。例：3 比特寄存器 `c`，`c[1]=0, c[2]=1, c[3]=1`
  → `"c:110"`。
* 未测量的位填 `'x'`：只测了 `c[1]=1` → `"c:1xx"`。
* 多寄存器：按 `c.cregs` 声明顺序以逗号连接，如 `"c:110,anc:01"`；
  没有任何测量位的寄存器被跳过。
"""
function counts_key(reg::CReg, outcome::AbstractDict{ClbitRef,<:Integer})
    io = IOBuffer()
    print(io, reg.name, ":")
    for i in reg.n:-1:1
        v = get(outcome, ClbitRef(reg, i), nothing)
        print(io, v === nothing ? 'x' : (iszero(v) ? '0' : '1'))
    end
    return String(take!(io))
end

function counts_key(reg::CReg, bits::AbstractVector{<:Integer})
    d = Dict{ClbitRef,Int}()
    for (i, v) in enumerate(bits)
        d[ClbitRef(reg, i)] = Int(v)
    end
    return counts_key(reg, d)
end

function counts_key(c::Circuit, outcome::AbstractDict{ClbitRef,<:Integer})
    parts = String[]
    for reg in c.cregs
        measured = any(haskey(outcome, ClbitRef(reg, i)) for i in 1:reg.n)
        measured || continue
        push!(parts, counts_key(reg, outcome))
    end
    if isempty(parts)
        return throw(ArgumentError("outcome does not contain any measured clbit " *
                                   "belonging to this circuit"))
    end
    return join(parts, ",")
end

end # module Interface
