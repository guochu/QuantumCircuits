@testset "gate library" begin
    @test nqubits(H) == 1
    @test num_params(RX) == 1
    @test nqubits(MS) == 2
    @test num_params(MS) == 2
    @test nqubits(CCX) == 3
    # 门库酉性
    for g in (ID, X, Y, Z, H, S, SDAG, T, TDAG, SX, CX, CY, CZ, CH, SWAP, ISWAP, CCX, CSWAP)
        @test approxeq(mat(g)' * mat(g), Matrix{ComplexF64}(I, 1 << nqubits(g), 1 << nqubits(g)); tol=1e-8)
    end
    # 元素类型参数化：实数门保持实矩阵，复数门为复矩阵
    @test mat(X) isa Matrix{Float64}
    @test mat(H) isa Matrix{Float64}
    @test mat(CX) isa Matrix{Float64}
    @test mat(Y) isa Matrix{ComplexF64}
    @test mat(S) isa Matrix{ComplexF64}
    # 整数输入自动提升为 Float64
    @test ConstGate(:intgate, [1 0; 0 -1]).matrix isa Matrix{Float64}
    # 调用即定位
    @test H(1) == GateOp(H, [1], [])
    @test CX(1, 2) == GateOp(CX, [1, 2], [])
    op = RX(π/2, 3)
    @test op.qubits == [3]
    @test op.params == [Float64(π/2)]
    @test RX(:θ, 3).params == [Param(:θ)]
    @test RX(Param(:θ), 3).params == [Param(:θ)]
    # CX 矩阵（Qiskit 约定：控制位在前 = 矩阵最高位）
    @test mat(CX) == [1 0 0 0; 0 1 0 0; 0 0 0 1; 0 0 1 0]
    # RZZ 与 MS 一致性：MS(θ, 0) == RXX(θ)
    @test approxeq(mat(MS, π/4, 0.0), mat(RXX, π/4))
    # 参数个数不匹配
    @test_throws ArgumentError mat(RX, [0.1, 0.2])
    # 非酉矩阵构造 ConstGate 报错
    @test_throws ArgumentError ConstGate(:bad, [1 0; 0 2])
end

@testset "modifiers" begin
    # pow(H, 2) = I
    @test approxeq(mat(pow(H, 2)), I2)
    # inv(RX(θ)) 与 RX(-θ)
    @test approxeq(mat(inv(RX(0.3, 1))), mat(RX(-0.3, 1)))
    # ctrl(H(1), 2)：控制位前置，矩阵为块对角 [I ⊕ H]（即 CH）
    op = ctrl(H(1), 2)
    @test op.qubits == [2, 1]
    @test op.gate isa CtrlGate
    ch = zeros(ComplexF64, 4, 4)
    ch[1:2, 1:2] .= I2
    ch[3:4, 3:4] .= mat(H)
    @test approxeq(mat(op), ch)
    # negctrl：双负控 H，仅控制位均为 0 的块（矩阵最低块）触发 H
    m = mat(negctrl(H(3), 1, 2))
    @test size(m) == (8, 8)
    for cb in 0:3
        blk = m[cb*2+1:cb*2+2, cb*2+1:cb*2+2]
        if cb == 0
            @test approxeq(blk, mat(H))
        else
            @test approxeq(blk, I2)
        end
    end
    # 非整数幂
    @test approxeq(_matrix_pow(X.matrix, 0.5)' * _matrix_pow(X.matrix, 0.5), I2; tol=1e-8)
    @test approxeq(_matrix_pow(X.matrix, 2.0), I2)
    # GateOp 层修饰
    @test inv(GateOp(S, [1])) == GateOp(InvGate(S), [1], [])
    @test ctrl(CX(0, 1), 2).qubits == [2, 0, 1]
end
