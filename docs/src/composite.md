# 复合结构：UserGate（定义层）与 BlockOp（定位层）

两者都是"子线路"的包装，但分工不同——**一个定义新门，一个圈定并命名一块已定位的区域**。

## 1. UserGate：定义一个新门

```julia
ug = UserGate(:mygate, [0 1; 1 0])     # 矩阵定义（糖：usergate(:mygate, m)）
ug(3)                                  # 像普通门一样调用定位

def = Circuit([H(1), CX(1, 2)])
bell = UserGate(:bell, 2, def)         # 子线路定义（延迟分解）
mat(bell)                              # 首次求矩阵时展开合成
```

属性：

- **必须全酉**；可被 `ctrl` / `inv` / `pow` 修饰、可参数化（继承 body 中的 `Param`）；
- 无定位——复用定义，哪里需要哪里调用；
- `mat` 语义：矩阵定义直接返回；子线路定义按 body 顺序嵌入合成（参数化时按
  `parameters(def)` 顺序代入）。

## 2. BlockOp：结构块（定位层）

```julia
blk = block(body; name=:round, repeat=3, at=[3, 4])
```

| 字段 | 含义 |
|---|---|
| `name` | 块名（可视化显示为单个命名框） |
| `body` | 子线路 |
| `n` | 重复次数（QEC 综合征轮次 / Trotter 步） |
| `mapping` | `at`：`mapping[i]` = body 局部比特 `i`（1-based）的全局位置；`nothing` 时 body 直接用全局比特 |

要点：

- **可含测量 / 屏障 / 经典控制**（不要求酉）——这是与 `UserGate` 的本质区别；
- 经典位作用域**全局共享**：body 直接引用父线路的 `CReg`；
- 全酉时 `mat(blk)` 可惰性合成（含映射与重复）；`inv(blk)` 合法；
- `dag(c)` 中 BlockOp 以 qubit 足迹作为**原子节点**；需要细粒度时先 `unroll!`。

## 3. 展开（unroll）

```julia
ops = unroll(blk)     # 纯函数：应用映射并重复 n 次 → Vector{Operation}
unroll!(c)            # 就地递归展开线路中所有 BlockOp（含 IfOp 分支内部）
```

- `mapping === nothing` 时操作原样复制；否则逐操作重映射比特
  （`GateOp` / `MeasOp` / `ReinitOp` / `BarrierOp` / `ChannelOp` / `IfOp` / 嵌套 `BlockOp`）；
- `UserGate` 属于定义层（门），**不**被 `unroll!` 展开。

## 4. 分工速查

| | `UserGate` | `BlockOp` |
|---|---|---|
| 层次 | 定义层（门） | 定位层（操作） |
| 酉性 | 必须全酉 | 不要求 |
| 定位 | 无（调用时定位） | 构造时绑定比特（`at`） |
| 可修饰（ctrl/inv/pow） | ✔ | 仅 `inv`（全酉时） |
| 参数化 | ✔（继承 body 的 `Param`） | ✗（先 `assign` 再包块） |
| 典型用途 | 定义可复用的新门 | 命名分组 / 优化区域 / 重复轮次 |
| 依赖图 | —（作为 Gate 参与） | 原子节点（按 qubit 足迹） |
