@testset "draw" begin
    c = Circuit(2)
    push!(c, H(1))
    push!(c, CX(1, 2))
    s = draw(c)
    @test occursin("H", s)
    @test occursin("●", s)
    @test occursin("X", s)
    @test occursin("│", s)
    # ASCII 模式
    a = draw(c; ascii=true)
    @test occursin("*", a)
    @test !occursin("●", a)
    # 测量 + 经典线
    push!(c, measure(1, c.cregs[1][1]))
    s2 = draw(c)
    @test occursin("M", s2)
    @test occursin("c[1]", s2)
    # 参数标签 / 屏障 / 重置
    c2 = Circuit(2)
    push!(c2, RX(0.5, 1))
    push!(c2, barrier(1, 2))
    push!(c2, reinit(2))
    s3 = draw(c2)
    @test occursin("RX(0.5)", s3)
    @test occursin("░", s3)
    @test occursin("|0>", s3)
    # RZZ 双点 + 顶部标签
    c4 = Circuit(2)
    push!(c4, RZZ(0.7, 1, 2))
    @test occursin("RZZ(0.7)", draw(c4))
    # REPL 显示（text/plain 走 draw）
    @test occursin("─", repr(MIME"text/plain"(), c2))
    # SWAP 交叉符号
    c5 = Circuit(2)
    push!(c5, SWAP(1, 2))
    @test occursin("✕", draw(c5))
    @test occursin("x", draw(c5; ascii=true))
    # IfOp
    c6 = Circuit(2)
    if_then(c6, c6.cregs[1][1] == 1, Circuit([X(1)]))
    s6 = draw(c6)
    @test occursin("if (c == 1)", s6)
    @test occursin("IF", s6)
    # BlockOp：draw 会先展开（unroll）再绘制，body 重复 3 次
    c7 = Circuit(4)
    push!(c7, block(Circuit([H(1), CX(1, 2)]); name=:round, repeat=3))
    s7 = draw(c7)
    @test count("─H─", s7) == 3
    @test count("─X─", s7) == 3
    # io 方法
    io = IOBuffer()
    draw(io, c2)
    @test occursin("RX", String(take!(io)))
end
