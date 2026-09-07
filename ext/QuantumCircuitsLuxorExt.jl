# =============================================================================
# QuantumCircuitsLuxorExt — Luxor 图形后端（包扩展）
#
# 触发方式：加载 Luxor 后本模块自动生效。
#
#     using QuantumCircuits, Luxor
#     ext = Base.get_extension(QuantumCircuits, :QuantumCircuitsLuxorExt)
#     ext.plot(c)                    # → SVG 字符串
#     ext.save_plot(c, "bell.svg")   # 保存（按扩展名支持 svg / png / pdf）
#
# 复用基础包 `QuantumCircuits._layout` 的列布局模型。
# =============================================================================

module QuantumCircuitsLuxorExt

using Luxor
using QuantumCircuits
using QuantumCircuits: _layout

export plot, save_plot

function _col_width(col; mincol::Real)
    w = Float64(mincol)
    isempty(col.label) || (w = max(w, 12 * textwidth(col.label) + 20))
    for cell in values(col.cells)
        w = max(w, 9 * textwidth(cell.text) + 26)
    end
    return w
end

"""
    plot(c::Circuit; filename=nothing, format=:svg, wiregap=46, mincol=56,
         margin=36, background="white")

把线路渲染为图形。`filename === nothing` 时返回 SVG 字符串；否则保存到文件
（格式由扩展名推断，Luxor 支持 `svg` / `png` / `pdf`）。
"""
function plot(c::QuantumCircuits.Circuit;
              filename::Union{Nothing,AbstractString}=nothing,
              format::Symbol=:svg,
              wiregap::Real=46,
              colgap::Real=14,
              mincol::Real=56,
              margin::Real=36,
              bgcolor::String="white")
    cols, nq, coff, ncl = _layout(c)
    widths = [_col_width(col; mincol=mincol) for col in cols]
    xs = Float64[]
    x = margin + 60
    for w in widths
        push!(xs, x + w / 2)
        x += w + colgap
    end
    canvasw = x + margin - colgap
    nwires = nq + ncl
    labelh = any(!isempty(col.label) for col in cols) ? 24 : 4
    canvash = margin + labelh + (nwires - 1) * wiregap + margin

    fname = filename === nothing ? tempname() * "." * string(format) : String(filename)
    Drawing(round(Int, canvasw), round(Int, canvash), fname)
    # Luxor 文件输出的坐标原点在画布左上角、y 向下
    y(r) = margin + labelh + (r - 1) * wiregap
    background(bgcolor)

    # 导线：量子线实线，经典线虚线
    setline(1.2)
    for r in 1:nwires
        setcolor("black")
        setdash(r <= nq ? "solid" : "dash")
        line(Point(margin + 40, y(r)), Point(canvasw - margin, y(r)), :stroke)
    end
    setdash("solid")
    setfont("monospace", 12)
    setcolor("#444444")
    for r in 1:nq
        settext("q[$r]", Point(margin, y(r)); halign="right", valign="center")
    end
    for r in c.cregs, j in 1:r.n
        settext(string(r.name, "[", j, "]"), Point(margin, y(nq + coff[r.name] + j)); halign="right", valign="center")
    end

    for (i, col) in enumerate(cols)
        xc = xs[i]
        isempty(col.label) || begin
            setcolor("#333333")
            setfont("sans-serif", 12)
            settext(col.label, Point(xc, 12); halign="center", valign="center")
        end
        # 连接线（画在符号下层）
        setcolor("black")
        setline(1.2)
        for r in (col.lo+1):col.hi
            line(Point(xc, y(r - 1)), Point(xc, y(r)), :stroke)
        end
        # 符号
        for (r, cell) in col.cells
            yy = y(r)
            if cell.kind === :box
                bw = max(34, 9 * textwidth(cell.text) + 12)
                setcolor("white")
                box(Point(xc, yy), bw, 28, :fill)
                setcolor("black")
                setline(1.2)
                box(Point(xc, yy), bw, 28, :stroke)
                setfont("sans-serif", 13)
                settext(cell.text, Point(xc, yy); halign="center", valign="center")
            elseif cell.kind === :ctrl
                setcolor("black")
                circle(Point(xc, yy), 5, :fill)
            elseif cell.kind === :negctrl
                setcolor("white")
                circle(Point(xc, yy), 5, :fill)
                setcolor("black")
                setline(1.2)
                circle(Point(xc, yy), 5, :stroke)
            elseif cell.kind === :swap
                setline(1.5)
                line(Point(xc - 5, yy - 5), Point(xc + 5, yy + 5), :stroke)
                line(Point(xc - 5, yy + 5), Point(xc + 5, yy - 5), :stroke)
            elseif cell.kind === :measure
                setcolor("white")
                box(Point(xc, yy), 26, 26, :fill)
                setcolor("black")
                setline(1.2)
                box(Point(xc, yy), 26, 26, :stroke)
                setfont("sans-serif", 13)
                settext("M", Point(xc, yy); halign="center", valign="center")
            elseif cell.kind === :cltarget
                setcolor("black")
                poly([Point(xc - 6, yy - 6), Point(xc + 6, yy - 6), Point(xc, yy + 6)], :fill)
            elseif cell.kind === :barrier
                ylo = y(col.lo) - 14
                yhi = y(col.hi) + 14
                setcolor(0.85, 0.85, 0.85)
                box(Point(xc, (ylo + yhi) / 2), 14, yhi - ylo, :fill)
            end
        end
    end

    finish()
    # svg 是文本可直接返回；png / pdf 是二进制，返回字节向量
    return filename === nothing ?
           (format === :svg ? read(fname, String) : read(fname)) : fname
end

"""
    save_plot(c::Circuit, filename::AbstractString; kwargs...)

把线路图形保存到 `filename`（按扩展名选择格式：`svg` / `png` / `pdf`）。
参数与 [`plot`](@ref) 相同。
"""
save_plot(c::QuantumCircuits.Circuit, filename::AbstractString; kwargs...) =
    plot(c; filename=filename, kwargs...)

end # module QuantumCircuitsLuxorExt
