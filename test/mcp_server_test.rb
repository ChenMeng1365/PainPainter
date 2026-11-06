#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# PainPainter MCP Server 端到端测试：spawn 子进程，走完整 JSON-RPC 往返。
# 运行：ruby test/mcp_server_test.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'minitest/autorun'
require 'json'

SERVER = File.expand_path('../mcp/painpainter_mcp_server.rb', __dir__)

class McpServerTest < Minitest::Test
  TABLES_OBJECT = [                     # 键值对象形式（AI 推荐用法）
    [ { hostname: '核心交换机A', portname: 'GE1/0/1',  services: 'vlan100', anotherside: '二楼接入交换机B GE0/0/1' },
      { hostname: '核心交换机A', portname: 'GE1/0/2',  services: 'vlan200', anotherside: '三楼接入交换机C GE0/0/24' } ],
    [ { hostname: 'node2', portname: 'port21', services: 'vlan21', anotherside: 'desc21' } ]
  ]
  TABLES_QUAD = [                       # 四元组数组形式（兼容原 gem API）
    [['node1', 'port11', 'vlan11', 'desc11'],
     ['node1', 'port12', 'vlan12', 'desc12']]
  ]

  def setup
    @io = IO.popen(['ruby', SERVER], 'r+')
    @io.set_encoding('UTF-8')
    @next_id = 0
    # 标准握手：initialize + initialized 通知
    resp = request 'initialize', { protocolVersion: '2024-11-05',
                                   capabilities: {}, clientInfo: { name: 'test', version: '0' } }
    assert_equal 'painpainter', resp['result']['serverInfo']['name']
    notify 'notifications/initialized'
  end

  def teardown
    @io.close unless @io.closed?
  end

  # —— 基础协议 —————————————————————————————————

  def test_initialize_echoes_protocol_and_capabilities
    # setup 已握手 2024-11-05；再用 2025-03-26 握一次验证回显
    resp = request 'initialize', { protocolVersion: '2025-03-26', capabilities: {} }
    assert_equal '2025-03-26', resp['result']['protocolVersion']
    assert resp['result']['capabilities'].key?('tools')
    assert_match(/\d+\.\d+/, resp['result']['serverInfo']['version'])
  end

  def test_ping_and_unknown_method
    assert_empty request('ping')['result']
    resp = request 'resources/list'
    assert_equal(-32601, resp['error']['code'])
    assert_includes resp['error']['message'], 'resources/list'
  end

  def test_initialized_notification_produces_no_output
    # 通知无响应：发送通知后紧跟一次 ping，读到的第一行应是 ping 的响应
    notify 'notifications/initialized'
    assert_empty request('ping')['result']
  end

  def test_invalid_json_line_gets_parse_error
    @io.puts 'this is not json'
    @io.flush
    line = @io.gets
    resp = JSON.parse(line)
    assert_equal(-32700, resp['error']['code'])
    assert_nil resp['id']
  end

  # —— 工具列表 —————————————————————————————————

  def test_tools_list
    tools = request('tools/list')['result']['tools']
    names = tools.map{|t| t['name'] }
    assert_equal %w[painpainter_portmap_dot painpainter_portmap_drawio], names
    tools.each do|t|
      schema = t['inputSchema']
      assert_equal 'object', schema['type']
      assert_equal ['tables'], schema['required']
      %w[hostname portname services anotherside].each do|f|     # 记录字段对 AI 可见
        assert t.to_s.include?(f), "schema 应描述字段 #{f}"
      end
      ann = t['annotations']
      assert_equal true, ann['idempotentHint']
      assert_equal false, ann['destructiveHint']
    end
  end

  # —— DOT 生成 —————————————————————————————————

  def test_call_dot_with_object_records
    resp = call_tool 'painpainter_portmap_dot', { tables: TABLES_OBJECT }
    text = resp['structuredContent']['text']
    assert_equal 'dot', resp['structuredContent']['format']
    assert text.start_with?('graph G {')
    assert_includes text, 'label="核心交换机A"'
    assert_includes text, 'label="GE1/0/1"'
    assert_includes text, 'label="vlan100"'
    assert_includes text, 'label="二楼接入交换机B GE0/0/1"'     # 中文无损往返
    assert_includes text, 'node10000 -- inter10000 -- ender10000'
    assert_includes resp['content'][0]['text'], '未落盘'
  end

  def test_call_dot_with_quad_records
    resp = call_tool 'painpainter_portmap_dot', { tables: TABLES_QUAD }
    assert_includes resp['structuredContent']['text'], 'label="port11"'
  end

  # —— drawio 生成 —————————————————————————————————

  def test_call_drawio
    resp = call_tool 'painpainter_portmap_drawio', { tables: TABLES_QUAD }
    sc = resp['structuredContent']
    assert_equal 'drawio', sc['format']
    assert sc['text'].start_with?('<mxfile')
    assert_includes sc['text'], '<mxGraphModel'
    assert_includes sc['text'], 'value="vlan11"'
    # 返回的 XML 可被标准 XML 解析器接受
    require 'rexml/document'
    refute_nil REXML::Document.new(sc['text']).root
  end

  # —— 落盘与覆盖保护 ———————————————————————————

  def test_save_path_writes_file_and_rejects_overwrite_without_flag
    path = File.join(__dir__, '..', '.temp', 'mcp_out.dot')
    File.delete(path) if File.exist?(path)
    resp = call_tool 'painpainter_portmap_dot',
                     { tables: TABLES_QUAD, save_path: path }
    assert_equal File.expand_path(path), resp['structuredContent']['saved_path']
    assert File.exist?(path)
    assert File.read(path, mode: 'rb').start_with?('graph G {')

    # 再次保存同一路径：默认拒绝
    resp = call_tool 'painpainter_portmap_dot',
                     { tables: TABLES_QUAD, save_path: path }
    assert_equal true, resp['isError']
    assert_includes resp['content'][0]['text'], 'overwrite: true'
    assert_includes resp['content'][0]['text'], '参数错误'

    # 显式 overwrite: true 后成功
    resp = call_tool 'painpainter_portmap_dot',
                     { tables: TABLES_QUAD, save_path: path, overwrite: true }
    assert_nil resp['isError']
    assert File.exist?(path)
  ensure
    File.delete(path) if File.exist?(path)
  end

  def test_save_path_rejects_missing_directory
    resp = call_tool 'painpainter_portmap_dot',
                     { tables: TABLES_QUAD,
                       save_path: File.join(__dir__, 'no', 'such', 'dir.dot') }
    assert_equal true, resp['isError']
    assert_includes resp['content'][0]['text'], '目录不存在'
  end

  # —— 参数错误（可自纠信息）——————————————————

  def test_missing_tables_argument
    resp = call_tool 'painpainter_portmap_dot', {}
    assert_equal true, resp['isError']
    assert_includes resp['content'][0]['text'], 'tables'
  end

  def test_bad_record_locates_the_exact_offset
    resp = call_tool 'painpainter_portmap_dot',
                     { tables: [ [ { hostname: 'n1', portname: 'p1' } ] ] }  # 缺 services/anotherside
    assert_equal true, resp['isError']
    assert_includes resp['content'][0]['text'], '第 1 张表第 1 条记录'
    assert_includes resp['content'][0]['text'], 'services'

    resp = call_tool 'painpainter_portmap_dot', { tables: [[['n1', 'p1', 'v1']]] }
    assert_equal true, resp['isError']
    assert_includes resp['content'][0]['text'], '实际 3 个元素'
  end

  def test_unknown_tool_name_is_protocol_error
    resp = request 'tools/call', { name: 'painpainter_nope', arguments: { tables: TABLES_QUAD } }
    assert_equal(-32602, resp['error']['code'])
    assert_includes resp['error']['message'], 'painpainter_portmap_dot'
  end

  # —— helpers —————————————————————————————————

  def request method, params = nil
    @next_id += 1
    msg = { jsonrpc: '2.0', id: @next_id, method: method }
    msg['params'] = params if params
    @io.puts JSON.generate(msg)
    @io.flush
    line = @io.gets
    refute_nil line, "server 应对 #{method} 有响应"
    JSON.parse(line)
  end

  def notify method, params = nil
    msg = { jsonrpc: '2.0', method: method }
    msg['params'] = params if params
    @io.puts JSON.generate(msg)
    @io.flush
  end

  def call_tool name, arguments
    request('tools/call', { name: name, arguments: arguments })['result']
  end
end
