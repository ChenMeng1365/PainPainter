#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# DrawioPainter 测试：make_portmap 生成的 mxGraph XML 结构与布局断言。
# 运行：ruby -I lib test/drawio_painter_test.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'rexml/document'
require 'painpainter'

class DrawioPainterTest < Minitest::Test
  # 与 dot_painter_test.rb 相同的样例数据（两台设备各三条记录）
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
    @xml = DrawioPainter.make_portmap(TABLES)
    @doc = REXML::Document.new(@xml)            # 解析失败会直接抛异常
    @cells = REXML::XPath.match(@doc, '//mxCell')
    @cell_by_id = @cells.map{|c| [c.attributes['id'], c] }.to_h
    @edges = @cells.select{|c| c.attributes['edge'] == '1' }
    @vertices = @cells.select{|c| c.attributes['vertex'] == '1' }
  end

  # —— 文档骨架 —————————————————————————————————

  def test_mxfile_wrapper
    # 层级：mxfile > diagram > mxGraphModel > root > mxCell...
    assert_equal 'mxfile', @doc.root.name
    assert_equal 'diagram', @doc.root.elements[1].name
    assert_equal 'mxGraphModel', @doc.root.elements[1].elements[1].name
    assert_equal 'root', @doc.root.elements[1].elements[1].elements[1].name
    assert_equal '0', @cell_by_id['0'].attributes['id']
    assert_equal '0', @cell_by_id['1'].attributes['parent']
  end

  def test_cell_count
    # 2 底层单元 + 2 设备集群 + (6 端口 + 6 服务 + 6 对端集群 + 6 占位框) + 12 连线
    assert_equal 40, @cells.size
    assert_equal 26, @vertices.size
    assert_equal 12, @edges.size
  end

  def test_ids_unique
    ids = @cells.map{|c| c.attributes['id'] }
    assert_equal ids.size, ids.uniq.size, "所有 mxCell id 应全局唯一"
  end

  # —— 单元与编号 —————————————————————————————————

  def test_device_clusters_with_hostname_labels
    # 每张表一个设备集群（swimlane），标题取首列唯一值，编号与 DotPainter 一致
    c1 = cell 'cluster1'
    assert_equal 'node1', c1.attributes['value']
    assert_includes c1.attributes['style'], 'swimlane'
    assert_includes c1.attributes['style'], 'startSize=30'
    assert_equal 'node2', cell('cluster2').attributes['value']
  end

  def test_port_service_and_peer_cells
    # 记录四元组映射：端口->node、服务->inter、对端->peer 集群（含 ender 占位框）
    assert_equal 'port11', cell('node10000').attributes['value']
    assert_equal 'cluster1', cell('node10000').attributes['parent']
    assert_includes cell('node10000').attributes['style'], 'rounded=0'

    assert_equal 'vlan11', cell('inter10000').attributes['value']
    assert_equal '1', cell('inter10000').attributes['parent']
    assert_includes cell('inter10000').attributes['style'], 'ellipse'

    assert_equal 'desc11', cell('cluster10000').attributes['value']
    assert_includes cell('cluster10000').attributes['style'], 'startSize=25'

    ender = cell 'ender10000'
    assert_equal '', ender.attributes['value']
    assert_equal 'cluster10000', ender.attributes['parent']

    # 第二台设备编号落在 2xxxx 段
    assert_equal 'port23', cell('node20002').attributes['value']
    assert_equal 'desc23', cell('cluster20002').attributes['value']
  end

  def test_relationship_edges
    # 每条记录两条边：node → inter、inter → ender
    pairs = @edges.map{|e| [e.attributes['source'], e.attributes['target']] }
    assert_includes pairs, %w[node10000 inter10000]
    assert_includes pairs, %w[inter10000 ender10000]
    assert_includes pairs, %w[node20002 inter20002]
    assert_includes pairs, %w[inter20002 ender20002]

    # 边的 source/target 必须指向实际存在的顶点
    vertex_ids = @vertices.map{|c| c.attributes['id'] }
    pairs.each do|source, target|
      assert vertex_ids.include?(source), "边 source 不存在：#{source}"
      assert vertex_ids.include?(target), "边 target 不存在：#{target}"
    end

    # every 顶点之间的父级引用也必须存在
    @cells.each do|c|
      parent = c.attributes['parent']
      assert_includes @cell_by_id.keys, parent, "parent 不存在：#{parent}" if parent
    end
  end

  def test_container_drawn_before_children
    # drawio 按 XML 顺序渲染：集群应先于其中的子节点出现
    assert cell_index('cluster1') < cell_index('node10000')
    assert cell_index('cluster10000') < cell_index('ender10000')
    assert cell_index('cluster2') < cell_index('node20002')
  end

  # —— 布局 —————————————————————————————————

  def test_band_geometry
    # 设备集群：等宽、首台位于 (40, 40)、第二台在首台下方并留出带间隔
    g1 = geometry 'cluster1'
    assert_equal 40, g1[:x]
    assert_equal 40, g1[:y]
    assert_equal 220, g1[:width]
    assert_equal 210, g1[:height]            # 3 行：30 标题 + 3*60 步进

    g2 = geometry 'cluster2'
    assert_equal g1[:x], g2[:x]
    assert_equal g1[:y] + g1[:height] + 60, g2[:y]
  end

  def test_rows_horizontally_aligned
    # 同条记录的 node/inter/ender 行中心应在同一水平线（连线保持水平）
    (1..2).each do|gnc|
      (0..2).each do|lnc|
        num = 10000*gnc + lnc
        port_c = center_y "node#{num}"
        inter_c = center_y "inter#{num}"
        ender_c = center_y "ender#{num}"
        assert_in_delta port_c, inter_c, 0.001, "记录 #{num}：端口与服务椭圆未对齐"
        assert_in_delta port_c, ender_c, 0.001, "记录 #{num}：端口与对端占位框未对齐"
      end
    end
  end

  def test_rows_inside_band_and_no_vertical_overlap
    # 行元素纵向落在所属集群的带内，且集群之间不重叠
    %w[cluster1 cluster2].each_with_index do|cluster_id, idx|
      top = geometry(cluster_id)[:y]
      bottom = top + geometry(cluster_id)[:height]
      gnc = idx + 1
      (0..2).each do|lnc|
        num = 10000*gnc + lnc
        assert center_y("node#{num}") > top, "node#{num} 应在带内"
        assert center_y("ender#{num}") < bottom, "ender#{num} 应在带内"
      end
    end
  end

  # —— 边界与转义 —————————————————————————————————

  def test_xml_escaping
    xml = DrawioPainter.make_portmap([[["h1", 'p&<>"1', 's&v', 'd<x>']]])
    assert_includes xml, 'value="p&amp;&lt;&gt;&quot;1"'
    assert_includes xml, 'value="s&amp;v"'
    assert_includes xml, 'value="d&lt;x&gt;"'
    doc = REXML::Document.new(xml)
    assert_equal 'p&<>"1', doc.elements['//mxCell[@id="node10000"]'].attributes['value']
  end

  def test_empty_table_produces_label_only_band
    xml = DrawioPainter.make_portmap([[ ]])
    doc = REXML::Document.new(xml)
    cluster = doc.elements['//mxCell[@id="cluster1"]']
    refute_nil cluster, "空表也应生成带标题的集群"
    assert_equal '', cluster.attributes['value']
    assert_equal '100', cluster.elements['mxGeometry'].attributes['height']
    assert xml.end_with?("</mxfile>\n"), "文档应以闭合标签结尾"
  end

  private

  def cell id
    @cell_by_id.fetch(id)
  end

  def cell_index id
    @cells.index{|c| c.attributes['id'] == id }
  end

  # 顶点几何（相对父集群的原始值）
  def geometry id
    geo = cell(id).elements['mxGeometry']
    { x: geo.attributes['x'].to_f, y: geo.attributes['y'].to_f,
      width: geo.attributes['width'].to_f, height: geo.attributes['height'].to_f }
  end

  # 顶点绝对纵坐标中心（沿 parent 链累加相对坐标，直到图层 "1"）
  def center_y id
    y, c = 0.0, cell(id)
    loop do
      geo = c.elements['mxGeometry']
      y += geo ? geo.attributes['y'].to_f : 0.0
      parent = c.attributes['parent']
      break if parent.nil? || parent == '0' || parent == '1'
      c = @cell_by_id.fetch(parent)
    end
    y + geometry(id)[:height]/2
  end
end
