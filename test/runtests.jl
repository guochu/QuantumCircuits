using Test
using QuantumCircuits
using QuantumCircuits: _embed, _compose_unitary, _matrix_pow, _U3,
                       InvGate, PowGate, CtrlGate
using QuantumCircuits.Hamiltonian
using LinearAlgebra

include("common.jl")

@testset "QuantumCircuits" begin
    include("bits_params.jl")
    include("gates.jl")
    include("draw.jl")
    include("circuit.jl")
    include("variational.jl")
    include("classical.jl")
    include("composite_dag.jl")
    include("channels.jl")
    include("hamiltonian.jl")
    include("interface.jl")
    include("io_qasm.jl")
    include("luxor_ext.jl")
    include("docexamples.jl")
end
