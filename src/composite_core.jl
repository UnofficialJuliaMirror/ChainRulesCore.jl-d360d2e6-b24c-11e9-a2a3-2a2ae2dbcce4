"""
    backing(x)

Returns a version of `x` that is of the type the backing of a `Composite` is.
i.e. as a `NamedTuple` or `Tuple`.

This is kind of the opposite of `construct` for structs.
"""
backing(x::Tuple) = x
backing(x::NamedTuple) = x
backing(x::Composite) = getfield(x, :backing)

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
    construct(::Type{T}, fields::[NamedTuple|Tuple])

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
        vals = (:(getproperty(fields, $(QuoteNode(fname)))) for fname in fieldnames(T))
        return :(T($(vals...)))
    else
        return T((getproperty(fields, fname) for fname in fieldnames(T))...)
    end
end

construct(::Type{T}, fields::T) where T = fields  # for Tuple

"""
    directly_construct(::Type{T}, fields::NamedTuple{L})

Directly constructs an object of type `T`, with the given fields.
**Bypassing all inner constructors.**
"""
function directly_construct(::Type{T}, fields::NamedTuple{L}) where {T, L}
    #TODO based on
    #https://github.com/JuliaIO/BSON.jl/blob/a58c88a14e07d0beed8f56edb79e5cbea7078e00/src/extensions.jl#L107
    # We need to use this rather than `construct` so that closures work.
    error("no implemented")
end


########################################################################################
elementwise_add(a::Tuple, b::Tuple) = map(+, a, b)

function elementwise_add(a::NamedTuple{an}, b::NamedTuple{bn}) where {an, bn}
    # Base on the `merge(:;NamedTuple, ::NamedTuple)` code from Base.
    # https://github.com/JuliaLang/julia/blob/592748adb25301a45bd6edef3ac0a93eed069852/base/namedtuple.jl#L220-L231
    if @generated
        names = Base.merge_names(an, bn)
        types = Base.merge_types(names, a, b)

        vals = map(names) do field
            a_field = :(getproperty(a, $(QuoteNode(field))))
            b_field = :(getproperty(b, $(QuoteNode(field))))
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
            if Base.sym_in(field, an)
                a_field = getproperty(a, field)
                if Base.sym_in(field, bn)
                    # in both
                    b_field = getproperty(b, field)
                    a_field + b_field
                else
                    # only in `an`
                    a_field
                end
            else # must be in `b` only
                b_field = getproperty(b, field)
                b_field
            end
        end
        return NamedTuple{names,types}(vals)
    end
end

elementwise_add((y=25,),  (x=2, y=4))
