#coding:utf-8

# Copyright (C) 2026 PainPainter Authors
#
# 本项目基于 MIT 许可证发布；代码移植自作者本人的 imdoc/PainPainter/dotpainter.rb（AGPL-3.0），
# 由版权持有人本人重新授权。

#------------------------------------------------------------------------------
# PainPainter —— 制作矢量图的文档工具集
#------------------------------------------------------------------------------
# 成员一：DotPainter    —— 网络设备接口关系图（生成 Graphviz DOT，排版交给 dot）
# 成员二：DrawioPainter —— 网络设备接口关系图（生成 drawio XML，布局自行计算）
#
# PainPainter 的定位是“画起来有点累”的那类矢量图：结构规整、数据在手、
# 手工画图得不偿失，把数据表喂给生成器，输出交给排版引擎或矢量图编辑器。
#
# 用法：
#   require 'painpainter'
#   File.write "sample.dot", DotPainter.make_portmap(tables)
#   File.binwrite "sample.drawio", DrawioPainter.make_portmap(tables)
#   # dot -Tpng sample.dot -o sample.png      （Graphviz 渲染）
#   # sample.drawio 用 drawio Desktop / app.diagrams.net 打开查看与编辑
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# PainPainter —— 库级共享定义（版本号、入参规整、统一落盘）
#------------------------------------------------------------------------------
# VERSION 是唯一版本来源（gemspec 与 MCP server 均引用此处）；
# normalize_tables / save_text 由命令行工具与 MCP server 共用，保证行为一致。
#------------------------------------------------------------------------------
module PainPainter
  VERSION = '0.2.0'

  # 接口关系记录的四元组字段（与 DotPainter/DrawioPainter 的输入约定一致）
  QUAD_FIELDS = %w[hostname portname services anotherside].freeze

  module_function

  # 把绘图入参规整为绘图核心接受的位置数组。
  # 每张表属于一台设备；记录接受两种形式：
  #   4 元组 ["hostname", "portname", "services", "anotherside"]（原生 API 形式）
  #   键值对象 {"hostname"=>..., "portname"=>..., "services"=>..., "anotherside"=>...}
  # 错误信息定位到「第几张表第几条记录」，便于调用方（人或 AI）自纠。
  #
  # @param raw [Array] tables 原始入参
  # @return [Array<Array<Array>>] 规整后的四元组表数组
  def normalize_tables raw
    raise ArgumentError, 'tables 必须是非空数组' unless raw.is_a?(Array) && !raw.empty?
    raw.each_with_index.map do|table, ti|
      unless table.is_a?(Array)
        raise ArgumentError, "tables 第 #{ti+1} 张表应为数组（一台设备的记录列表），实际是 #{table.class}"
      end
      table.each_with_index.map do|record, ri|
        where = "tables 第 #{ti+1} 张表第 #{ri+1} 条记录"
        case record
        when Array
          if record.size != 4
            raise ArgumentError,
              "#{where}应为 4 元组 [hostname, portname, services, anotherside]，实际 #{record.size} 个元素"
          end
          record.map{|v| v.nil? ? '' : v.to_s }
        when Hash
          QUAD_FIELDS.map do|f|
            raise ArgumentError, "#{where}缺少必填字段 #{f}" unless record.key?(f)
            v = record[f]
            v.nil? ? '' : v.to_s
          end
        else
          raise ArgumentError, "#{where}应为 4 元组数组或键值对象，实际是 #{record.class}"
        end
      end
    end
  end

  # 统一落盘：UTF-8 字节写、无 BOM；默认拒绝覆盖已存在文件（防误覆盖）；
  # 父目录必须已存在（不擅自创建目录树）。
  #
  # @param text [String] 待保存内容
  # @param path [String] 目标路径（相对当前工作目录或绝对路径）
  # @param overwrite [Boolean] 已存在时是否允许覆盖
  # @return [String] 展开后的绝对路径
  def save_text text, path, overwrite = false
    raise ArgumentError, '保存路径不应为空字符串' if path.to_s.empty?
    unless overwrite
      raise ArgumentError, "文件已存在：#{File.expand_path(path)}（确认覆盖请传 overwrite: true）" if File.exist?(path)
    end
    dir = File.dirname(File.expand_path(path))
    raise ArgumentError, "目录不存在：#{dir}（请改用已存在目录下的路径）" unless Dir.exist?(dir)
    File.binwrite(path, text)
    File.expand_path(path)
  end
