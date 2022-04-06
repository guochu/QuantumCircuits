
struct QubitsTerm <: QuantumOperation
	positions::Vector{Int}
	op::Vector{<:AbstractMatrix}
	coeff::Number
end

positions(x::QubitsTerm) = x.positions
oplist(x::QubitsTerm) = x.op
coeff(x::QubitsTerm) = x.coeff


function QubitsTerm(pos::Vector{Int}, m::Vector, v::Number)
	(length(pos) == length(m)) || error("number of sites mismatch with number of ops.")
	pos, m = _get_normal_order(pos, m)
	return QubitsTerm(pos, m, v)
end 
QubitsTerm(pos::Tuple, m::Vector, v::Number) = QubitsTerm([pos...], m, v)

function QubitsTerm(x::AbstractDict{Int}; coeff::Number=1.)
	sites, ops = dict_to_site_ops(x)
	return QubitsTerm(sites, ops, coeff)
end

QubitsTerm(x::Pair{Int, <:Union{AbstractString, AbstractMatrix}}...; coeff::Number=1.) = QubitsTerm(
	Dict(x...), coeff=coeff)



function _get_normal_order(key::Vector{Int}, op)
	seq = sortperm(key)
	return key[seq], op[seq]
end

function dict_to_site_ops(opstr::AbstractDict)
	sites = []
	ops = []
	for (k, v) in opstr
	    push!(sites, k)
	    push!(ops, v)
	end
	return [sites...], [ops...]
end

