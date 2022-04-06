const QOP_DATA_TYPE = Dict{Tuple{Int, Vararg{Int, N} where N}, Vector{Tuple{Vector{AbstractMatrix}, Number}}}
const QOP_DATA_VALUE_TYPE = Vector{Tuple{Vector{AbstractMatrix}, Number}}

struct QubitsOperator <: QuantumOperation
	data::QOP_DATA_TYPE
end

QubitsOperator() = QubitsOperator(QOP_DATA_TYPE())

Base.copy(x::QubitsOperator) = QubitsOperator(copy(x.data))

function QubitsOperator(x::QubitsTerm, v::QubitsTerm...)
	r = QubitsOperator()
	add!(r, x)
	for item in v
	    add!(r, item)
	end
	return r
end 

function absorb_one_bodies(ham::QubitsOperator)
	r = QubitsOperator()
	# L = get_largest_pos(ham)
	iden = I₂
	for (key, value) in ham.data
		if length(key)==1
			i = key[1]
			for (k2, v2) in ham.data
			    if ((length(k2) > 1) && (i in k2))
			    	for item in value
			    		ops = [ (kk == i) ? oplist(item)[1] : iden for kk in k2]
			    		add!(r, QubitsTerm([k2...], ops, coeff(item)))
			        end
			        break
			    end
			end
		else
			for item in value
			    add!(r, QubitsTerm([key...], item))
			end
		end
	end
	return r
end

reduce_terms(h::QubitsOperator) = absorb_one_bodies(h)

function add!(x::QubitsOperator, m::QubitsTerm)
	pos = Tuple(positions(m))
	v = get!(x.data, pos, QOP_DATA_VALUE_TYPE())
	push!(v, convert(Tuple{Vector{AbstractMatrix}, Number}, (oplist(m), coeff(m))) )
	return x
end

function Base.:+(x::QubitsTerm, y::QubitsTerm)
	r = QubitsOperator()
	add!(r, x)
	add!(r, y)
	return r
end
function Base.:+(x::QubitsTerm, y::QubitsOperator)
	r = copy(y)
	add!(r, x)
	return r
end
Base.:+(x::QubitsOperator, y::QubitsTerm) = y + x
function Base.:+(x::QubitsOperator, y::QubitsOperator)
	r = copy(x)
	for (k, v) in y.data
		kk = [k...]
		for item in v
		    add!(r, QubitsTerm(kk, item))
		end
	end
	return r
end


function matrix(L::Int, x::QubitsOperator)
	is_constant(x) || error("input must be a constant operator.")
	h = nothing
	for (k, v) in data(x)
		for item in v
			tmp = _generateprodham(L, sites_ops_to_dict(k, oplist(item))) * coeff(item)
			if h === nothing
			    h = tmp
			else
				h += tmp
			end
		end
	end
	return h
end

matrix(x::QubitsOperator) = matrix(get_largest_pos(x), x)
matrix(L::Int, x::QubitsTerm) = _generateprodham(L, sites_ops_to_dict(positions(x), oplist(x))) * coeff(x)


change_positions(x::QubitsOperator, m::AbstractDict) = QubitsOperator(QOP_DATA_TYPE(_index_map(k, m)=>v for (k, v) in x.data)) 


# *(x::QubitsOperator, y::Number) = QubitsOperator(
# 	Dict{Tuple{Int, Vararg{Int, N} where N}, BareBond{BareTerm{AbstractMatrix}}}(k=>(v*y) for (k, v) in data(x)))
# *(y::Number, x::QubitsOperator) = x * y

# function Base.getindex(h::QubitsOperator, v::Vector{Int})
# 	index_map = Dict(vj=>j for (j, vj) in enumerate(v))
# 	data_new = typeof(data(h))()
# 	for (k, bond) in data(h)
# 	    if issubset(k, v)
# 	    	new_k = Tuple(index_map[item] for item in k)
# 	    	seq = sortperm([new_k...])
# 	    	new_k = new_k[seq]
# 	    	data_new[new_k] = permute(bond, seq)
# 	    end
# 	end
# 	return QubitsOperator(data_new)
# end

function _generateprodham(L::Int, opstr::Dict{Int, <:AbstractMatrix}) 
	(max(keys(opstr)...) <= L) || error("op str out of bounds")
	i = 1
	ops = []
	for i in 1:L
	    v = get(opstr, i, nothing)
	    if v === nothing
	        v = I₂
	    else
	    	(size(v, 1)==2 && size(v, 2)==2) || error("dimension mismatch with dim.")
	    end
	    push!(ops, sparse(v))
	end
	return _kron_ops(reverse(ops))
end

_index_map(x::NTuple{N, Int}, mm::AbstractDict) where N = ntuple(j -> mm[x[j]], N)


# _get_mat(x::BareTerm{AbstractMatrix}) = _kron_ops(reverse(oplist(x))) * value(coeff(x))
# _get_mat(x::QubitsTerm) = _kron_ops(reverse(oplist(x))) * value(coeff(x))

# function _get_mat(n::Int, x::BareBond{BareTerm{AbstractMatrix}})
#     isempty(x) && error("bond is empty.")
#     is_constant(x) || error("bond must be constant.")
#     m = zeros(scalar_type(x), 2^n, 2^n)
#     for item in x
#         tmp = _kron_ops(reverse(oplist(item)))
#         alpha = value(coeff(item))
#         @. m += alpha * tmp
#     end
#     return m
# end





sites_ops_to_dict(sites, ops)= Dict(sites[j]=>ops[j] for j=1:length(sites))
