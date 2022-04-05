
abstract type ParametricGate{N} <: Gate{N} end


parameters(x::Gate) = nothing
active_parameters(x::Gate) = nothing

parameters(x::ParametricGate) = x.paras
parameters(x::AdjointQuantumGate) = parameters(x.parent)
is_parameters(x::ParametricGate) = x.isparas
active_parameters(x::ParametricGate) = x.paras[x.isparas]
active_parameters(x::AdjointQuantumGate) = active_parameters(x.parent)



activate_parameter!(x::Gate, j::Int) = x
activate_parameters!(x::Gate) = x
deactivate_parameter!(x::Gate, j::Int) = x
deactivate_parameters!(x::Gate) = x

function activate_parameter!(x::ParametricGate, j::Int)
	x.isparas[j] = true
	return x
end
function activate_parameters!(x::ParametricGate)
	x.isparas .= true
	return x
end
function deactivate_parameter!(x::ParametricGate, j::Int)
	x.isparas[j] = false
	return x
end
function deactivate_parameters!(x::ParametricGate)
	x.isparas .= false
	return x
end

function activate_parameter!(x::AdjointQuantumGate, j::Int)
	activate_parameter!(x.parent, j)
	return x
end
function activate_parameters!(x::AdjointQuantumGate)
	activate_parameters!(x.parent)
	return x
end
function deactivate_parameter!(x::AdjointQuantumGate, j::Int)
	deactivate_parameter!(x.parent, j)
	return x
end
function deactivate_parameters!(x::AdjointQuantumGate)
	deactivate_parameters!(x.parent)
	return x
end

differentiate(x::Gate) = nothing

"""
	differentiate(x::ParametricGate)
	return a list of gates, with the same number as the active parameters
"""
differentiate(x::ParametricGate) = error("differentiate not implemented for parametric gate $(typeof(x)).") 

