# OpenQASM 序列化

## 1. 入口

```julia
to_qasm(c; version=3)          # → String
write_qasm(path, c; version=3) # 写文件
read_qasm(path)                # 读文件（按 OPENQASM 头自动识别 2/3）
read_qasm(src::AbstractString) # 参数以 "OPENQASM" 开头时按源码字符串解析
```

## 2. OpenQASM 2

### 导出（qelib1 子集，含 Qiskit 扩展的 `rxx` / `rzz`）

支持：`id x y z h s sdg t tdg sx cx cy cz ch swap ccx cswap rx ry rz
u1（=PHASE）cu1（=CPHASE）rxx rzz rz（=VirtualZ）`、`measure`、`reset`、
`barrier`、单操作 `if (c==k) stmt;`。

限制：门修饰符（`inv/pow/ctrl`）、`ChannelOp`、`UserGate` 不可导出（报错提示改用 QASM3）。

### 导入

- 支持 `qreg` / `creg`、`measure`（`->` 语法）、`reset`、`barrier`、`if (c==k) stmt`；
- `gate` 自定义定义：递归展开（`barrier` 可用；测量/分支不允许出现在 body 内）；
- qelib1 名称映射：`u1→PHASE`、`u3/cu3/cu/crz/cry/u2` 由内部参数门承载、
  `cu1→CPHASE`、`rzz→RZZ`、`rxx→RXX`、`iswap→ISWAP`、`ms→MS`、`sdg→SDAG` 等；
- 参数表达式支持数字、`pi`、`+ - * / ^`、括号、`cos`/`sin`/`tan`/`exp`/`ln`/`sqrt`/`abs`。

## 3. OpenQASM 3（增长子集）

### 导出

- stdgates 子集 + 按需自动生成自定义门定义：
  `rzz rxx ryy iswap ms`（定义间依赖自动补齐，如 `iswap` 会带上 `rxx`/`ryy`/`rzz`）；
- 修饰符用 QASM3 原生语法：`inv @`、`pow(k) @`、`ctrl(n) @`、`negctrl(n) @`（可链式组合；
  混合极性控制不支持，报错）；
- `IfOp` 导出为 `if (…) { … } else { … }` 块；
- `measure` 用赋值语法 `c[j] = measure q[i];`；
- `VirtualZ → rz`、`PHASE → p`、`CPHASE → cp`。

### 导入

与 QASM2 共享统一解析器，额外支持：

- `qubit[n] name` / `bit[n] name` 声明（也兼容 `qreg`/`creg` 写法）；
- 修饰符链：`inv @ pow(0.5) @ ctrl(2) @ g(…) q[…]；`；
- `if (…) { … } else { … }`；
- 赋值式测量 `c[j] = measure q[i];`；
- `gate` 定义（同 QASM2 规则）。

不支持（v1 明确报错）：`input`/`output`/`const`/`defcal`/`for`/`while`/`switch`、
时序类型、子程序 `def`、噪声信道。

## 4. 寄存器与寻址

- 导出要求 `qregs` 尺寸之和恰为 `nqubits(c)`（寄存器按声明顺序线性切分全局比特）；
- 导入按声明顺序为寄存器分配全局比特区间；
- QASM 侧寄存器下标一律 **0-based**。

## 5. 参数

导出要求所有 `Param` 已绑定（未绑定报错）；`read_qasm` 产生的操作全部是具体数值参数。
