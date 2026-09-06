# 子模块 Hamiltonian（Pauli 代数）

```julia
using QuantumCircuits.Hamiltonian
```

## 1. PauliTerm：单项

```julia
PauliTerm(1.0, 1=>:Z, 2=>:X)      # 1.0 · Z₁ ⊗ X₂
PauliTerm(0=>:X)                   # 系数默认 1.0
```

- 位置**自动升序排序**；同 qubit 重复项自动相乘合并（`X·X → I`，`X·Y → iZ`）；
- 系数类型参数化 `PauliTerm{T<:Number}`：实数/复数均可，整数系数自动提升为 `Float64`；
- 合并与乘法产生的相位（`i`/`-i`）自动并入系数并按需提升类型。

## 2. PauliSum：厄米算符 = Pauli 项之和

```julia
h = PauliTerm(1.0, 0=>:Z) + PauliTerm(2.0, 1=>:X)
h = PauliSum([PauliTerm(1.0, 0=>:Z), PauliTerm(0.5, 1=>:X)])
```

- `+` / `-` 自动**合并同类项**、去掉零系数项（保持首次出现顺序）；
- `*` 按 Pauli 代数分配相乘（同 qubit 查乘法表，跨 qubit 拼接）；
- `2.0 * h` / `adjoint(h)` 可用（Pauli 串厄米，伴随仅取系数共轭）。

## 3. 展开为矩阵

```julia
mat(h::PauliSum, n::Int)   # → SparseMatrixCSC（2^n × 2^n）
```

- **小端序**：qubit 0 = 最低有效位，即 `PauliTerm(1.0, 0=>:X)` 在 2 比特空间为
  `kron(I₂, X)`；
- 元素类型随系数与 Pauli 串自然提升（全实项 ⇒ `SparseMatrixCSC{Float64}`，
  含 `:Y` 或复系数 ⇒ `ComplexF64`）；
- `expectation` 由模拟器后端实现，本包**不**提供。

## 4. 示例：氢分子 H₂（STO-3G, 0.7414 Å）哈密顿量的写法

```julia
h = -0.810547980537326 * PauliSum([]) +
     0.172183932619155 * PauliTerm(1.0, 0=>:Z) +
     ...
```

（示意——空 `PauliTerm()` 表示恒等项，可写 `PauliTerm(1.0)`。）
