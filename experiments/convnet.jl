using Flux, XConv, BSON
using Flux: onecold, logitcrossentropy, @epochs
using CUDA
using Parameters: @with_kw

cd(dirname(@__FILE__))

if CUDA.has_cuda()
    device = gpu
    CUDA.allowscalar(false)
    @info "Training on GPU"
else
    device = cpu
    @info "Training on CPU"
end

include("./datautils.jl")
include("./modelutils.jl")

@with_kw mutable struct Args
    name::String = "MNIST"
    batchsize::Int = 128
    η::Float64 = 3e-4
    epochs::Int = 50
    splitr_::Float64 = 0.1
    probe_size::Int = 8
    mode::String = "TrueGrad"
    savepath::String = "./$(name)_bench"
end

function accuracy(test_data, m)
    correct, total = 0, 0
    for (x, y) in test_data
        correct += sum(onecold(cpu(m(x)), 0:9) .== onecold(cpu(y), 0:9))
        total += size(y, 2)
    end
    test_accuracy = correct / total
    test_accuracy
end

function train(; kws...)
    # Initialize the hyperparameters
    args = Args(; kws...)

    # Initialize gradient mode
    XConv.initXConv(args.probe_size, args.mode)

    # Load the train, validation data 
    train_data, validation_data = get_train_data(args)
    test_data = get_test_data(args)

    @info("Constructing Model")	
    # Defining the loss and accuracy functions
    m = build_model(args.name) |> device
    loss(x, y) = logitcrossentropy(m(x), y)

    @info("Training $(args.name)")
    args.mode= "TrueGrad" ? @info("Mode: $(args.mode)") : @info("Mode: $(args.mode), probing vectors: $(args.probe_size)")
    lhist = []
    # Defining the optimizer
    opt = ADAM(args.η)
    ps = Flux.params(m)
    # Starting to train models
    for epoch in 1:args.epochs
        local l
        for (x, y) in train_data
            x, y = x |> device, y |> device

            gs = Flux.gradient(ps) do 
                l = loss(x, y)
                l
            end
            Flux.update!(opt, ps, gs)
            push!(lhist, l)
        end

        validation_loss = 0f0
        for (x, y) in val_data
            x, y = x |> device, y |> device
            validation_loss += loss(x, y)
        end
        validation_loss /= length(val_data)
        @info "Epoch $epoch validation loss = $(validation_loss)"
    end

    @show accuracy(test_data, m)

    BSON.@save joinpath(args.savepath, "$(args.name)_conv_$(args.mode)_$(args.batch_size)_$(args.probe_size).bson") params=cpu.(params(m)) acc lhist

end

train(;mode="TrueGrad")

# datasets = ["MNIST", "CIFAR10"]

# b_sizes = [2^i for i=5:10]
# ps_sizes = [2^i for i=1:6]

# for d in datasets
#     for b in b_sizes
#         train(;mode="TrueGrad", epochs=1, batch_size=b, name=d)
#         @time train(;mode="TrueGrad", batch_size=b, name=d)
#         for ps in ps_sizes
#             train(;mode="EVGrad", epochs=1, batch_size=b, probe_size=ps, name=d)
#             @time train(;mode="EVGrad", batch_size=b, probe_size=ps, name=d)
#         end
#     end
# end
