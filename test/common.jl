# 测试公共工具
const I2 = Matrix{ComplexF64}(I, 2, 2)
approxeq(a, b; tol=1e-10) = maximum(abs.(a - b)) <= tol
