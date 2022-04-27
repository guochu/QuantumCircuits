

# predefined quantum channels

# see NielsenChuang
AmplitudeDamping(pos::Int; γ::Real) = QuantumMap(1, [[1 0; 0 sqrt(1-γ)], [0 sqrt(γ); 0 0]])
PhaseDamping(pos::Int; γ::Real) = QuantumMap(1, [[1 0; 0 sqrt(1-γ)], [0 0; 0 sqrt(γ)]])
