# Luxor 图形后端扩展（weakdep：Luxor 在测试环境中由 Pkg 自动接入）
using Luxor

@testset "plots extension" begin
    ext = Base.get_extension(QuantumCircuits, :QuantumCircuitsLuxorExt)
    @test ext !== nothing

    c = Circuit(2)
    push!(c, H(1))
    push!(c, CX(1, 2))
    push!(c, measure(1, c.cregs[1][1]))

    # SVG 字符串输出（注意：Luxor 将文字转为矢量 glyph，不包含字面字符）
    s = ext.plot(c)
    @test s isa AbstractString
    @test occursin("<svg", s)
    @test occursin("<rect", s)     # 门盒
    @test occursin("path", s)      # 导线/符号

    # 保存到文件（PNG/PDF 走 Luxor 同一路径）
    f = tempname() * ".svg"
    @test ext.save_plot(c, f) == f
    @test isfile(f)
    @test occursin("<svg", read(f, String))

    f2 = tempname() * ".png"
    ext.plot(c; filename=f2)
    @test isfile(f2)
end
