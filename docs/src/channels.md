# 噪声信道（Channels）

设计立场（Stim 先例）：**噪声即指令**。含噪实验由线路自描述（`ChannelOp`），
而不是在模拟器层外挂噪声模型。

## 1. 信道类型

所有信道实现一个接口：`kraus(ch)` 返回 Kraus 算子集（`Vector{Matrix{ComplexF64}}`），
构造时校验完全正迹（TP）与概率归一。

| 类型 | 说明 |
|---|---|
| `KrausChannel(ops)` | 通用 Kraus 信道（校验 Σ K†K = I） |
| `PauliChannel(paulis, probs)` | Pauli 串 + 概率，如 `PauliChannel([[:I],[:X],[:Y],[:Z]], [1-px-py-pz, px, py, pz])` |
| `UnitaryChannel(ops, probs)` | 酉混合（校验各算子酉性） |

## 2. 噪声指令（定位）

信道包装进 `ChannelOp` 后进线路。快捷构造：

```julia
PauliError(q, (px, py, pz))       # 单比特 Pauli 误差（QEC 核心）
Depolarizing(qubits, p)           # 以概率 p 施加均匀随机非恒 Pauli（比特数不限）
AmplitudeDamping(q, γ)            # 振幅阻尼
PhaseDamping(q, γ)                # 相位阻尼
KrausOp(ch, qubits)               # 任意信道定位

push!(c, Depolarizing([1, 2], 1e-3))
```

## 3. 属性

```julia
op = PauliError(2, (0.001, 0.001, 0.002))
op isa ChannelOp        # true
qubits(op)              # [1]
kraus(op)               # Kraus 算子集
is_unitary(op)          # false
```

## 4. 限制

- 噪声指令**不可序列化**到 OpenQASM（v1 报错提示）；
- 无执行语义：`kraus` 只给出算子集，如何作用于态由模拟器后端决定。
