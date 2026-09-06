using Pkg

# 自包含：激活 docs 环境，并将本包以 develop 方式接入
Pkg.activate(@__DIR__)
Pkg.develop(; path = dirname(@__DIR__))
Pkg.instantiate()

using Documenter
using QuantumCircuits
using QuantumCircuits.Hamiltonian

makedocs(;
    sitename = "QuantumCircuits.jl",
    modules = [QuantumCircuits],
    authors = "Guo Chu <guochu604b@gmail.com>",
    checkdocs = :exports,
    pages = [
        "首页" => "index.md",
        "约定" => "conventions.md",
        "门与修饰符" => "gates.md",
        "线路" => "circuits.md",
        "复合结构" => "composite.md",
        "噪声信道" => "channels.md",
        "Hamiltonian" => "hamiltonian.md",
        "QASM 序列化" => "io.md",
        "扩展协议" => "extending.md",
        "API 参考" => "api.md",
    ],
)

# 部署到 GitHub Pages 时取消注释并填写仓库地址（或改用 GitHub Actions 的 DocumenterScheduler）：
# deploydocs(;
#     repo = "github.com/<user>/QuantumCircuits.jl.git",
#     devbranch = "main",
# )
