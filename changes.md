# 接口变更记录（changes.md）

## v0.2 — 比特索引改为 1-based（2026-09）

### 动机

原设计沿用 Qiskit/OpenQASM 的 0-based 比特编号，但与 Julia 生态的 1-based
惯例不一致：寄存器取下标是 1-based（`q[1]`），取出的比特却是 `Qubit(0)`，
心智负担明显。v0.2 起**全包比特索引统一为 1-based**，与 Julia 惯例对齐；
与 QASM 的 0-based 索引由 IO 层自动换算。

### 变更内容

| 事项 | v0.1（旧） | v0.2（新） |
|---|---|---|
| `Circuit(n)` 的合法比特 | `0 … n-1` | **`1 … n`** |
| `QReg` / `CReg` 取下标 | `q[1] ⇒ Qubit(0)` | **`q[1] ⇒ Qubit(1)`**（下标即比特号） |
| `ClbitRef` 显示 | `c[0]`（0-based 显示） | **`c[1]`** |
| 小端序 | qubit 0 = 最低有效位 | **qubit 1 = 最低有效位** |
| `validate` 合法范围 | `0 ≤ q < n` | **`1 ≤ q ≤ n`** |
| `BlockOp` 局部比特 | 局部索引 `0..k-1`，`mapping[i+1]` | **局部索引 `1..k`，`mapping[i]`** |
| `_embed(M, qs, n)` 的 `qs` | 0-based | **1-based**（内部工具） |
| Hamiltonian `PauliTerm` 比特 | `0=>:X` 起 | **`1=>:X` 起** |
| `draw` / `plot` 线标签 | `q0, q1, …` | **`q1, q2, …`** |
| QASM 导出/导入 | 直接使用内部编号 | **自动换算**：内部 `q` ⇄ QASM `q[q-1]` |

### 不变的部分

- 门矩阵约定：比特列表**首比特仍是矩阵最高位**（`CX(a,b)`：a 控制、b 目标）；
- 小端序本身不变——只是编号整体 +1；
- 门矩阵 ↔ 2k 阶张量转换公式不变（公式中的 `i`、`j` 是比特值 0/1，与编号无关）；
- `Cond` / `IfOp` 的经典位引用（`ClbitRef` 内部本就是 1-based）；
- `reinit` / `ReinitOp`、`measure` / `barrier` 等 API 形态不变。

### 迁移指南

旧代码中的比特编号统一 **+1**：

```julia
# 旧（0-based）
push!(c, H(0)); push!(c, CX(0, 1)); push!(c, measure(2, c.cregs[1][1]))

# 新（1-based）
push!(c, H(1)); push!(c, CX(1, 2)); push!(c, measure(3, c.cregs[1][1]))
```

Hamiltonian：

```julia
# 旧
PauliTerm(1.0, 0=>:Z, 1=>:X)      # = kron(Z, X)
# 新（编号 +1，矩阵不变）
PauliTerm(1.0, 1=>:Z, 2=>:X)      # = kron(Z, X)
```

QASM 文本**无需改动**：QASM 本身是 0-based，读写层自动换算，
旧 QASM 文件读入后比特自动映射到 1-based 内部表示。

### 涉及文件

- `src/bits.jl`（`Qubit` / `QReg` / `CReg` / `ClbitRef`）
- `src/circuit.jl`（比特数推断、`validate`、`measure_all!`）
- `src/composite.jl`（`_embed` 位运算、`BlockOp` 映射与展开）
- `src/hamiltonian.jl`（`_kron_term`）
- `src/io/qasm2.jl`（读写偏移换算；`qasm3.jl` 共享同一工具）
- `src/draw.jl` 与 `ext/QuantumCircuitsLuxorExt.jl`（线标签 `q1, q2, …`）
- 全部测试、文档与教程 notebook 已同步更新

---

## v0.1 — reset → reinit（2026-09）

- 构造函数 `reset(q)` 更名为 **`reinit(q)`** 并导出：`Base.reset`
  （`Event` / 流复位）已占用该名字，避免 `using` 歧义；
- 类型 `ResetOp` 同步更名为 **`ReinitOp`**；
- QASM 指令词 `reset` 保持不变（OpenQASM 规范词汇）。
