# 下游扩展协议（Extending）

`Operation` 是开放类型：下游包（QCCD 编译器、QEC、模拟器）**不需要修改本包源码**，
定义新的指令类型并实现最小协议即可——这是 Julia 多重派发相对 visitor 模式的核心优势。

## 1. 最小契约

```julia
using QuantumCircuits

# 例：QCCDCompiler.jl 定义离子阱输运指令
struct Relocate <: Operation
    qubits::Vector{Int}
    path::Vector{Int}
end
```

| 协议函数 | 默认 | 说明 |
|---|---|---|
| `qubits(op)` | **无（必须实现）** | 涉及的量子比特 |
| `clbits(op)` | `[]` | 涉及的经典位 |
| `is_unitary(op)` | `false` | 是否酉操作 |
| `mat(op)` | 报错 | 仅酉操作需要 |

最小实现：

```julia
QuantumCircuits.qubits(op::Relocate) = op.qubits
# Relocate 无矩阵 → 不实现 mat；validate 对无语义指令默认放行
```

实现 `qubits` 后，`depth` / `qubits_used` / `dag` / `validate` / QASM 导出前置检查
等分析函数立即对自定义指令可用。

## 2. 序列化扩展

`to_qasm` 对无法识别的操作会调用既有路径报错。v1 的扩展点：
为自定义操作实现与内部一致的方法（推荐通过类型分派扩展内部 `_qasm*_op!` 的语义），
或退化为在下游包内实现独立的导出器。

## 3. 建议遵守的约定

- 新指令类型加入 `Operation` 层次，字段自包含（可复制、可比较）；
- 指令**不携带执行语义**——"怎么算"由后端定义；
- QASM 不可表达的结构（如输运指令）导出时应显式报错，而非静默丢弃；
- 需要参与参数绑定时，实现内部钩子 `_collect_params!` / `_assign_op`
  （参考 `BlockOp` / `IfOp` 的做法）。

## 4. 模拟器后端关心什么

- `GateOp` 的类型参数：`GateOp{<:GateOp}` 的 `gate` 字段类型携带 arity 信息
  （如 `ConstGate{1}` / `CtrlGate{ConstGate{1},2}`），可按 arity 静态分派内核；
- [约定](conventions.md#4-把-k-比特门矩阵转换成-2k-阶张量) 的矩阵↔张量转换公式
  是态矢/张量网络内核的实现依据；
- `Param` 未绑定时 `mat` 报错——后端可自行按 `parameters(op)` 顺序接数值参数。

## 5. 包扩展：Luxor 图形后端

本包按 Julia 1.9+ 包扩展机制提供图形渲染（`Project.toml` 的 `[weakdeps]`/`[extensions]`）：

- 不安装 Luxor 时，`draw`（文本图）始终可用；
- `using Luxor` 后，扩展模块 `QuantumCircuitsLuxorExt` 自动加载，提供：

| 函数 | 说明 |
|---|---|
| `plot(c; format=:svg)` | 返回 SVG 字符串（`filename=...` 时保存文件，按扩展名支持 `svg`/`png`/`pdf`） |
| `save_plot(c, "file.svg")` | 保存到文件 |

扩展通过 `Base.get_extension(QuantumCircuits, :QuantumCircuitsLuxorExt)` 访问；
`plot` / `save_plot` 由扩展模块导出，用法：

```julia
using QuantumCircuits, Luxor
ext = Base.get_extension(QuantumCircuits, :QuantumCircuitsLuxorExt)
ext.save_plot(c, "bell.svg")   # 矢量图，可嵌入网页 / LaTeX（svg→pdf）
```

图形后端复用文本图 `draw` 的同一布局（`_layout` 列模型），
新增门样式时两边一起改。
