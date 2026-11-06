#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# 本项目基于 MIT 许可证发布。

#------------------------------------------------------------------------------
# PainPainter MCP Server —— stdio 传输的 MCP（Model Context Protocol）服务器
#------------------------------------------------------------------------------
# 把 DotPainter / DrawioPainter 的绘图接口封装成 MCP tools，供 AI 客户端
# （TeleAgent / MCP Inspector 等）直接调用。
#
# 零依赖：仅 Ruby 标准库（json）；绘图核心来自 ../lib/painpainter.rb 单一来源。
#
# 启动（stdio）：ruby mcp/painpainter_mcp_server.rb
# 消息格式：每行一条 JSON-RPC 2.0 消息（UTF-8，换行分隔）。
#
# 暴露工具：
#   painpainter_portmap_dot    —— 接口关系表 -> Graphviz DOT（自动排版）
#   painpainter_portmap_drawio —— 接口关系表 -> drawio XML（可编辑，布局内置）
#
# 两个工具共用参数：
#   tables    [必填] 接口关系表数组，记录支持键值对象（推荐）或四元组两种形式
#   save_path [选填] 落盘路径；缺省只返回文本
#   overwrite [选填] 默认 false；save_path 已存在时需显式传 true 才覆盖
#------------------------------------------------------------------------------

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'json'
require 'painpainter'

