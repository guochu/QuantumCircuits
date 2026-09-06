# QuantumCircuits.jl

```@docs
QuantumCircuits
```

## 安装

```julia
import Pkg
Pkg.develop(path = "path/to/QuantumCircuits")
```

依赖仅 Julia 标准库 `LinearAlgebra`。

## 快速上手

```julia
using QuantumCircuits

# ── Bell 态 + 测量 ──────────────────────────────
c = Circuit(2)
push!(c, H(0))                     # 门调用即定位：H(0) ⇒ GateOp(H, [0])
push!(c, CX(0, 1))                 # 控制 = 比特 0，目标 = 比特 1
push!(c, measure([0, 1], c.cregs[1][1:2]))
print(to_qasm(c))                  # 导出 OpenQASM 3

# ── 变分线路（符号参数）─────────────────────────
c = Circuit(4)
φ = params(:φ, 3)
for q in 0:3
    push!(c, RX(:θ, q))            # Symbol 自动提升为 Param
end
for q in 0:2
    push!(c, RZZ(φ[q+1], q, q+1))  # φ[i] 各自独立
end
parameters(c)                      # 收集符号参数（去重、按出现序）
bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))

# ── QEC 综合征轮：块 + 重复 ─────────────────────
round_i = Circuit(5, cregs=[CReg(:syn, 2)])
push!(round_i, CX(0, 4)); push!(round_i, CX(2, 4))
if_then(round_i, round_i.cregs[1][1] == 1, Circuit([X(1)]))
syn = Circuit(5)
push!(syn, block(round_i; name=:syndrome_round, repeat=5))

# ── 含噪线路（噪声即指令）───────────────────────
noisy = Circuit(2)
push!(noisy, H(0)); push!(noisy, CX(0, 1))
push!(noisy, Depolarizing([0, 1], 1e-3))
push!(noisy, PauliError(1, (1e-3, 1e-3, 2e-3)))
```

## 文档目录

| 页面 | 内容 |
|---|---|
| [约定](conventions.md) | **必读**：比特索引、端序、门矩阵 ↔ 张量转换 |
| [门与修饰符](gates.md) | 门接口、门库、`inv/pow/ctrl/negctrl` |
| [线路](circuits.md) | Circuit、构造 DSL、分析、参数绑定、经典控制、布局 |
| [复合结构](composite.md) | UserGate（定义层）、BlockOp（定位层）、unroll |
| [噪声信道](channels.md) | Kraus / Pauli / 去极化 / 阻尼 |
| [Hamiltonian](hamiltonian.md) | 子模块：Pauli 代数 |
| [QASM 序列化](io.md) | OpenQASM 2 / 3 |
| [扩展协议](extending.md) | 下游扩展（自定义 Operation） |
| [API 参考](api.md) | 由源码 docstring 自动生成 |

## 构建

```bash
julia --project=docs docs/make.jl    # 输出在 docs/build/
```
