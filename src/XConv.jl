module XConv

# Dependencies
using LinearAlgebra
using CUDA
using NNlib
using ChainRulesCore

export grad_ev, initXConv

# Setup valuesa
const DEFAULT = "TrueGrad"
const EV = "EVGrad"
const _params = Dict(:p_size => 2^4, :mode => DEFAULT)

# Probing
include("gemm.jl")
include("probe.jl")

# EV setup function
function initXConv(probe_size::Integer, mode::String)
    _params[:mode] = mode
    _params[:p_size] = probe_size
end

# Helper functions for rrule
grad_ev_interface(x, Δ, cdims, kw...) = grad_ev(x, Δ, _params[:p_size], weightsize(cdims))
weightsize(::DenseConvDims{N,K,C_in,C_out,S,P,D,F}) where {N,K,C_in,C_out,S,P,D,F} = K[1]
∇conv_filter_map = Dict(EV => grad_ev_interface, DEFAULT => NNlib.∇conv_filter_im2col)

# Little wrapper to have our own conv
for N=3:5
    for AT in [Array, CuArray]
        @eval begin
            function NNlib.∇conv_filter(x::$(AT){xT, $N}, dy::$(AT){wT, $N},
                                        cdims::ConvDims; kw...) where {xT, wT}
                return ∇conv_filter_map[_params[:mode]](x, dy, cdims; kw...)
            end
        end
        @eval begin
            function NNlib.∇conv_data(Δ::$(AT){xT, $N}, w::$(AT){xT, $N}, cdims::ConvDims; kw...) where {xT, wT}
                return @thunk(conv_data_im2col(Δ, w, cdims; kw...))
            end
        end
    end
end

ChainRulesCore.Thunk(T::ChainRulesCore.Thunk) = T

end