module PainPainterMCP
  # 与 lib/painpainter.rb 的 PainPainter::VERSION 同步（唯一版本来源）
  SERVER_NAME       = 'painpainter'
  SERVER_VERSION    = PainPainter::VERSION
  DEFAULT_PROTOCOL  = '2024-11-05'
  PROTOCOL_VERSIONS = %w[2024-11-05 2025-03-26 2025-06-18].freeze

  # 接口关系记录的四元组字段（定义在 PainPainter 库中，MCP 引用而非重复）
  QUAD_FIELDS = PainPainter::QUAD_FIELDS
  TOOL_NAMES  = %w[painpainter_portmap_dot painpainter_portmap_drawio].freeze

  module_function

  # —— 工具定义（JSON Schema）—————————————————————————

  def record_schema
    { oneOf: [
        { type: 'array', minItems: 4, maxItems: 4,
          items: { type: 'string' },
          description: '四元组 [hostname, portname, services, anotherside]' },
        { type: 'object',
          properties: {
            hostname:    { type: 'string', description: '设备名（同一张表内保持一致）' },
            portname:    { type: 'string', description: '本端端口名，如 GE1/0/1' },
            services:    { type: 'string', description: '端口上的服务，如 vlan100 / trunk' },
            anotherside: { type: 'string', description: '对端描述，如 "对端设备名 端口名"' }
          },
          required: QUAD_FIELDS, additionalProperties: false,
          description: '键值对象（推荐，字段语义自明）' }
      ] }
  end

  def tables_schema
    { type: 'array', minItems: 1,
      description: '接口关系表数组：每张表属于一台设备，记录逐条描述该设备的一个端口',
      items: { type: 'array', description: '一台设备的全部记录', items: record_schema } }
  end

  def call_tool_schema
    { type: 'object',
      properties: {
        tables: tables_schema,
        save_path: { type: 'string',
                     description: '可选：输出文件路径（绝对或相对当前工作目录）；缺省只返回文本不落盘' },
        overwrite: { type: 'boolean',
                     description: '可选：save_path 已存在且确认覆盖时传 true，默认 false（防误覆盖）' }
      },
      required: ['tables'],
      additionalProperties: false }
  end

  def tools
    [ { name: 'painpainter_portmap_dot',
        description: '把网络设备接口关系表渲染成 Graphviz DOT 端口关系图文本。' \
                     '每台设备一个集群，每条记录呈「端口 -- 服务 -- 对端」关系链。' \
                     '渲染成图需 Graphviz：dot -Tpng <file>.dot -o out.png',
        inputSchema: call_tool_schema,
        annotations: { readOnlyHint: false, destructiveHint: false,
                       idempotentHint: true, openWorldHint: false } },
      { name: 'painpainter_portmap_drawio',
        description: '把网络设备接口关系表渲染成 drawio (diagrams.net) XML 文本，' \
                     '可直接写入 .drawio 文件用 drawio Desktop / app.diagrams.net 打开编辑导出。' \
                     '布局内置：每台设备一条「端口 - 服务 - 对端」三列水平带。',
        inputSchema: call_tool_schema,
        annotations: { readOnlyHint: false, destructiveHint: false,
                       idempotentHint: true, openWorldHint: false } } ]
  end

  # —— 参数规整与执行 —————————————————————————————————

  def call_tool name, args
    format    = name.end_with?('dot') ? 'dot' : 'drawio'
    tables    = PainPainter.normalize_tables(args['tables'])
    text      = format == 'dot' ? DotPainter.make_portmap(tables)
                                : DrawioPainter.make_portmap(tables)
    saved     = args['save_path'] ? PainPainter.save_text(text, args['save_path'], !!args['overwrite']) : nil
    renderer  = format == 'dot' ? 'Graphviz（dot -Tpng <file>.dot -o out.png）'
                                : 'drawio Desktop / app.diagrams.net（可编辑、导出 PNG/SVG/PDF）'

    footer = saved ? "已保存：#{saved}" : "（未落盘；需要保存请传 save_path）"
    { content: [ { type: 'text', text: "#{text}\n\n#{footer}\n用法：#{renderer}" } ],
      structuredContent: { format: format, text: text, saved_path: saved,
                           bytes: text.bytesize, renderer: renderer.split('（').first } }
  end

  # —— JSON-RPC 分发 ——————————————————————————————————

  def error_response id, code, message
    { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
  end

  def dispatch msg
    return nil unless msg.is_a?(Hash) && msg['method']
    method, id = msg['method'].to_s, msg['id']
    params     = msg['params'] || {}

    result =
      case method
      when 'initialize'
        version = PROTOCOL_VERSIONS.include?(params['protocolVersion']) ?
                    params['protocolVersion'] : DEFAULT_PROTOCOL
        { protocolVersion: version, capabilities: { tools: {} },
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION } }
      when 'ping'
        {}
      when 'tools/list'
        { tools: tools }
      when 'tools/call'
        tname = params['name'].to_s
        unless TOOL_NAMES.include?(tname)
          return error_response(id, -32602,
                                "Unknown tool: #{tname}. Available: #{TOOL_NAMES.join(', ')}")
        end
        call_tool(tname, params['arguments'] || {})
      else
        # 其余均为通知或未知方法
        return id ? error_response(id, -32601, "Method not found: #{method}") : nil
      end
    id ? { jsonrpc: '2.0', id: id, result: result } : nil
  end

  # —— 主循环 ————————————————————————————————————————

  def run
    STDIN.set_encoding('UTF-8')
    $stdout.set_encoding('UTF-8')
    $stdout.sync = true                    # stdio MCP 客户端逐行读取，必须立即刷新
    STDIN.each_line do|line|
      line = line.strip
      next if line.empty?
      msg =
        begin
          JSON.parse(line)
        rescue JSON::ParserError => e
          $stdout.puts JSON.generate(error_response(nil, -32700, "Parse error: #{e.message}"))
          next
        end
      resp =
        begin
          dispatch(msg)
        rescue ArgumentError => e          # 参数级错误：isError 结果，AI 可自纠
          next if msg['id'].nil?
          { jsonrpc: '2.0', id: msg['id'],
            result: { content: [ { type: 'text', text: "参数错误：#{e.message}\n请修正后重试。" } ],
                      isError: true } }
        rescue StandardError => e          # 执行级错误：同样以 isError 返回
          next if msg['id'].nil?
          { jsonrpc: '2.0', id: msg['id'],
            result: { content: [ { type: 'text',
                                   text: "执行错误：#{e.class}: #{e.message}" } ],
                      isError: true } }
        end
      $stdout.puts JSON.generate(resp) if resp
    end
  end
end

PainPainterMCP.run if $PROGRAM_NAME == __FILE__
