@testset "doc examples" begin
    # §五 示例 2：变分线路（0-based 索引）
    c = Circuit(4)
    φ = params(:φ, 3)
    for q in 1:4
        push!(c, RX(:θ, q))
    end
    for q in 1:3
        push!(c, RZZ(φ[q], q, q + 1))
    end
    @test parameters(c) == [Param(:θ), φ[1], φ[2], φ[3]]
    bound = assign(c, Dict(:θ => 0.3, φ => [π/4, 0.5, 0.2]))
    @test parameters(bound) == Param[]
    @test validate(bound) === bound

    # §五 示例 5：含噪线路（0-based 索引）
    noisy = Circuit(2)
    push!(noisy, H(1)); push!(noisy, CX(1, 2))
    push!(noisy, Depolarizing([1, 2], 1e-3))
    push!(noisy, PauliError(2, (0.001, 0.001, 0.002)))
    @test num_ops(noisy) == 4
    @test validate(noisy) === noisy

    # §五 示例 1：Bell 态 + 测量（0-based 索引）
    bell = Circuit(2)
    push!(bell, H(1))
    push!(bell, CX(1, 2))
    push!(bell, measure([1, 2], bell.cregs[1][1:2]))
    @test to_qasm(bell) isa String
    @test validate(bell) === bell
end
