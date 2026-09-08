# =============================================================================
# hamiltonians.jl — 子模块 Hamiltonian：Pauli / 自旋算符代数（聚合入口）
#
# 用法：`using QuantumCircuits.Hamiltonian`
# 系数类型：`PauliTerm` 无类型参数，`coeff::Number`；实数/复数/整数均可，
# 元素类型在需要时（矩阵展开、合并）动态提升。
# 注意：`expectation` 由模拟器后端实现，本包不实现。
# =============================================================================

module Hamiltonian

using LinearAlgebra
import QuantumCircuits: mat

export PauliTerm, PauliSum, SpinOpTerm, SpinOpSum

include("paulihamiltonian.jl")   # Pauli 代数（PauliTerm / PauliSum）
include("spinhamiltonian.jl")    # 自旋算符代数（SpinOpTerm / SpinOpSum）

end # module Hamiltonian
