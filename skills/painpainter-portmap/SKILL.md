---
name: painpainter-portmap
description: Generate network port relationship diagrams (网络设备接口关系图) from structured port tables using PainPainter. Produces Graphviz DOT text or editable drawio XML. Use when the user has a device/interface inventory table (设备名/端口/服务/对端 four fields) and wants it turned into a connection diagram, port map, 拓扑图 or 接口关系图 without manual drawing. Triggers include 端口关系图, 接口关系表, 端口清单画图, 设备连接图, 接口表转图, port map, port relationship diagram.
name_cn: PainPainter 端口关系图
description_cn: 接口关系表一键生成矢量图：Graphviz DOT 或可编辑的 drawio 文件
---

# PainPainter 端口关系图

把「网络设备接口关系表」生成矢量图：每台设备一个集群，每条端口记录呈 **端口 -- 服务 -- 对端** 三段关系链。两种输出：

| 输出 | 格式 | 排版 | 后续用法 |
|------|------|------|---------|
| `dot` | Graphviz DOT | dot 自动排版 | `dot -Tpng out.dot -o out.png` |
| `drawio` | drawio XML | 内置三列布局 | drawio Desktop / app.diagrams.net 打开，可继续编辑导出 |

## 数据格式

每台设备一张表，每条记录四个字段：

```json
{"hostname": "核心交换机A", "portname": "GE1/0/1", "services": "vlan100", "anotherside": "二楼接入B GE0/0/1"}
```

| 字段 | 含义 | 图上位置 |
|------|------|---------|
| hostname | 设备名（同表内保持一致） | 设备集群标题 |
| portname | 本端端口名 | 端口方框 |
| services | 端口上的服务（vlan/trunk…） | 中间连接点 |
| anotherside | 对端描述（设备+端口） | 对端集群标题 |

归整规则：同一设备的记录只进同一张表（以 hostname 分组）；缺失字段可填空字符串，但键名必须齐全。

## 调用

### 方式一：MCP 工具（优先）

若 painpainter MCP server 已注册，直接调用工具，`tables` 用上面的对象形式；`save_path` 指定输出文件，`overwrite: true` 才允许覆盖已存在文件：

```json
{"name": "painpainter_portmap_drawio",
 "arguments": {"tables": [[{"hostname": "SW-A", "portname": "GE1/0/1", "services": "vlan10", "anotherside": "SW-B GE0/0/1"}]],
               "save_path": "portmap.drawio"}}
```

注册方法见 [references/mcp-setup.md](references/mcp-setup.md)（仅当需要部署 MCP server 或排查工具 schema 时读取）。

### 方式二：命令行（gem 安装后）

```shell
# tables.json 即上文数据格式的 JSON 数组（可含 {"tables": [...]} 包装）
painpainter dot    -i tables.json -o portmap.dot      # Graphviz DOT
painpainter drawio -i tables.json -o portmap.drawio   # drawio XML

# 管道用法：stdin 读、stdout 写
cat tables.json | painpainter dot > portmap.dot
```

选项：`-i` 缺省 stdin，`-o` 缺省 stdout；输出已存在时默认拒写，确认覆盖加 `--overwrite`。未安装 gem 时在仓库根目录用 `ruby bin/painpainter ...` 等价调用。

### 方式三：Ruby 直调

```ruby
require 'painpainter'   # gem 安装后；源码态在仓库根目录用 ruby -Ilib 或改用方式二

tables = [[["SW-A", "GE1/0/1", "vlan10", "SW-B GE0/0/1"]]]

File.write    "portmap.dot",    DotPainter.make_portmap(tables)
File.binwrite "portmap.drawio", DrawioPainter.make_portmap(tables)
```

## 验证

- DOT：跑 `dot -Tpng portmap.dot -o portmap.png`（需 Graphviz），确认集群标题、关系链、无报错
- drawio：用 drawio 打开目检 —— 三列水平布局、连线为水平直线、集群先于子元素渲染
- 中文数据必须 `File.binwrite` 写 .drawio，否则外部编码会转坏 UTF-8
- 参数错误会返回「第几张表第几条记录」定位信息，按提示修正后重试即可

## 边界

- 空表会生成只有集群标题的窄带，属正常输出
- drawio 布局常数（列宽/行距）在 `lib/painpainter.rb` 的 `DrawioPainter` 模块头部，改后需重跑测试