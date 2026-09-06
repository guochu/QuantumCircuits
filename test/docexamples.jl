@testset "doc examples" begin
    # §五 示例 2：变分线路（0-based 索引）
    c = Circuit(4)
    φ = params(:φ, 3)
    for q in 0:3
        push!(c, RX(:θ, q))
    end
    for q in 0:2
        push!(c, RZZ(φ[q+1], q, q + 1))
    end
    @test parameters(c) == [Param(:θ), φ[1], φ[2], φ[3]]
    bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))
    @test parameters(bound) == Param[]
    @test validate(bound) === bound

    # §五 示例 5：含噪线路（0-based 索引）
    noisy = Circuit(2)
    push!(noisy, H(0)); push!(noisy, CX(0, 1))
    push!(noisy, Depolarizing([0, 1], 1e-3))
    push!(noisy, PauliError(1, (0.001, 0.001, 0.002)))
    @test num_ops(noisy) == 4
    @test validate(noisy) === noisy

    # §五 示例 1：Bell 态 + 测量（0-based 索引）
    bell = Circuit(2)
    push!(bell, H(0))
    push!(bell, CX(0, 1))
    push!(bell, measure([0, 1], bell.cregs[1][1:2]))
    @test to_qasm(bell) isa String
    @test validate(bell) === bell
end
