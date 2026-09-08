# 子模块 Hamiltonian（Pauli / 自旋算符代数）

```julia
using QuantumCircuits.Hamiltonian
```

## 1. PauliTerm：单项

```julia
PauliTerm(1.0, 1=>:Z, 2=>:X)      # 1.0 · Z₁ ⊗ X₂
PauliTerm(1=>:X)                   # 系数默认 1.0
```

- 位置**自动升序排序**；同 qubit 重复项自动相乘合并（`X·X → I`，`X·Y → iZ`）；
- `PauliTerm` **无类型参数**，`coeff::Number`（实数/复数/整数均可），
  元素类型在矩阵展开等需要时动态提升；
- 合并与乘法产生的相位（`i`/`-i`）自动并入系数并按需提升类型。

## 2. PauliSum：厄米算符 = Pauli 项之和

```julia
h = PauliTerm(1.0, 1=>:Z) + PauliTerm(2.0, 2=>:X)
h = PauliSum([PauliTerm(1.0, 1=>:Z), PauliTerm(0.5, 2=>:X)])
```

- `+` / `-` 自动**合并同类项**、去掉零系数项（保持首次出现顺序）；
- `*` 按 Pauli 代数分配相乘（同 qubit 查乘法表，跨 qubit 拼接）；
- `2.0 * h` / `adjoint(h)` 可用（Pauli 串厄米，伴随仅取系数共轭）。

## 3. 展开为矩阵

```julia
mat(h::PauliSum, n::Int)   # → Matrix（稠密，2^n × 2^n）
mat(t::PauliTerm, n::Int)  # 单项同样支持
```

- **小端序**：qubit 1 = 最低有效位，即 `PauliTerm(1.0, 1=>:X)` 在 2 比特空间为
  `kron(I₂, X)`；
- 输出为**稠密矩阵**，元素类型随系数与 Pauli 串自然提升
  （全实项 ⇒ `Matrix{Float64}`，含 `:Y` 或复系数 ⇒ `ComplexF64`）；
- `expectation` 由模拟器后端实现，本包**不**提供。

## 4. SpinOpTerm / SpinOpSum：自旋算符代数

Pauli 代数的推广：单个比特位可放任意单比特算子（`Symbol` 简写或任意 `2×2` 矩阵，
不限 Pauli / 厄米）。

```julia
SpinOpTerm(0.5, 1=>:Z, 2=>:Y)        # :I/:X/:Y/:Z/:P(σ₊)/:M(σ₋) 简写
SpinOpTerm(1.0, 3=>[0 1; -1 0])      # 任意 2×2 矩阵
s = SpinOpTerm(0.1, 3=>:X) + SpinOpTerm(1.0, 2=>:Z)^2   # ∈ SpinOpSum
mat(s, 3)                            # 稠密矩阵（小端序；小规模验证 / 对拍用）
```

同位重复项**按乘积顺序保留**（`P·M ≠ M·P`）；`adjoint` 自动处理 `:P ↔ :M` 与
矩阵伴随；`ishermitian` 可用。大规模 `apply` 作用由各模拟器后端实现。

## 5. 示例：氢分子 H₂（STO-3G, 0.7414 Å）哈密顿量的写法

```julia
h = -0.810547980537326 * PauliSum([]) +
     0.172183932619155 * PauliTerm(1.0, 1=>:Z) +
     ...
```

（示意——空 `PauliTerm()` 表示恒等项，可写 `PauliTerm(1.0)`。）
