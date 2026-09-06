@testset "hamiltonian" begin
    t1 = PauliTerm(1.0, 1=>:Z, 2=>:X)
    @test t1.ops == [1=>:Z, 2=>:X]          # 位置自动排序
    @test t1 isa PauliTerm{Float64}          # 实系数保持实类型
    # 同 qubit 合并：X·X = I
    @test PauliTerm(1.0, 0=>:X, 0=>:X).ops == Pair{Int,Symbol}[]
    # Pauli 代数：X·Y = iZ（相位使系数提升为复数）
    xy = PauliTerm(1.0, 0=>:X) * PauliTerm(1.0, 0=>:Y)
    @test xy.coeff ≈ im && xy.ops == [0=>:Z]
    @test xy isa PauliTerm{ComplexF64}
    yx = PauliTerm(1.0, 0=>:Y) * PauliTerm(1.0, 0=>:X)
    @test yx.coeff ≈ -im
    # 加法合并同类项
    s = PauliTerm(1.0, 0=>:Z) + PauliTerm(2.0, 0=>:Z) + PauliTerm(1.0, 1=>:X)
    @test length(s.terms) == 2
    # 矩阵展开（小端序）：qubit 0 = 最低位 → kron(P_1, P_0)；全实项 ⇒ 实矩阵
    m = mat(PauliSum([PauliTerm(1.0, 0=>:X)]), 2)
    @test m isa SparseMatrixCSC{Float64}
    @test approxeq(Matrix(m), kron(I2, mat(X)))
    m2 = mat(PauliSum([PauliTerm(1.0, 1=>:Z, 0=>:X)]), 2)
    @test approxeq(Matrix(m2), kron(mat(Z), mat(X)))
    # 乘法分配
    s12 = PauliSum([PauliTerm(1.0, 0=>:X)]) * PauliSum([PauliTerm(1.0, 0=>:Y)])
    @test length(s12.terms) == 1 && s12.terms[1].coeff ≈ im
    # 伴随
    @test adjoint(PauliTerm(1.0 + 2.0im, 0=>:X)).coeff ≈ 1.0 - 2.0im
    # 标量
    @test (2.0 * PauliTerm(1.0, 0=>:X)).coeff ≈ 2.0
end
