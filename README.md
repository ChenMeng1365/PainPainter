# PainPainter

制作矢量图的文档工具集——「画起来有点累」的那类图，把数据表交给生成器，交给 Graphviz 排版，或者直接产出可编辑的 drawio 文件。

当前成员：

- **DotPainter**：网络设备接口关系图，输入端口关系表，输出 Graphviz DOT 文本
- **DrawioPainter**：网络设备接口关系图，输入同一张端口关系表，输出 drawio（diagrams.net）XML 文本

## 安装

```shell
gem build painpainter.gemspec
gem install --local painpainter-0.2.0.gem
```

安装后获得两个命令：`painpainter`（绘图）与 `painpainter-mcp`（MCP 服务器启动器）。

## 使用

### 命令行

```shell
# tables.json：接口关系表 JSON（记录可用对象或 4 元组，见数据格式）
painpainter dot    -i tables.json -o sample.dot       # Graphviz DOT
painpainter drawio -i tables.json -o sample.drawio    # drawio XML
cat tables.json | painpainter dot > sample.dot        # stdin/stdout 管道
```

`-i` 缺省读 stdin，`-o` 缺省写 stdout；输出已存在时默认拒写，确认覆盖加 `--overwrite`。

### Ruby API

```ruby
require 'painpainter'

table1 = [
  ["node1", "port11", "vlan11", "desc11"],
  ["node1", "port12", "vlan12", "desc12"],
  ["node1", "port13", "vlan13", "desc13"]
]

table2 = [
  ["node2", "port21", "vlan21", "desc21"],
  ["node2", "port22", "vlan22", "desc22"],
  ["node2", "port23", "vlan23", "desc23"]
]

tables = [table1, table2]

File.write "sample.dot", DotPainter.make_portmap(tables)
File.binwrite "sample.drawio", DrawioPainter.make_portmap(tables)
```

渲染成图（需安装 [Graphviz](https://graphviz.org)）：

```shell
dot -Tpng sample.dot -o sample.png
```

而 `sample.drawio` 用 [drawio Desktop](https://github.com/jgraph/drawio-desktop/releases) 或浏览器打开 [app.diagrams.net](https://app.diagrams.net) 即可查看，所见即所得，还可以继续手工编辑、导出 PNG/SVG/PDF。

## AI 集成（MCP / Skill）

两个生成器都封装成了 AI 可直接调用的接口：

- **MCP**：`painpainter-mcp`（或源码态 `mcp/painpainter_mcp_server.rb`），stdio 传输、纯 Ruby 零依赖，暴露 `painpainter_portmap_dot` / `painpainter_portmap_drawio` 两个工具（支持 save_path 落盘与 overwrite 防误覆盖）。注册方法见 [mcp/README.md](mcp/README.md)
- **Skill**：`skills/painpainter-portmap/`，面向 AI 的使用技能（数据归整规则、调用路径、验证方法），可按需复制到智能体技能目录启用

## 数据格式

两个生成器的 `make_portmap` 接收同一种接口关系表数组，每张表属于一台设备，每条记录为四元组：

| 字段 | 含义 | DOT 图上位置 | drawio 图上位置 |
|------|------|---------|---------|
| hostname | 设备名（表内唯一值） | 设备集群 subgraph 标题 | 设备集群（蓝色标题栏）|
| portname | 本端端口名 | 方框节点（node） | 端口框（蓝，集群内左列）|
| services | 端口上的服务 | 中间连接点（inter） | 服务椭圆（橙，中列）|
| anotherside | 对端描述 | 对端子集群标题（ender 所在） | 对端集群标题栏（绿，内含空占位框）|

## 说明

- 代码移植自作者本人的 imdoc/PainPainter（AGPL-3.0），由版权持有人重新授权为本项目的 MIT
- DOT 输出由 Graphviz 自动排版；drawio 输出的布局由 DrawioPainter 手工计算：每台设备一条横向「带」，记录逐行按「端口 - 服务 - 对端」三列排布，行内水平对齐，多台设备自上而下叠加
- 写 .drawio 文件建议用 `File.binwrite`，避免中文设备名被外部编码转码
- 测试：`ruby -I lib test/dot_painter_test.rb`、`ruby -I lib test/drawio_painter_test.rb`、`ruby test/cli_test.rb`、`ruby test/mcp_server_test.rb`
