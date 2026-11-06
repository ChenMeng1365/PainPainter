#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# 命令行工具测试：bin/painpainter（绘图）与 bin/painpainter-mcp（启动器）。
# 运行：ruby test/cli_test.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'minitest/autorun'
require 'open3'
require 'json'
require 'painpainter'

class CliTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  CLI  = File.join(ROOT, 'bin', 'painpainter')
  MCP  = File.join(ROOT, 'bin', 'painpainter-mcp')
  TMP  = File.join(ROOT, '.temp')

  # 对象记录形式（与 MCP/CLI 文档一致）
  TABLES = [
    [ { 'hostname' => 'SW-A', 'portname' => 'GE1/0/1',
        'services' => 'vlan100', 'anotherside' => 'SW-B GE0/0/1' },
      { 'hostname' => 'SW-A', 'portname' => 'GE1/0/2',
        'services' => 'vlan200', 'anotherside' => 'SW-C GE0/0/2' } ]
  ]

  def setup
    Dir.mkdir(TMP) unless Dir.exist?(TMP)
  end

  def run_cli *args, stdin_data: ''
    out, err, status = Open3.capture3('ruby', CLI, *args,
                                      stdin_data: stdin_data, binmode: true)
    [out.force_encoding('UTF-8'), err.force_encoding('UTF-8'), status]
  end

  def run_mcp *args
    out, err, status = Open3.capture3('ruby', MCP, *args, binmode: true)
    [out.force_encoding('UTF-8'), err.force_encoding('UTF-8'), status]
  end

  # —— painpainter 主命令 ————————————————————————————

  def test_version
    out, _err, status = run_cli 'version'
    assert status.success?
    assert_equal PainPainter::VERSION, out.strip
  end

  def test_help
    out, _err, status = run_cli 'help'
    assert status.success?
    assert_includes out, 'painpainter dot'
    assert_includes out, '--overwrite'

    # 无参数同样打印帮助
    out, _err, status = run_cli
    assert status.success?
    assert_includes out, '用法'
  end

  def test_unknown_command_fails
    _out, err, status = run_cli 'svg'
    assert_equal 1, status.exitstatus
    assert_includes err, '未知命令'
  end

  # —— 绘图：stdin → stdout ————————————————————————

  def test_dot_from_stdin
    out, err, status = run_cli 'dot', stdin_data: JSON.generate(TABLES)
    assert status.success?, "stderr: #{err}"
    assert out.start_with?('graph G {')
    assert_includes out, 'label="GE1/0/1"'
    assert_includes out, 'label="vlan100"'
    assert_includes out, 'label="SW-B GE0/0/1"'
    assert_empty err
  end

  def test_drawio_accepts_wrapped_tables_key
    payload = JSON.generate('tables' => TABLES)       # {"tables": [...]} 包装形式
    out, _err, status = run_cli 'drawio', stdin_data: payload
    assert status.success?
    assert out.start_with?('<mxfile')
    assert_includes out, 'value="GE1/0/2"'
  end

  def test_chinese_labels_round_trip
    tables = [[{ 'hostname' => '核心交换机A', 'portname' => 'GE1/0/1',
                 'services' => 'vlan100', 'anotherside' => '出口路由器E1 GE0/0' }]]
    out, _err, status = run_cli 'dot', stdin_data: JSON.generate(tables)
    assert status.success?
    assert_includes out, 'label="核心交换机A"'
    assert_includes out, 'label="出口路由器E1 GE0/0"'
  end

  # —— 绘图：文件输入/输出 ————————————————————————

  def test_file_io_and_overwrite_protection
    input  = File.join(TMP, 'cli_in.json')
    output = File.join(TMP, 'cli_out.drawio')
    File.write(input, JSON.generate(TABLES), mode: 'wb')
    File.delete(output) if File.exist?(output)

    out, err, status = run_cli 'drawio', '-i', input, '-o', output
    assert status.success?, "stderr: #{err}"
    assert_empty out                                  # 落盘模式 stdout 保持干净
    assert_includes err, '已生成'
    assert File.exist?(output)
    assert File.read(output, mode: 'rb').start_with?('<mxfile')

    # 默认拒绝覆盖
    _out, err, status = run_cli 'drawio', '-i', input, '-o', output
    assert_equal 1, status.exitstatus
    assert_includes err, 'overwrite'

    # 显式 --overwrite 后成功
    _out, err, status = run_cli 'drawio', '-i', input, '-o', output, '--overwrite'
    assert status.success?, "stderr: #{err}"
  ensure
    File.delete(input)  if File.exist?(input)
    File.delete(output) if File.exist?(output)
  end

  def test_missing_output_directory_fails
    _out, err, status = run_cli 'dot', '-o', File.join(TMP, 'no', 'such', 'dir.dot'),
                            stdin_data: JSON.generate(TABLES)
    assert_equal 1, status.exitstatus
    assert_includes err, '目录不存在'
  end

  # —— 输入校验 ————————————————————————————————

  def test_empty_stdin_fails
    _out, err, status = run_cli 'dot', stdin_data: ''
    assert_equal 1, status.exitstatus
    assert_includes err, '输入为空'
  end

  def test_invalid_json_fails
    _out, err, status = run_cli 'dot', stdin_data: 'not json'
    assert_equal 1, status.exitstatus
    assert_includes err, 'JSON'
  end

  def test_record_error_locates_offset
    payload = JSON.generate([[{ 'hostname' => 'SW-A', 'portname' => 'GE1/0/1' }]])
    _out, err, status = run_cli 'dot', stdin_data: payload
    assert_equal 1, status.exitstatus
    assert_includes err, '第 1 张表第 1 条记录'
    assert_includes err, 'services'
  end

  # —— painpainter-mcp 启动器 ————————————————————

  def test_mcp_check_passes
    out, _err, status = run_mcp '--check'
    assert status.success?, "stdout: #{out}"
    assert_includes out, 'OK'
    assert_includes out, '自检通过'
  end

  def test_mcp_help
    out, _err, status = run_mcp '--help'
    assert status.success?
    assert_includes out, 'MCP 服务器启动器'
  end
end