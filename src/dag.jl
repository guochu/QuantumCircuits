# =============================================================================
# dag.jl — 依赖 DAG（编译器原料）
#
# 节点为 Operation（拓扑序 = 线路顺序）；BlockOp 以 qubit 足迹作为原子节点，
# 需要细粒度依赖时先 flatten!。
# =============================================================================

"""线路依赖 DAG：`nodes(dag)` 拓扑序节点；`dependencies(dag, i)` 前驱索引。"""
struct CircuitDAG
    ops::Vector{Operation}
    deps::Vector{Vector{Int}}
end

"拓扑序节点。"
nodes(dag::CircuitDAG) = dag.ops

"第 i 个节点的前驱节点索引。"
dependencies(dag::CircuitDAG, i::Integer) = dag.deps[i]

Base.length(dag::CircuitDAG) = length(dag.ops)

"由线路构建依赖 DAG。"
function dag(c::Circuit)
    last_q = Dict{Int,Int}()
    last_c = Dict{ClbitRef,Int}()
    ops = copy(c.ops)
    deps = Vector{Vector{Int}}(undef, length(ops))
    for (i, op) in enumerate(ops)
        dep = Set{Int}()
        for q in qubits(op)
            haskey(last_q, q) && push!(dep, last_q[q])
        end
        for cb in clbits(op)
            haskey(last_c, cb) && push!(dep, last_c[cb])
        end
        deps[i] = sort!(collect(dep))
        for q in qubits(op)
            last_q[q] = i
        end
        for cb in clbits(op)
            last_c[cb] = i
        end
    end
    return CircuitDAG(ops, deps)
end
