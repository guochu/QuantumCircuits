using Test
using QuantumCircuits
using QuantumCircuits: _embed, _compose_unitary, _matrix_pow, _U3,
                       InvGate, PowGate, CtrlGate
import QuantumCircuits: reset
using QuantumCircuits.Hamiltonian
using LinearAlgebra
using SparseArrays

include("common.jl")

@testset "QuantumCircuits" begin
    include("bits_params.jl")
    include("gates.jl")
    include("circuit.jl")
    include("classical.jl")
    include("composite_dag.jl")
    include("channels.jl")
    include("hamiltonian.jl")
    include("io_qasm.jl")
    include("docexamples.jl")
end
