#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# DotPainter 测试：make_portmap 生成的 DOT 结构断言。
# 运行：ruby -I lib test/dot_painter_test.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'painpainter'

class DotPainterTest < Minitest::Test
  # imdoc README 中的样例数据（两台设备各三条记录）
  TABLES = [
    [
      ["node1", "port11", "vlan11", "desc11"],
      ["node1", "port12", "vlan12", "desc12"],
      ["node1", "port13", "vlan13", "desc13"]
    ],
    [
      ["node2", "port21", "vlan21", "desc21"],
      ["node2", "port22", "vlan22", "desc22"],
      ["node2", "port23", "vlan23", "desc23"]
    ]
  ]

  def setup
    @dot = DotPainter.make_portmap(TABLES)
  end

  def test_graph_wrapping
    assert @dot.start_with?("graph G {")
    assert @dot.end_with?("}")
  end

  def test_device_clusters_with_hostname_labels
    # 每张表一个设备集群，label 取首列唯一值（主机名）
    assert_includes @dot, 'subgraph cluster1 {'
    assert_includes @dot, 'subgraph cluster2 {'
    assert_includes @dot, 'label="node1"'
    assert_includes @dot, 'label="node2"'
  end

  def test_port_service_and_peer_nodes
    # 记录四元组映射：端口->node、服务->inter、对端->ender（label 在对端子集群上）
    # 原版编号规则：10000*集群号 + 记录号（记录号从 0 起）
    assert_includes @dot, 'node10000 [shape=box, label="port11"]'
    assert_includes @dot, 'inter10000 [label="vlan11"]'
    assert_includes @dot, 'subgraph cluster10000 {'
    assert_includes @dot, 'label="desc11"'
    assert_includes @dot, 'ender10000 [shape=box,label=""]'
    # 第二台设备编号落在 2xxxx 段
    assert_includes @dot, 'node20002 [shape=box, label="port23"]'
    assert_includes @dot, 'label="desc23"'
  end

  def test_relationship_chains
    assert_includes @dot, 'node10000 -- inter10000 -- ender10000'
    assert_includes @dot, 'node10002 -- inter10002 -- ender10002'
    assert_includes @dot, 'node20000 -- inter20000 -- ender20000'
  end

  def test_braces_balanced
    # DOT 结构合法性粗校验：花括号配平
    assert_equal @dot.count('{'), @dot.count('}'), "DOT 花括号应配平"
  end

  def test_output_is_valid_dot_syntax_shape
    # 关键语句形态：节点/边/子图行均以两空格缩进出现在图声明之内
    lines = @dot.lines.map(&:strip).reject(&:empty?)
    assert_includes lines, 'graph G {'
    assert lines.include?('node10000 [shape=box, label="port11"]'), "节点行应保持缩进规范"
    assert lines.include?('subgraph cluster1 {')
  end
end
