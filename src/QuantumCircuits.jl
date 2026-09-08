"""
    QuantumCircuits

全栈量子软件的**唯一中间表示（IR）层**：从算法线路到 QEC 综合征线路再到
QCCD 编译产物，共用这一种表示。

设计原则：

1. **定义与定位分离**（Cirq 模式）：`Gate` 是不携带比特位置的数学对象；
   `Gate` 作用于比特后得到 `Operation`。线路是 `Operation` 的序列。
2. **IR 无执行语义**：本包不定义 `apply!` 到任何态，作用入口由各模拟器后端实现。
3. **经典层一等公民**：经典寄存器、测量写回、条件分支进 IR。
4. **修饰符可组合**：`inv / pow / ctrl / negctrl` 四个惰性包装。
5. **布局一等公民**：线路自带 `initial_layout / output_permutation`。
6. **开放类型 + 小接口**：`Operation` 是抽象类型，下游只需实现最小协议
   （`qubits` / `clbits` / `is_unitary` / `mat`）。
7. **约定**：比特索引 1-based（与 Julia 惯例一致）、小端序（qubit 1 = 最低有效位）；类型 PascalCase、函数 snake_case、
   `!` 表示就地修改。
8. **参数用符号**：门参数接受 `Real | Param | Symbol`，变分工作流先建线路后绑参。

模块结构：`bits` / `params` / `gates` / `modifiers` / `ops` / `channels` /
`classical` / `circuit` / `composite` / `dag` / `Hamiltonian`（子模块：Pauli 代数）/
`Interface`（子模块：模拟后端契约）/ `io`。
"""
module QuantumCircuits

using LinearAlgebra

# ── 比特 / 寄存器 ──
export Qubit, QReg, CReg, ClbitRef

# ── 门 ──
export Gate, ConstGate, ParamGate, UserGate,
       H, X, Y, Z, S, T, SDAG, TDAG, SX, ID,
       CX, CY, CZ, CH, SWAP, ISWAP, CCX, CSWAP,
       RX, RY, RZ, PHASE, CRX, CPHASE, RXX, RZZ, MS, VirtualZ,
       usergate

# ── 修饰符 ──
export pow, ctrl, negctrl            # inv 直接扩展 Base.inv，无需再导出

# ── 操作 ──
export Operation, GateOp, MeasOp, ReinitOp, BarrierOp, ChannelOp, IfOp, BlockOp,
       measure, measure_all!, barrier, block, reinit,
       unroll, unroll!, assign, assign!, draw

# ── 信道 ──
export Channel, KrausChannel, PauliChannel, UnitaryChannel,
       PauliError, Depolarizing, AmplitudeDamping, PhaseDamping, kraus

# ── 经典控制 ──
export Cond, if_then

# ── 线路 ──
export Circuit, Layout,
       Param, ParamVector, params, parameters, dagger,
       depth, num_ops, count_ops, qubits_used, validate, dag,
       CircuitDAG, nodes, dependencies
# `push!` / `append!` / `<<` 是对 Base 函数的扩展，Base 已导出，直接可用，无需重复导出。

# ── 模拟后端契约（Interface 子模块，重导出） ──
export Backend, SimResult, simulate, simulate!, expectation,
       supports, max_qubits,
       set_default_backend!, default_backend, clear_default_backend!,
       counts_key

# ── IO ──
export to_qasm, write_qasm, read_qasm

# ── 协议（下游扩展点） ──
export qubits, clbits, is_unitary, mat

# ── Gate 接口（门作者使用） ──
export nqubits, num_params, name

include("bits.jl")
include("params.jl")
include("gates.jl")        # Gate 抽象 + 门库单例
include("channels.jl")     # 信道类型 + kraus + 噪声指令构造
include("ops.jl")          # Operation + GateOp/MeasOp/ReinitOp/BarrierOp/ChannelOp
include("modifiers.jl")    # inv / pow / ctrl / negctrl
include("circuit.jl")      # Circuit + DSL + 分析 + 绑参
include("classical.jl")    # Cond + IfOp + if_then
include("composite.jl")    # UserGate + BlockOp + unroll + 矩阵嵌入
include("draw.jl")         # 线路文本图（draw）
include("dag.jl")          # 依赖 DAG
include("hamiltonians/hamiltonians.jl")  # 子模块 Hamiltonian：Pauli / 自旋算符代数
include("interface.jl")    # 子模块 Interface：模拟后端契约（Backend / simulate / SimResult）
include("io/io.jl")        # to_qasm / write_qasm / read_qasm + 共享工具
include("io/qasm2.jl")     # QASM2 读写 + 统一解析器
include("io/qasm3.jl")     # QASM3 读写

# 重导出 Interface 契约（算法包 `using QuantumCircuits` 即可直接使用）
using .Interface: Backend, SimResult, simulate, expectation,
       supports, max_qubits,
       set_default_backend!, default_backend, clear_default_backend!,
       counts_key

end # module
