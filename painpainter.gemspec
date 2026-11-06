require_relative "lib/painpainter"

Gem::Specification.new do |spec|
  spec.name          = "painpainter"
  spec.version       = PainPainter::VERSION
  spec.authors       = ["Frampt"]
  # 占位信息：公开发布前替换为维护者邮箱与仓库地址
  spec.email         = ["maintainer@example.com"]

  spec.summary       = %q{vector graphics document tools}
  spec.description   = %q{PainPainter makes vector-graph documents like network port maps, rendered via Graphviz DOT or editable drawio XML.}
  spec.homepage      = "https://github.com/OWNER/PainPainter"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.files         = Dir["lib/**/*.rb"] + Dir["bin/*"] +
                       ["LICENSE", "README.md", "mcp/painpainter_mcp_server.rb"]
  spec.bindir        = "bin"
  spec.executables   = ["painpainter", "painpainter-mcp"]
  spec.require_paths = ["lib"]
end