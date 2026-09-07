# QuantumCircuits.jl

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)
[![Julia](https://img.shields.io/badge/julia-1.10+-9558B2)](https://julialang.org)

全栈量子软件的**唯一中间表示（IR）层**：从算法线路、QEC 综合征线路到离子阱
（QCCD）编译产物，共用这一种表示。

本包只描述“是什么”（线路结构），不定义“怎么算”——模拟、编译、可视化由下游包
（Simulators.jl、QCCDCompiler.jl 等）基于同一 IR 实现。

## 设计亮点

- **定义与定位分离**（Cirq 模式）：`Gate` 是数学对象，作用于比特后得到 `Operation`
  （`H(1)` ⇒ `GateOp`），修饰、复用、求矩阵更干净；
- **类型参数化门**：`ConstGate{N,T}` / `ParamGate{N}` / `CtrlGate{G,K}`，
  下游可按比特数静态分派；矩阵元素类型实数/复数均可；
- **经典层一等公民**：经典寄存器、测量写回、条件分支（`IfOp`）进 IR；
- **修饰符可组合**：`inv / pow / ctrl / negctrl` 惰性包装，取代变体类型枚举；
- **布局一等公民**：线路自带 `Layout(initial, output)`；
- **噪声即指令**（Stim 先例）：`Depolarizing` / `PauliError` 等直接进线路；
- **开放扩展**：自定义指令只需实现 `qubits / clbits / is_unitary / mat` 四函数协议。

## 安装

```julia
import Pkg
Pkg.develop(path = "path/to/QuantumCircuits")
```

依赖仅 Julia 标准库 `LinearAlgebra`（Julia ≥ 1.10）。

## 快速上手

```julia
using QuantumCircuits

# ── Bell 态 + 测量 ──────────────────────────────
c = Circuit(2)
push!(c, H(1))                     # 门调用即定位：H(1) ⇒ GateOp(H, [1])
push!(c, CX(1, 2))                 # 控制 = 比特 1，目标 = 比特 2
push!(c, measure([1, 2], c.cregs[1][1:2]))
print(to_qasm(c))                  # 导出 OpenQASM 3

# ── 变分线路（符号参数）─────────────────────────
φ = params(:φ, 3)
c = Circuit(4)
for q in 1:4
    push!(c, RX(:θ, q))            # Symbol 自动提升为 Param
end
for q in 1:3
    push!(c, RZZ(φ[q], q, q+1))
end
parameters(c)                      # [θ, φ[1], φ[2], φ[3]]（去重、按出现序）
bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))

# ── QEC 综合征轮：块 + 重复 ─────────────────────
round_i = Circuit(5, cregs=[CReg(:syn, 2)])
push!(round_i, CX(1, 5)); push!(round_i, CX(3, 5))
if_then(round_i, round_i.cregs[1][1] == 1, Circuit([X(1)]))
syn = Circuit(5)
push!(syn, block(round_i; name=:syndrome_round, repeat=5))

# ── 含噪线路（噪声即指令）───────────────────────
noisy = Circuit(2)
push!(noisy, H(1)); push!(noisy, CX(1, 2))
push!(noisy, Depolarizing([1, 2], 1e-3))
push!(noisy, PauliError(2, (1e-3, 1e-3, 2e-3)))
```

## 核心约定

| 事项 | 约定 |
|---|---|
| 比特索引 | **1-based**（与 Julia 惯例一致，`q[1] ⇒ Qubit(1)`）；QASM 读写自动换算 |
| 端序 | **小端序**：qubit 1 = 最低有效位（与 Qiskit 编号平移一致） |
| 多比特门 | 列表第一个比特是门矩阵索引的**最高位**（`CX(a,b)`：a 控制、b 目标） |
| 命名 | 类型 PascalCase、函数 snake_case、`!` 表示就地修改 |

完整约定（含门矩阵 ↔ 2k 阶张量的精确转换公式）见
[docs/src/conventions.md](docs/src/conventions.md)。

## 线路可视化

文本图 `draw` 始终可用（REPL 中直接回车显示线路即为此图）：

```julia
julia> c = Circuit(2); push!(c, H(1)); push!(c, CX(1, 2))
julia> draw(c)
q[1]: ─H──●─
      │
q[2]: ────X─
```

图形输出由**包扩展**提供——安装并加载
[Luxor](https://github.com/JuliaGraphics/Luxor.jl)（弱依赖）后自动启用：

```julia
using Luxor                          # 触发扩展 QuantumCircuitsLuxorExt
ext = Base.get_extension(QuantumCircuits, :QuantumCircuitsLuxorExt)
ext.save_plot(c, "bell.svg")         # svg / png / pdf（按扩展名）
s = ext.plot(c)                      # SVG 字符串
```

不安装 Luxor 不影响本包任何 IR 功能；测试环境通过 `Pkg.test()` 自动接入 Luxor。

## 文档

按 Julia 标准方式使用 [Documenter.jl](https://documenter.juliadocs.org/stable/) 构建：

```bash
julia docs/make.jl                 # 构建到 docs/build/（含 API 参考，由 docstring 自动生成）
```

文档源在 `docs/src/`：[index](docs/src/index.md) ·
[约定](docs/src/conventions.md) · [门](docs/src/gates.md) ·
[线路](docs/src/circuits.md) · [复合结构](docs/src/composite.md) ·
[信道](docs/src/channels.md) · [Hamiltonian](docs/src/hamiltonian.md) ·
[QASM](docs/src/io.md) · [扩展协议](docs/src/extending.md) ·
[API 参考](docs/src/api.md)。

## 开发

```bash
julia --project=. test/runtests.jl    # 运行测试
```

测试按模块拆分在 `test/` 下（`gates.jl`、`circuit.jl`、`channels.jl` 等）。

## License

[GPL-3.0](LICENSE)
