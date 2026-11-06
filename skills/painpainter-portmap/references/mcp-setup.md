# MCP Server 部署与工具说明

painpainter MCP server 把 `DotPainter` / `DrawioPainter` 封装成两个 stdio 工具。本文件供 AI 在需要部署、注册或排查工具调用时读取。

## 服务器

- 位置：`<PainPainter目录>/mcp/painpainter_mcp_server.rb`（gem 安装后位于 gem 安装目录内）
- 实现：Ruby 零依赖（仅标准库 `json`），绘图逻辑来自 `lib/painpainter.rb` 单一来源
- 传输：stdio，每行一条 JSON-RPC 2.0 消息（UTF-8）
- 启动：
  - 已安装 gem：`painpainter-mcp`（PATH 中的命令）
  - 源码态：`ruby mcp/painpainter_mcp_server.rb`（在仓库根目录执行，路径解析基于脚本自身位置，任意目录启动均可）

## TeleAgent 注册

在 TeleAgent Desktop：头像 → 工具设置 → MCP 配置 → 添加。

已安装 gem（推荐，命令名即入口，无需绝对路径）：

```json
{
  "mcpServers": {
    "painpainter": { "command": "painpainter-mcp" }
  }
}
```

源码态（未安装 gem，用 ruby 直接启动；`<PainPainter目录>` 替换为实际仓库路径）：

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

无任何凭证需求。注册后在工具设置确认状态"已连接"，随后可直接调用 `painpainter_portmap_dot` / `painpainter_portmap_drawio`。

## 工具参数（两个工具共用）

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| tables | array | 是 | 接口关系表数组；每张表一台设备；记录为 4 字段对象（推荐）或 4 元组数组 |
| save_path | string | 否 | 输出文件路径；缺省只返回文本不落盘 |
| overwrite | boolean | 否 | 默认 false；目标文件已存在时需显式传 true 才覆盖 |

记录字段：`hostname` / `portname` / `services` / `anotherside`，语义见 SKILL.md 数据格式表。

响应同时含：
- `content[0].text`：完整 DOT/XML 文本 + 落盘信息 + 渲染提示
- `structuredContent`：`{format, text, saved_path, bytes, renderer}`

## 错误形态

| 情形 | 形态 | 自纠方式 |
|------|------|---------|
| 记录缺字段 / 不是 4 元组 | `result.isError: true`，文本含「tables 第 N 张表第 M 条记录…」 | 按定位补齐字段重试 |
| save_path 已存在且未传 overwrite | `result.isError: true`，提示 overwrite: true | 确认覆盖或换路径 |
| save_path 父目录不存在 | `result.isError: true`，提示目录不存在 | 先建目录或改路径 |
| 工具名拼错 | JSON-RPC error -32602，列出可用工具 | 用返回的名称重试 |

## 协议细节

- 支持方法：`initialize`、`ping`、`tools/list`、`tools/call`；通知（无 id）不产生响应
- protocolVersion 白名单回显：`2024-11-05` / `2025-03-26` / `2025-06-18`，未知版本回落 `2024-11-05`
- serverInfo：`{"name": "painpainter", "version": "<与 gem 版本一致>"}`
- 协议级日志不写 stdout（stdout 仅协议消息）；调试可用 stderr

## 验证

```shell
painpainter-mcp --check            # 环境自检：Ruby 版本/库加载/绘图冒烟/协议模块
ruby test/mcp_server_test.rb        # 13 项端到端测试（在仓库根目录执行）
```

也可以用 MCP Inspector 人工交互验证：`npx @modelcontextprotocol/inspector painpainter-mcp`
