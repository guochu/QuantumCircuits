# 子模块 Interface（模拟后端契约）

```julia
using QuantumCircuits.Interface
```

IR 本身无执行语义；`Interface` 子模块只声明"可执行线路的引擎"
必须满足的契约。**算法包只依赖本契约与 IR，后端实例由调用方注入。**

## 契约组成

| 组成 | 说明 |
|---|---|
| `Backend` | 后端标记抽象类型（算法包唯一需要认识的类型） |
| `simulate(c, backend; shots=0, seed=nothing)` | **唯一必须实现的方法** |
| `SimResult` | 统一返回：`counts`（弱模拟）/ `state`（强模拟）/ `metadata` |
| `expectation(h, c, backend; params)` | 可选：`PauliSum` 期望值直算（backend 置尾） |
| `supports` / `max_qubits` | 能力查询（`:statevector` / `:mid_measure` / `:noise` / `:adjoint`） |
| `counts_key` | 计数键格式约定（小端序、`x` 填充、多寄存器）——跨后端可比的前提 |
| `set_default_backend!` / `default_backend` | 会话级默认后端（便利层） |

## 后端接入示例

```julia
using QuantumCircuits
using QuantumCircuits.Interface: Backend, simulate

struct MyBackend <: Backend; end

function simulate(c::Circuit, ::MyBackend; shots::Int = 0,
                  seed::Union{Nothing,Integer} = nothing)
    # … 执行线路，返回 SimResult(counts, state; metadata)
end
```

## 计数键约定

`counts_key` 生成的键形如 `"name:bits"`：`bits` 串**右端是寄存器
index 1（最低有效位）**（与全栈小端序约定一致）；未测量的位填 `'x'`；
多寄存器按声明顺序以逗号连接（如 `"c:110,anc:01"`）。
所有后端必须用同一约定生成键，跨后端结果才可比。

## 使用示例

```julia
c = Circuit(2)
push!(c, H(1)); push!(c, CX(1, 2)); measure_all!(c)

r = simulate(c, MyBackend(); shots = 1024)
r.counts                                  # Dict{String,Int}

set_default_backend!(MyBackend())
simulate(c; shots = 1024)                 # 免传后端
```
