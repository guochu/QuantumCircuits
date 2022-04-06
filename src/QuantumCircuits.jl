module QuantumCircuits

using SparseArrays

# gates
export nqubits, positions, mat, ordered_positions, ordered_mat, change_positions
export parameters, nparameters, active_parameters, activate_parameter!, activate_parameters!, deactivate_parameter!, deactivate_parameters!, reset_parameters!
export Gate, ParametricGate, QuantumGate, AdjointQuantumGate, gate, XGate, YGate, ZGate, SGate, HGate, TGate, sqrtXGate, sqrtYGate
export SWAPGate, iSWAPGate, CZGate, CNOTGate
export TOFFOLIGate, FREDKINGate

# parametric gates
export RxGate, RyGate, RzGate, PHASEGate
export CRxGate, CRyGate, CRzGate, CPHASEGate, FSIMGate
export CCPHASEGate


# circuit 
export QMeasure, QSelect, QCircuit

# hamiltonian
export QubitsTerm, oplist, coeff, QubitsOperator, matrix

abstract type QuantumOperation end

# auxiliary
include("auxiliary/tensorops.jl")


# elementary gate matrices
include("elemops.jl")

using QuantumCircuits.Gates


# gate operations
include("gates/gates.jl")
include("gates/generic.jl")
include("gates/parametric_gates.jl")
include("gates/onebody.jl")
include("gates/twobody.jl")
include("gates/threebody.jl")
include("gates/gatediff.jl")

# circuit
include("circuit.jl")

# qubit hamiltonian
include("qubitsham/qterm.jl")
include("qubitsham/qoperator.jl")

end