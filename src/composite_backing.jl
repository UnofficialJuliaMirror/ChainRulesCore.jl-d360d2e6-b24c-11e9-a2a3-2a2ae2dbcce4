"""
    backing(x)

Returns a version of `x` that is of the type the backing of a `Composite` is.
i.e. as a `NamedTuple` or `Tuple`.

This is kind of the opposite of `construct` for structs.
"""
backing(x::Tuple) = x
backing(x::NamedTuple) = x
backing(x::Composite) = x.backing

function backing(x::T)::NamedTuple where T
    nfields = fieldcount(T)
    names = ntuple(ii->fieldname(T, ii), nfields)
    types = ntuple(ii->fieldtype(T, ii), nfields)

    if @generated
        vals = ntuple(ii->:(getfield(x, $ii)), nfields)
        return :(NamedTuple{$names, Tuple{$(types...)}}($vals))
    else
        vals = ntuple(ii->getfield(x, ii), nfields)
        return NamedTuple{names, Tuple{types...}}(vals)
    end
end



"""
    construct(::Type{T}, fields::NamedTuple{L})

Constructs an object of type `T`, with the given fields.
Fields must be correct in name and type, and `T` must have a default constructor
"""
function construct(::Type{T}, fields::NamedTuple{L}) where {T, L}
    # Tested and varified that that this avoids a ton of allocations
    if length(L) !== fieldcount(T)
        # if length is equal but names differ then we will catch that below anyway.
        throw(ArgumentError("Unmatched fields. Type: $(fieldnames(T)),  namedtuple: $L"))
    end

    if @generated
        if !isempty(setdiff(L, fieldnames())
            ArgumentError("Extra fields in namedtuple (has$L), not ")
        end
        vals = (:(getproperty(fields, $(QuoteNode(fname)))) for fname in fieldnames(T))
        return :(T($(vals...)))
    else
        return T((getproperty(fields, fname) for fname in fieldnames(T))...)
    end
end



"""
    directly_construct(::Type{T}, fields::NamedTuple{L})

Directly constructs an object of type `T`, with the given fields.
**Bypassing all inner constructors.**
"""
function directly_construct(::Type{T}, fields::NamedTuple{L}) where {T, L}
    #TODO based on
    #https://github.com/JuliaIO/BSON.jl/blob/a58c88a14e07d0beed8f56edb79e5cbea7078e00/src/extensions.jl#L107
    error("no implemented")
end


########################################################################################

function elementwise_add(a::NamedTuple{an}, b::NamedTuple{bn})
    # Base on the `merge(:;NamedTuple, ::NamedTuple)` code from Base.
    # https://github.com/JuliaLang/julia/blob/592748adb25301a45bd6edef3ac0a93eed069852/base/namedtuple.jl#L220-L231
    if @generated
        names = Base.merge_names(an, bn)
        types = Base.merge_types(names, a, b)

        vals = map(names) do field
            a_field = :(getproperty(:a, $(QuoteNode(field))))
            b_field = :(getproperty(:b, $(QuoteNode(field))))
            val_expr = if Base.sym_in(field, an)
                if Base.sym_in(field, bn)
                    # in both
                    :($a_field + $b_field)
                else
                    # only in `an`
                    a_field
                end
            else # must be in `b` only
                b_field
            end
        end
        return :(NamedTuple{$names, $types}(($(vals...),)))
    else
        names = Base.merge_names(an, bn)
        types = Base.merge_types(names, typeof(a), typeof(b))
        vals = map(names) do field
            val_expr = if Base.sym_in(field, an)
                a_field = getproperty(a, field)
                if Base.sym_in(field, bn)
                    # in both
                    b_field = getproperty(a, field)
                    :($a_field + $b_field)
                else
                    # only in `an`
                    a_field
                end
            else # must be in `b` only
                b_field = getproperty(a, field)
                b_field
            end
        end
        NamedTuple{names,types}(map(n->getfield(sym_in(n, bn) ? b : a, n), names))
    end
end

function Base.:+(a::Primal, b::Composite{Primal, <:NamedTuple})::Primal where {Primal}

    backing =  #TODO: factor out the +(::Composite,::Composite) above and call it here.

    return _construct(Primal, backing)  # should use _directly_construct
end


# this should not need to be generated, # TODO test that
function Base.:+(a::Composite{Primal, <:Tuple}, b::Composite{Primal, <:Tuple}) where Primal
    # TODO: should we even allow it on different lengths?
    short, long =  length(a) < length(b) ? (a.backing, b.backing) : (b.backing, a.backing)
    backing = ntuple(length(long)) do ii
        long_val = getfield(long, ii)
        if ii <= length(short)
            short_val = getfield(short, ii)
            return short_val + long_val
        else
            return long_val
        end
    end

    return Composite{Primal, typeof(backing)}(backing)
end


# this should not need to be generated, # TODO test that
function Base.:+(a::Primal, b::Composite{Primal, <:Tuple})::Primal where {Primal}
    @assert Primal <: Tuple  # only Composites for Tuples have Tuple backing

    # TODO: should we even allow it on different lengths?
    short, long =  length(a) < length(b) ? (a.backing, b.backing) : (b.backing, a.backing)
    return ntuple(length(long)) do ii
        long_val = getfield(long, ii)
        if ii <= length(short)
            short_val = getfield(short, ii)
            return short_val + long_val
        else
            return long_val
        end
    end
end

Base.:+(b::Composite{Primal}, a::Primal) where Primal =  a + b
