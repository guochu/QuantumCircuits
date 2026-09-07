@testset "channels" begin
    # PauliError
    op = PauliError(2, (0.001, 0.001, 0.002))
    @test op isa ChannelOp
    ks = kraus(op)
    @test length(ks) == 4
    tp = sum(k' * k for k in ks)
    @test approxeq(tp, I2; tol=1e-8)
    # Depolarizing（两比特）
    d = Depolarizing([1, 2], 0.01)
    ks = kraus(d)
    @test length(ks) == 16
    tp = sum(k' * k for k in ks)
    @test approxeq(tp, Matrix{ComplexF64}(I, 4, 4); tol=1e-6)
    # AmplitudeDamping
    ks = kraus(AmplitudeDamping(1, 0.3))
    @test approxeq(sum(k' * k for k in ks), I2; tol=1e-8)
    @test ks[2] ≈ [0 sqrt(0.3); 0 0]
    # PhaseDamping
    ks = kraus(PhaseDamping(1, 0.3))
    @test approxeq(sum(k' * k for k in ks), I2; tol=1e-8)
    # 概率和不为 1 报错
    @test_throws ArgumentError PauliChannel([[:I], [:X]], [0.5, 0.6])
    # 信道进线路
    c = Circuit(2)
    push!(c, H(1))
    push!(c, Depolarizing(1, 0.01))
    @test count_ops(c) == Dict(:H => 1, :channel => 1)
end
