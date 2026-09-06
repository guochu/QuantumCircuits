# 线路（Circuit）

线路 = `Operation` 的有序序列 + 寄存器元数据 + 布局信息。
内部是 `Vector{Operation}`，依赖分析按需 `dag()` 转换。

## 1. 构造

```julia
c = Circuit(4)                      # 4 比特；默认带 QReg(:q,4) 与 CReg(:c,4)
c = Circuit(3, cregs=[CReg(:syn, 2)])          # 自定义经典寄存器
c = Circuit([H(0), CX(0, 1)])       # 由操作序列构造（自动推断比特数）
```

字段：`ops`（操作向量）、`n`（比特数，`nqubits(c)`）、`qregs`、`cregs`、`layout`。

## 2. 构造 DSL

| 写法 | 语义 |
|---|---|
| `push!(c, op)` | 追加一个 `Operation`（主入口） |
| `push!(c, H, 1)` / `push!(c, RX, π/2, 3)` | 便利重载：门 + 参数/比特 |
| `c << H(1)` / `c << other` | 管道糖（等价 `push!` / `append!`，返回线路） |
| `append!(c, other)` | 就地拼接 |
| `c1 * c2` | `append!` 的纯函数版（先 `c1` 后 `c2`，`c1` 不变） |

线路支持 `length` / `getindex` / `iterate` / `copy` / `reverse` 等容器接口。
`push!`、`append!`、`<<` 是 Base 函数的扩展，直接可用。

## 3. 参数：Param / ParamVector / assign

门参数位可填 `Real | Param | Symbol`（`Symbol` 自动提升）：

```julia
push!(c, RX(:θ, 0))       # 权重共享：同名参数是同一个 Param
φ = params(:φ, 3)         # 参数向量；φ[i] ⇒ Param(Symbol("φ[i]"))
push!(c, RZZ(φ[1], 0, 1))
```

```julia
parameters(c)                        # 收集（去重、按首次出现顺序）
bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))   # 纯函数版
       assign(c, :θ, 0.3)            # 单参数
assign!(c, φ[1], 0.7)                # 就地版
```

- 未绑定的符号参数在 `mat` 求矩阵时报错（IR 保真传递参数信息，求值交给后端）；
- 热循环可跳过 `assign`，由模拟器按 `parameters(c)` 顺序直接接收参数向量。

## 4. 经典控制

```julia
if_then(c, c.cregs[1] == 3, then_circuit; otherwise=else_circuit)
```

- 条件 `Cond(reg, op, value)`，支持 `==  ≠  ≥  ≤`（对 `CReg` 或 `ClbitRef` 使用比较
  运算符即得 `Cond`——注意这会覆盖它们的布尔语义）；
- `IfOp` 的 `qubits` = 分支线路比特的并集，`clbits` = 条件寄存器 + 分支内的经典位；
- v1 不做 `while`/`for`（类型层次开放，后续可加，不破坏兼容）。

## 5. 分析

| 函数 | 说明 |
|---|---|
| `depth(c)` | 量子比特 + 经典位依赖图上的最长链 |
| `num_ops(c)` / `count_ops(c)` | 操作总数 / `Dict{Symbol,Int}` 分类计数 |
| `qubits_used(c)` | 使用过的量子比特（升序） |
| `clbits_used(c)` | 使用过的经典位（首次出现序） |
| `dagger(c)` | 逆线路（逆序 + 逐操作求逆；要求全酉） |
| `validate(c)` | 合法性检查（越界、引用、测量长度等），通过返回自身 |
| `dag(c)` | 依赖 DAG（`nodes` / `dependencies`），`BlockOp` 为原子节点 |
| `measure_all!(c)` | 全部比特测量到同尺寸经典寄存器 |

## 6. 布局（Layout）

```julia
c = Circuit(3)
c.layout = Layout([5, 7, 9], nothing)   # initial: 线路比特 → 设备比特
```

布局随线路走（编译产物自描述），`initial` 为线路比特 → 设备比特映射，
`output` 为输出置换（测量位置）。

## 7. 显示

```julia
julia> c
Circuit(n=2, ops=2)
  1: H q[0]
  2: CX q[0], q[1]
```
