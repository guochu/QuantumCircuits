
abstract type Gate{N} <: QuantumOperation end


# interfaces for Quantum Gates

"""
	nqubits(x::Gate)
"""
nqubits(x::Gate{N}) where N = N

"""
	positions(x::Gate)
"""
positions(x::Gate) = x.pos


"""
	mat(x::Gate)
"""
mat(x::Gate) = error("mat not implemented for gate type $(typeof(x)).")

"""
	op(x::Gate)
"""
op(x::Gate) = reshape(mat(x), ntuple(i->2, 2*nqubits(x)))



"""
	ordered_positions(x::Gate)
"""
ordered_positions(x::Gate) = Tuple(sort([positions(x)...]))


"""
	ordered_mat(x::Gate)
"""
ordered_mat(x::Gate{N}) where N = reshape(ordered_op(x), 2^N, 2^N)

"""
	ordered_op(x::Gate)
"""
function ordered_op(x::Gate)
	is_ordered(x) && return op(x)
	ordered_pos, ordered_data = _get_norm_order(positions(x), op(x))
	return ordered_data
end 


change_positions(x::Gate, m::AbstractDict) = error("change_positions not implemented for gate type $(typeof(x)).")

Base.eltype(x::Gate) = eltype(mat(x))

function is_ordered(x::Gate)
	pos = positions(x)
	for i in 1:nqubits(x)-1
		(pos[i] < pos[i+1]) || return false
	end
	return true
end





function _get_norm_order(key::NTuple{N, Int}, p) where N
	seq = sortperm([key...])
	perm = (seq..., [s + N for s in seq]...)
	return key[seq], permute(p, perm)
end



