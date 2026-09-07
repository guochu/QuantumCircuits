# 门（Gates）与修饰符（Modifiers）

## 1. 定义层与定位层

- **`Gate`（定义层）**：不携带比特位置的数学对象，可复用、可修饰。
- **`Operation`（定位层）**：`Gate` 作用于具体比特后得到 `GateOp`，是线路的基本单元。

```julia
H          # ::ConstGate —— 数学对象
H(1)       # ::GateOp   —— 定位：作用在 qubit 1 上
CX(1, 2)   # 控制比特 1，目标比特 2
RX(π/2, 3) # 参数在前，比特在后（与 Qiskit 线路方法签名一致）
RX(:θ, 3)  # Symbol 自动提升为 Param(:θ)（符号参数）
```

## 2. Gate 接口

| 函数 | 说明 |
|---|---|
| `nqubits(g)` | 门作用的比特数（`ConstGate{N}` 在编译期可得） |
| `num_params(g)` | 参数个数（0 = 固定门） |
| `name(g)` | 门名（`Symbol`），用于 `count_ops` 与序列化 |
| `mat(g)` / `mat(g, params)` | 门矩阵 `2^n × 2^n`（元素类型由构造决定，实/复均可） |

### 具体类型

| 类型 | 类型参数 | 字段 | 构造 |
|---|---|---|---|
| `ConstGate{N,T}` | `N` 比特数、`T` 元素类型 | `name, matrix` | `ConstGate(name, matrix)`（校验酉性；整数/复整数元素自动提升） |
| `ParamGate{N}` | `N` 比特数 | `name, nparams, matrix_fn` | `ParamGate(name, n, nparams, fn)` |
| `UserGate{N,T}` | `N` 比特数、`T` 元素类型 | `name, nparams, matrix, def` | `UserGate(name, matrix)` 或 `UserGate(name, n, def::Circuit)`（延迟分解） |

自定义门：

```julia
g  = usergate(:mygate, [0 1; 1 0])   # 矩阵定义（等价 UserGate(:mygate, ...))
g(3)                                  # ⇒ GateOp(g, [3])

def = Circuit([H(1), CX(1, 2)])
bell = UserGate(:bell, 2, def)        # 子线路定义（必须全酉），mat 惰性合成
mat(bell)
```

## 3. 门库

全部导出为**可调用单例**，调用签名 = `(参数…, 比特…)`：

| 类别 | 门 |
|---|---|
| 单比特固定 | `ID X Y Z H S SDAG T TDAG SX` |
| 两比特固定 | `CX CY CZ CH SWAP ISWAP` |
| 三比特固定 | `CCX`（别名 `TOFFOLI`）`CSWAP` |
| 单比特旋转 | `RX RY RZ PHASE` |
| 受控 / 两比特旋转 | `CRX CPHASE RXX RZZ` |
| 离子阱 | `MS(θ, φ)`（= exp(-iθ/2(cosφ XX + sinφ YY))，φ=0 退化为 `RXX`）`VirtualZ` |

矩阵约定：**列表中第一个比特是矩阵索引的最高位**（详见
[约定 §3](conventions.md#3-多比特门的比特作用顺序)）。例如
`mat(CX) == [1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]`。

## 4. 修饰符（惰性、可组合）

| 修饰符 | 形式 | 说明 |
|---|---|---|
| `inv` | `inv(g)` / `inv(op)` | 逆（`mat = U†`） |
| `pow` | `pow(g, k)` / `pow(op, k)` | 幂（整数幂精确；分数幂经特征分解） |
| `ctrl` | `ctrl(g, n…)` / `ctrl(op, qs…)` | 正控；作用于 `GateOp` 时新控制比特**前置** |
| `negctrl` | `negctrl(g, n…)` / `negctrl(op, qs…)` | 负控 |

规范化顺序：`negctrl → ctrl → pow → inv`（`mat` 惰性求值时应用；四者相互可交换，嵌套任意组合）。

```julia
ctrl(H(1), 2)          # GateOp(CtrlGate(H,1,[0]), [2, 1])：矩阵为 [I ⊕ H]（即 CH）
negctrl(H(3), 1, 2)    # 双负控
inv(RZZ(0.3, 1, 2))    # 逆 ZZ 门
pow(H, 2)              # 恒等（H² = I）
pow(X(1), 0.5)         # √X（分数幂经谱分解，可能有数值误差）
```

矩阵语义（`_controlled_matrix`）：控制比特是受控矩阵的**最高位**，逐块块对角——
正控在控制位 = 1 的块放置内部矩阵，负控在控制位 = 0 的块放置。

## 5. 元素类型（实数 / 复数）

矩阵元素类型是类型参数 `T<:Number`，**不强制复数**：

```julia
mat(X)   # ::Matrix{Float64}    —— 实门保持实矩阵
mat(Y)   # ::Matrix{ComplexF64}
```

整数/复整数输入在构造时自动提升为 `Float64` / `ComplexF64`。
`ConstGate` / `UserGate` 构造时校验酉性；`ParamGate` 的 `matrix_fn` 返回什么元素类型，
`mat` 就给什么。
