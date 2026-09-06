# =============================================================================
# params.jl — 符号参数（Qiskit Parameter / PennyLane 模式）
#
# 变分工作流先建线路、后绑参：
#   * 门参数位可填 `Real | Param | Symbol`（Symbol 自动提升为 Param）。
#   * 同名参数（如 :θ）即权重共享，是有意义的建模决策。
#   * `parameters(c)` 收集 → `bind` / `bind!` 按名绑定。
# =============================================================================

"""符号参数。"""
struct Param
    name::Symbol
end

Base.show(io::IO, p::Param) = print(io, ":", p.name)

"""参数向量（Qiskit ParameterVector 模式）。`pv[i]`（1-based）⇒ `Param(Symbol("name[i]"))`。"""
struct ParamVector
    name::Symbol
    n::Int
end

"构造参数向量：`params(:φ, 3)`。"
params(name::Symbol, n::Int) = ParamVector(name, n)

Base.length(pv::ParamVector) = pv.n
Base.getindex(pv::ParamVector, i::Integer) = (1 <= i <= pv.n || throw(BoundsError(pv, i)); Param(Symbol(pv.name, "[", Int(i), "]")))
Base.getindex(pv::ParamVector, rng::AbstractVector) = Param[pv[i] for i in rng]
Base.iterate(pv::ParamVector, state::Int=1) = state > pv.n ? nothing : (pv[state], state + 1)
Base.show(io::IO, pv::ParamVector) = print(io, "ParamVector(:", pv.name, ", ", pv.n, ")")
