# =============================================================================
# variational.jl — 参数化量子线路示例（hardware efficient 变分 ansatz）
#
# 作为「先建线路、后绑参」工作流的示例：
#   * `θs` 缺省时线路携带符号参数 `θ[1]…θ[n]`（`params(:θ, n)` 向量），
#     `parameters(c)` 收集后 `assign` 绑定数值；
#   * 也可直接传 `Vector{<:Real}`，一步得到已绑定数值的线路。
# 纠缠层为一维最近邻 `CX` 梳：奇数层正序 `1→L-1`、偶数层倒序，交替铺满。
# =============================================================================

"""
    variational_circuit_1d(L::Int, depth::Int; θs = params(:θ, 3L*(depth+1))) -> Circuit

一维最近邻变分线路（hardware efficient ansatz）：`depth + 1` 个旋转层，
每层每比特 `RZ-RY-RZ`；相邻旋转层之间铺一维最近邻 `CX` 梳（奇数层
`1→L-1` 正序、偶数层倒序交替），共 `depth` 个纠缠层。

参数个数 `3L(depth+1)`。`θs` 缺省时用符号参数向量 `params(:θ, n)`；
也可传 `Vector{<:Real}`（个数不符抛 `ArgumentError`）。

# 示例

```julia
c = variational_circuit_1d(2, 1)             # 符号参数 θ[1]…θ[12]
bound = assign(c, Dict(params(:θ, 12) => collect(0.1:0.1:1.2)))

c = variational_circuit_1d(2, 1; θs = rand(12) .* 2π)   # 直接数值
```
"""
function variational_circuit_1d(L::Int, depth::Int;
                                θs = params(:θ, 3 * L * (depth + 1)))
    n = 3 * L * (depth + 1)
    length(θs) == n ||
        throw(ArgumentError("wrong number of parameters: expected $n, got $(length(θs))"))
    circuit = Circuit(L)
    ncount = 1
    for i in 1:L
        push!(circuit, RZ(θs[ncount], i)); ncount += 1
        push!(circuit, RY(θs[ncount], i)); ncount += 1
        push!(circuit, RZ(θs[ncount], i)); ncount += 1
    end
    for d in 1:depth
        if isodd(d)
            for j in 1:(L-1)
                push!(circuit, CX(j, j + 1))
            end
        else
            for j in (L-1):-1:1
                push!(circuit, CX(j, j + 1))
            end
        end
        for j in 1:L
            push!(circuit, RZ(θs[ncount], j)); ncount += 1
            push!(circuit, RY(θs[ncount], j)); ncount += 1
            push!(circuit, RZ(θs[ncount], j)); ncount += 1
        end
    end
    return circuit
end

"""
    real_variational_circuit_1d(L::Int, depth::Int; θs = params(:θ, L*(depth+1))) -> Circuit

实参数版一维变分线路：旋转层仅含 `RY`（参数个数 `L(depth+1)`），
纠缠层与 [`variational_circuit_1d`](@ref) 相同。

参数约定同上：`θs` 缺省为符号参数向量，也可传 `Vector{<:Real}`。
"""
function real_variational_circuit_1d(L::Int, depth::Int;
                                     θs = params(:θ, L * (depth + 1)))
    n = L * (depth + 1)
    length(θs) == n ||
        throw(ArgumentError("wrong number of parameters: expected $n, got $(length(θs))"))
    circuit = Circuit(L)
    ncount = 1
    for i in 1:L
        push!(circuit, RY(θs[ncount], i)); ncount += 1
    end
    for d in 1:depth
        if isodd(d)
            for j in 1:(L-1)
                push!(circuit, CX(j, j + 1))
            end
        else
            for j in (L-1):-1:1
                push!(circuit, CX(j, j + 1))
            end
        end
        for j in 1:L
            push!(circuit, RY(θs[ncount], j)); ncount += 1
        end
    end
    return circuit
end
