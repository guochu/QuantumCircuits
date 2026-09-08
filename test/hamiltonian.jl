@testset "hamiltonian" begin
    t1 = PauliTerm(1.0, 1=>:Z, 2=>:X)
    @test t1.ops == [1=>:Z, 2=>:X]          # 位置自动排序
    @test t1.coeff isa Float64              # 系数无参数化：类型动态保留
    @test PauliTerm(1, 1=>:Z).coeff isa Int # 整数系数保持原类型
    # 同 qubit 合并：X·X = I
    @test PauliTerm(1.0, 1=>:X, 1=>:X).ops == Pair{Int,Symbol}[]
    # Pauli 代数：X·Y = iZ（相位使系数提升为复数）
    xy = PauliTerm(1.0, 1=>:X) * PauliTerm(1.0, 1=>:Y)
    @test xy.coeff ≈ im && xy.ops == [1=>:Z]
    @test xy.coeff isa ComplexF64
    yx = PauliTerm(1.0, 1=>:Y) * PauliTerm(1.0, 1=>:X)
    @test yx.coeff ≈ -im
    # 加法合并同类项
    s = PauliTerm(1.0, 1=>:Z) + PauliTerm(2.0, 1=>:Z) + PauliTerm(1.0, 2=>:X)
    @test length(s.terms) == 2
    # 矩阵展开（小端序）：qubit 0 = 最低位 → kron(P_1, P_0)；全实项 ⇒ 实矩阵
    m = mat(PauliSum([PauliTerm(1.0, 1=>:X)]), 2)
    @test m isa Matrix{Float64}
    @test approxeq(Matrix(m), kron(I2, mat(X)))
    m2 = mat(PauliSum([PauliTerm(1.0, 2=>:Z, 1=>:X)]), 2)
    @test approxeq(Matrix(m2), kron(mat(Z), mat(X)))
    # 单项展开
    mt = mat(PauliTerm(2.0, 2=>:Z, 1=>:X), 2)
    @test mt isa Matrix{Float64}
    @test approxeq(mt, 2 * kron(mat(Z), mat(X)))
    mc = mat(PauliTerm(1.0, 1=>:Y), 1)
    @test mc isa Matrix{ComplexF64}
    @test approxeq(mc, mat(Y))
    # 乘法分配
    s12 = PauliSum([PauliTerm(1.0, 0=>:X)]) * PauliSum([PauliTerm(1.0, 0=>:Y)])
    @test length(s12.terms) == 1 && s12.terms[1].coeff ≈ im
    # 伴随
    @test adjoint(PauliTerm(1.0 + 2.0im, 0=>:X)).coeff ≈ 1.0 - 2.0im
    # 标量
    @test (2.0 * PauliTerm(1.0, 0=>:X)).coeff ≈ 2.0
end

@testset "spinhamiltonian" begin
    # 构造：位置排序 + 算子校验
    t = SpinOpTerm(0.5, 2=>:Y, 1=>:Z)
    @test t.coeff == 0.5
    @test first.(t.ops) == [1, 2]
    @test SpinOpTerm(1.0, 1=>[0 1; -1 0]).ops == [1=>[0 1; -1 0]]
    @test_throws ArgumentError SpinOpTerm(1.0, 1=>randn(3, 3))
    @test_throws ArgumentError SpinOpTerm(1.0, 1=>:Q)

    # 代数：数乘 / 加法 / 负号
    @test (2 * t).coeff == 1.0
    @test (-t).coeff == -0.5
    s = t + SpinOpTerm(1.0, 3=>:X)
    @test s isa SpinOpSum && length(s.terms) == 2

    # 伴随与厄米性：:P ↔ :M
    @test adjoint(SpinOpTerm(1.0, 1=>:P)).ops[1][2] == :M
    @test adjoint(SpinOpTerm(0.5 + 0.5im, 1=>:Y)) == SpinOpTerm(0.5 - 0.5im, 1=>:Y)
    @test ishermitian(SpinOpTerm(0.7, 1=>:Z, 2=>:Z))
    @test !ishermitian(SpinOpTerm(1.0, 1=>:P))

    # 矩阵展开（小端序）：qubit 1 = 最低位 → 单比特算子为 kron(I, A)，qubit 2 为 kron(A, I)
    mz = mat(SpinOpTerm(0.5, 1=>:Z), 2)
    Z = ComplexF64[1 0; 0 -1]; I2 = Matrix{ComplexF64}(I, 2, 2)
    @test mz ≈ 0.5 * kron(I2, Z)
    t2 = SpinOpTerm(0.5, 2=>:Z, 1=>:X)
    X = ComplexF64[0 1; 1 0]
    @test mat(t2, 2) ≈ 0.5 * kron(Z, X)
    # 同位双算子：按乘积顺序保留（:P·:M = |0⟩⟨0| ≠ :M·:P）
    pm = mat(SpinOpTerm(1.0, 1=>:P, 1=>:M), 1)
    @test pm ≈ ComplexF64[1.0 0; 0 0]
    # 任意 2×2 非厄米矩阵（qubit 2 = 高位 → kron(A, I)）
    A = ComplexF64[0.5 0.2im; -0.3 1.2]
    mA = mat(SpinOpTerm(0.7, 2=>A), 2)
    @test mA ≈ 0.7 * kron(A, I2)
    # SpinOpSum
    H = SpinOpSum([SpinOpTerm(0.5, 1=>:Z, 2=>:Z), SpinOpTerm(1.0, 2=>:X)])
    @test mat(H, 2) ≈ 0.5 * kron(Z, Z) + kron(X, I2)
    # 位置越界
    @test_throws ArgumentError mat(SpinOpTerm(1.0, 5=>:X), 2)
end