end

#------------------------------------------------------------------------------
# DotPainter —— Graphviz DOT 端口关系图生成
#------------------------------------------------------------------------------
# cover graphviz.dot
#
# make_portmap 把“网络设备接口关系表”渲染成无向图 DOT 文本：
#   - 每张输入表对应一个 subgraph cluster（集群框，label 取表首列唯一值，即主机名）
#   - 每条记录生成三个节点与一条关系链：
#       node<编号>   [shape=box, label=端口名]     —— 设备侧端口
#       inter<编号>  [label=服务]                   —— 中间的服务/虚连接点
#       ender<编号>  [shape=box, label=""]          —— 对端（label 记在 subgraph 上）
#     关系链：node -- inter -- ender
#   - 对端再包一层 subgraph cluster，label 为对端描述
#   - 节点编号规则：<10000*集群号 + 记录号>，保证 DOT 内全局唯一
#------------------------------------------------------------------------------
module DotPainter
  module_function

  # 制作网络设备接口关系图。
  #
  # @param tables [Array<Array<Array>>] 接口关系表数组，每张表属于一台设备，
  #   每条记录为四元组 [hostname, portname, services, anotherside]：
  #     hostname    —— 设备名（取表内唯一值作为集群标题）
  #     portname    —— 本端端口名（方框节点）
  #     services    —— 端口上的服务（中间连接点）
  #     anotherside —— 对端描述（作为对端子集群标题）
  # @return [String] graphviz DOT 文本（graph G { ... }）
  # @example
  #   table1 = [
  #     ["node1", "port11", "vlan11", "desc11"],
  #     ["node1", "port12", "vlan12", "desc12"]
  #   ]
  #   DotPainter.make_portmap([table1])  # => "graph G {\n\n  subgraph cluster1 {..."
  def make_portmap tables
    board,gnc = [], 0
    tables.each do|table|
      lnc,interinstance,endinstance,relationship = 0,[],[],[]
      gnc += 1
      head,body,tail = "subgraph cluster#{gnc} {",[], "}"
      body << %Q{  label="#{table.map{|i|i[0]}.uniq.first}"}
      table.each do|record|
        body << %Q{  node#{10000*gnc+lnc} [shape=box, label="#{record[1]}"]}
        interinstance << %Q{inter#{10000*gnc+lnc} [label="#{record[2]}"]}
        endinstance << %Q{subgraph cluster#{10000*gnc+lnc} {\n  label="#{record[3]}"\n  ender#{10000*gnc+lnc} [shape=box,label=""]\n}}
        relationship << %Q{node#{10000*gnc+lnc} -- inter#{10000*gnc+lnc} -- ender#{10000*gnc+lnc}}
        lnc += 1
      end
      board += [[head,body.join("\n"),tail].join("\n")]
      board += [interinstance.join("\n")]
      board += [endinstance.join("\n")]
      board += [relationship.join("\n")]

    end
    ["graph G {",board.map{|i|i.split("\n").map{|l|"  #{l}"}.join("\n")},"}"].join("\n\n")
  end

end

#------------------------------------------------------------------------------
# DrawioPainter —— drawio (diagrams.net) 端口关系图生成
#------------------------------------------------------------------------------
# cover drawio.mxgraph
#
# make_portmap 把与 DotPainter 相同的“网络设备接口关系表”渲染成 drawio 的
# mxGraph XML 文本（.drawio 文件，可用 drawio Desktop / app.diagrams.net 打开）。
# 与 Graphviz 不同，drawio 不做自动排版，因此布局由本模块手工计算：
#   - 每张输入表对应一个设备集群（swimlane，标题取表首列唯一值，即主机名），
#     横跨一个纵向“带”（band），多台设备自上而下依次排队
#   - 每条记录一行三列，行中心纵向对齐，保证连线为水平直线：
#       设备集群内的方框节点 node<编号>   [label=端口名]（集群内相对坐标）
#       中间椭圆    inter<编号>          [label=服务]（绝对坐标）
#       对端集群    cluster<编号>        [标题=对端描述]，内含空占位框 ender<编号>
#     连线：node → inter → ender 两条 level edge（exit/entry 锁定左右中点）
#   - 节点编号规则与 DotPainter 一致：10000*集群号 + 记录号，保证全局唯一，
#     对端集群直接借用 ender 的编号（cluster10000 与 ender10000 同级成对）
#------------------------------------------------------------------------------
module DrawioPainter
  module_function

  # —— 布局常量（单位：像素；drawio 坐标系：子节点相对父集群、其余相对图层"1"）
  CLUSTER_X  = 40    # 设备集群左缘 X
  CLUSTER_W  = 220   # 设备集群宽度
  TITLE_H    = 30    # 设备集群标题栏高度（swimlane startSize）
  ROW_STEP   = 60    # 每行纵向步进（端口框 40 + 行距 20）
  BOX_W      = 180   # 端口框/占位框宽度
  BOX_H      = 40    # 端口框/占位框/服务椭圆高度
  INTER_X    = 310   # 服务椭圆左缘 X
  INTER_W    = 110   # 服务椭圆宽度
  PEER_X     = 470   # 对端集群左缘 X
  PEER_W     = 200   # 对端集群宽度
  PEER_TITLE = 25    # 对端集群标题栏高度
  PEER_H     = 80    # 对端集群高度（标题 25 + 上留白 5 + 占位框 40 + 下留白 10）
  PEER_HEAD  = PEER_TITLE + 5 + BOX_H/2   # 对端集群顶到占位框中心的距离
  BAND_GAP   = 60    # 相邻设备集群（带）之间的纵向间隔
  BAND_TOP   = 40    # 首个设备集群的纵向起点

  # —— 视觉样式（蓝=本端端口，橙=服务，绿=对端；集群标题栏用同色加深）
  CLUSTER_STYLE = "swimlane;html=1;horizontal=1;startSize=30;fontSize=14;" \
                  "fontStyle=1;fillColor=#dae8fc;strokeColor=#6c8ebf;swimlaneFillColor=#ffffff;"
  PORT_STYLE    = "rounded=0;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;"
  INTER_STYLE   = "ellipse;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;"
  PEER_STYLE    = "swimlane;html=1;horizontal=1;startSize=25;fontStyle=1;" \
                  "fillColor=#d5e8d4;strokeColor=#82b366;swimlaneFillColor=#ffffff;"
  ENDER_STYLE   = "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;"
  EDGE_STYLE    = "edgeStyle=none;endArrow=none;strokeColor=#7f7f7f;" \
                  "exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;"

  # 制作网络设备接口关系图（drawio 版）。
  #
  # 输入表格式与 DotPainter.make_portmap 完全一致，返回可直接写入 .drawio
  # 文件的 mxGraph XML 文本；建议用 File.binwrite 写盘（避免外部编码转码）。
  #
  # @param tables [Array<Array<Array>>] 接口关系表数组，每张表属于一台设备，
  #   每条记录为四元组 [hostname, portname, services, anotherside]
  # @return [String] drawio mxGraph XML 文本（<mxfile>…</mxfile>）
  # @example
  #   table1 = [
  #     ["node1", "port11", "vlan11", "desc11"],
  #     ["node1", "port12", "vlan12", "desc12"]
  #   ]
  #   File.binwrite "sample.drawio", DrawioPainter.make_portmap([table1])
  def make_portmap tables
    cells = []
    y = BAND_TOP
    gnc = 0
    tables.each do|table|
      gnc += 1
      # 非空表：标题 30 + 首尾留白各 10 + n 行步进；空表也保留一条只带标题的窄带
      cluster_h = [ROW_STEP*table.size + TITLE_H, 100].max
      center_y = y + TITLE_H + ROW_STEP/2          # 首行行中心
      cells << vertex("cluster#{gnc}", esc(table.map{|i|i[0]}.uniq.first),
                      CLUSTER_STYLE, "1", CLUSTER_X, y, CLUSTER_W, cluster_h)
      table.each_with_index do|record, lnc|
        num = 10000*gnc + lnc
        cells << vertex("node#{num}", esc(record[1]), PORT_STYLE, "cluster#{gnc}",
                        (CLUSTER_W - BOX_W)/2, TITLE_H + 10 + lnc*ROW_STEP,
                        BOX_W, BOX_H)
        cells << vertex("inter#{num}", esc(record[2]), INTER_STYLE, "1",
                        INTER_X, center_y - BOX_H/2, INTER_W, BOX_H)
        cells << vertex("cluster#{num}", esc(record[3]), PEER_STYLE, "1",
                        PEER_X, center_y - PEER_HEAD, PEER_W, PEER_H)
        cells << vertex("ender#{num}", "", ENDER_STYLE, "cluster#{num}",
                        (PEER_W - BOX_W)/2, PEER_TITLE + 5, BOX_W, BOX_H)
        cells << edge("rel#{num}a", "node#{num}", "inter#{num}")
        cells << edge("rel#{num}b", "inter#{num}", "ender#{num}")
        center_y += ROW_STEP
      end
      y += cluster_h + BAND_GAP
    end
    wrap cells
  end

  class << self
    private

    # XML 属性值转义
    def esc text
      text.to_s.gsub(/[&<>"]/, {'&'=>'&amp;', '<'=>'&lt;', '>'=>'&gt;', '"'=>'&quot;'})
    end

    # 构造一个 mxCell 顶点
    def vertex id, value, style, parent, x, y, w, h
      "        <mxCell id=\"#{id}\" value=\"#{value}\" style=\"#{style}\" " \
      "vertex=\"1\" parent=\"#{parent}\">\n" \
      "          <mxGeometry x=\"#{x}\" y=\"#{y}\" width=\"#{w}\" height=\"#{h}\" as=\"geometry\" />\n" \
      "        </mxCell>"
    end

    # 构造一条 mxCell 边（锁定左右中点为入出锚点）
    def edge id, source, target
      "        <mxCell id=\"#{id}\" style=\"#{EDGE_STYLE}\" edge=\"1\" " \
      "parent=\"1\" source=\"#{source}\" target=\"#{target}\">\n" \
      "          <mxGeometry relative=\"1\" as=\"geometry\" />\n" \
      "        </mxCell>"
    end

    # 把 mxCell 列表包成完整的 .drawio 文档
    def wrap cells
      [ "<mxfile host=\"painpainter\">",
        "  <diagram id=\"portmap\" name=\"Portmap\">",
        "    <mxGraphModel dx=\"800\" dy=\"600\" grid=\"1\" gridSize=\"10\" " \
        "guides=\"1\" tooltips=\"1\" connect=\"1\" arrows=\"1\" fold=\"1\" " \
        "page=\"1\" pageScale=\"1\" pageWidth=\"850\" pageHeight=\"1100\" " \
        "math=\"0\" shadow=\"0\">",
        "      <root>",
        "        <mxCell id=\"0\" />",
        "        <mxCell id=\"1\" parent=\"0\" />",
        *cells,
        "      </root>",
        "    </mxGraphModel>",
        "  </diagram>",
        "</mxfile>"].join("\n") + "\n"
    end
  end
end
