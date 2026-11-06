# PainPainter MCP Server

把绘图接口封装成 MCP（Model Context Protocol）tools，供 AI 客户端（TeleAgent、MCP Inspector 等）直接调用：AI 整理接口关系数据 → 调工具 → 拿到 DOT/drawio 文本或落盘文件。

- **服务器**：`painpainter_mcp_server.rb` —— 纯 Ruby 零依赖（仅标准库 `json`），stdio 传输
- **启动器**：`../bin/painpainter-mcp` —— 命令行入口（启动服务 / `--check` 自检）
- **绘图核心**：`../lib/painpainter.rb` 单一来源，与 gem 完全一致，MCP 层不做任何绘图实现

## 工具

| 工具 | 输出 | 排版 |
|------|------|------|
| `painpainter_portmap_dot` | Graphviz DOT 文本 | dot 自动排版 |
| `painpainter_portmap_drawio` | drawio XML 文本 | 内置三列水平带布局 |

共用参数（inputSchema 见 `tools/list`）：

- `tables`（必填）：接口关系表数组；每张表一台设备；记录接受两种形式
  - 键值对象（推荐给 AI）：`{"hostname": ..., "portname": ..., "services": ..., "anotherside": ...}`
  - 四元组：`["hostname", "portname", "services", "anotherside"]`
- `save_path`（可选）：落盘路径，缺省只返回文本
- `overwrite`（默认 false）：目标文件已存在时需显式传 true，防误覆盖

响应 `content` 携带全文与用法提示，`structuredContent` 携带 `{format, text, saved_path, bytes, renderer}`。

## 启动与注册

```shell
painpainter-mcp            # gem 安装后：启动 stdio 服务器
painpainter-mcp --check    # 环境自检后退出
ruby mcp/painpainter_mcp_server.rb   # 源码态等价启动（仓库根目录执行）
```

TeleAgent：工具设置 → MCP 配置 → 添加。

已安装 gem（推荐，无需绝对路径）：

```json
{
  "mcpServers": {
    "painpainter": { "command": "painpainter-mcp" }
  }
}
```

源码态（`<PainPainter目录>` 替换为实际仓库路径）：

```json
{
  "mcpServers": {
    "painpainter": {
      "command": "ruby",
      "args": ["<PainPainter目录>/mcp/painpainter_mcp_server.rb"]
    }
  }
}
```

## 协议实现

- 消息：每行一条 JSON-RPC 2.0（UTF-8，换行分隔）；stdout 仅输出协议消息
- 方法：`initialize`（protocolVersion 白名单回显，未知回落 2024-11-05）、`ping`、`tools/list`、`tools/call`；通知不回包；未知方法 -32601；坏行 -32700；未知工具名 -32602
- 参数/执行错误统一走 `result.isError: true`，错误文本定位到「第几张表第几条记录」并给出修复动作，便于调用方 AI 自纠
- 落盘安全：字节写无 BOM；存在即拒（除非 overwrite）；父目录必须已存在

## 测试与验证

```shell
ruby test/mcp_server_test.rb     # 在仓库根目录执行
```

13 项端到端测试：握手/协议回显、工具列表 schema、DOT 与 drawio 生成（含中文无损）、落盘与覆盖保护、目录校验、参数错误定位、未知工具协议错误、坏 JSON 行。

交互式排查可用 MCP Inspector：`npx @modelcontextprotocol/inspector painpainter-mcp`

## 相关

- 命令行绘图：`../bin/painpainter`（`painpainter dot|drawio -i 表.json -o 输出`）
- 技能形式的用法指引：`../skills/painpainter-portmap/`（含 `references/mcp-setup.md` 部署手册）
- 生成器本身：`../lib/painpainter.rb`（`DotPainter` / `DrawioPainter`）
