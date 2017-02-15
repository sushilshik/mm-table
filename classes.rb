#!/usr/bin/ruby
# encoding: UTF-8
#2017-02-15 17:01:04
require 'sinatra'
require 'cgi'
require 'yaml'
require 'json'
require 'nokogiri'
require 'sqlite3'
require 'logger'
require 'rubygems'
class MM
	attr_accessor :conf, :file, :fileName, :dirPath, :extn, :link, :linkShort, :themes, :pagesInBook, :readPagesInBook, :leafReadPagesInBook, :mapTable, :db, :mapDbId, :xml, :allNodes, :allNodesCount, :allRootNodes, :wrappedLinks, :mmInternalConf, :allLinksCount, :timelinesList, :lastEditDate
	def initialize(file, mapTable, conf)
		@file = file
		@conf = conf
		@fileName = File.basename(file)
		@dirPath = File.dirname(file)
		@extn = File.extname(file)
		@mapTable = mapTable
		@db = @mapTable.db
		fileContent = File.read(@file).gsub(/^<!--.*-->$/,'')
		@xml = Nokogiri::XML(fileContent) { |config|
		   #config.options = Nokogiri::XML::ParseOptions::STRICT
		   #config.options = Nokogiri::XML::ParseOptions::PEDANTIC
		   #config.options = Nokogiri::XML::ParseOptions::RECOVER
		   #config.options = Nokogiri::XML::ParseOptions::OLD10
		   #config.options = Nokogiri::XML::ParseOptions::HUGE
		}
		@link = "<span class='mmFileLink' mapfile='" +@file +"' href='/m?f=" + @file + "'>" + @fileName + "</span>"
		@linkShort = "<span class='mmFileLink' mapfile='" +@file +"' href='/m?f=" + @file + "'>" + @fileName.sub(/\n/,'')[0..9] + "</span>"
		@db.execute "insert into maps(name, path) values('#{fileName}', '#{dirPath+"/"+fileName}')"
		@mapDbId = @db.last_insert_row_id
		@leafReadPagesInBook = leafReadPagesInBookCount()
		@readPagesInBook = readPagesInBookCount()
		@pagesInBook = self.class.pagesInBookCount(file,@xml)
		self.prepareThemes
		@mapTable.pagesInBooksSum += @pagesInBook
		@mapTable.readPagesInBooksSum += @readPagesInBook
		@mapTable.leafReadPagesInBooksSum += @leafReadPagesInBook
		@allNodes = @xml.xpath("//child[@xsi:type='node']")
		@allNodesCount = self.countAllNodes()
		@allRootNodes = self.getAllRootNodes()
		allLinksXml = @xml.xpath("//child[@xsi:type='link']")
		@wrappedLinks = MMWrappedLinks.new(allLinksXml)
		@allLinksCount = self.countAllLinks()
		#saveDataInNeo4j() if @mapTable.rebuildNeo4j == "true" && @allNodes.length < 1200 && @wrappedLinks.wrappedLinksList.length < 1200
		saveDataInNeo4j() if @mapTable.neo4jHelper.rebuildNeo4j == "true"
		p " nodes: " + @allNodesCount.to_s + ", links: " + @allLinksCount.to_s
		buildMMInternalConf()
		p "<<< " + @mapTable.allMaps.length().to_s + ": " + @fileName
		@lastEditDate = nil
		#@xml = nil
	end
	def saveDataInNeo4j()
		p ">>> " + @fileName
		timeAllNeo4j = Time.now
		queryParts= []
		time1 = Time.now
		@allNodes.each_with_index{|n, index|
		   vueId = n.xpath("@ID").text()
		   if vueId.length() > 0
		      label = n .xpath("@label").text()
		      label = CGI.unescape(label).gsub("\n", " ")
		      label = label.gsub("\\", "\\\\\\\\").gsub("'","\'").gsub('"','\"')
		      file = URI.escape(@file)
		      fillColor = n.xpath("fillColor/text()")
		      fontSize = n.xpath("font/text()[1]").text().split("-")[2].to_i
		      queryParts << "(:VueNode{ vueId: \"#{vueId.to_s}\", label: \"#{label}\", file: \"#{file}\", fillColor: \"#{fillColor}\", fontSize: \"#{fontSize.to_s}\"})"
		   end
		   if (index % 2000) == 0 && index != 0
		      query = "create " + queryParts.join(",")
		      time2 = Time.now
		      @mapTable.neo4jHelper.dataImportQuery(query)
		      p " index: " + index.to_s + " timeNodesParts: " + (Time.now - time2).to_s
		      queryParts = []
		   end
		}
		p " timeNodes: " + (Time.now - time1).to_s
		if queryParts.length() > 0
		   query = "create " + queryParts.join(",")
		   @mapTable.neo4jHelper.dataImportQuery(query)
		end
		timeLinks = Time.now
		queryLinksParts = []
		@wrappedLinks.wrappedLinksList.each_with_index{|l, index|
		   nodeIdStart = l.nodeIdStart.to_s
		   nodeIdEnd = l.nodeIdEnd.to_s
		   if !nodeIdStart.nil? && !nodeIdEnd.nil?
		      label = CGI.unescape(l.label).gsub("\n", " ")
		      label = label.gsub("\\", "\\\\\\\\").gsub("'","\'").gsub('"','\"')
		      file = URI.escape(@file)
		      qPart = "match (a:VueNode), (b:VueNode) where a.vueId = '#{nodeIdStart}' and a.file ='#{file}' "
		      qPart += "and b.vueId = '#{nodeIdEnd}' and b.file ='#{file}' create (a)-[r:VueRelation { file: '#{file}', label: \"#{label}\" }]->(b)"
		      queryLinksParts << qPart
		   end
		   if (index % 300) == 0 && index != 0
		      p " indexLinks: " + index.to_s
		      queryLinks = queryLinksParts.join(" with count(*) as dummy ")
		      @mapTable.neo4jHelper.dataImportQuery(queryLinks)
		      queryLinksParts = []
		   end
		}
		   if (queryLinksParts.length() > 0)
		      p " linksLastPart"
		      queryLinks = queryLinksParts.join(" with count(*) as dummy ")
		      @mapTable.neo4jHelper.dataImportQuery(queryLinks)
		   end
		p " timeLinks: " + (Time.now - timeLinks).to_s
		p " timeAllNeo4j: " + (Time.now - timeAllNeo4j).to_s
	end
	def buildMMInternalConf()
		@mmInternalConf = MMInternalConf.new()
		@mmInternalConf.assemble(@file, @mapTable.neo4jHelper)
	end
	def leafReadPagesInBookCount()
		#`grep -R '#C1F780' "#{file}" | wc -l`.to_i
		@xml.xpath("//child[@xsi:type=\"node\" and fillColor/text()=\"#C1F780\" and @label=\"New Node\"]").length.to_i
	end
	def readPagesInBookCount()
		@xml.xpath("//child[@xsi:type=\"node\" and fillColor/text()=\"#8AEE95\" and @label=\"New Node\"]").length.to_i
	end
	def self.pagesInBookCount(file,xml)
		imgs = xml.xpath("//child[@xsi:type=\"node\" and child/resource/*[@value=\"JPEG\"] and @label=\"New Node\"]")
		imgs = imgs.select {|i|
		   imgHeight = i.xpath("child/resource/*[@key=\"image.height\"]").xpath("@value").text().to_f
		   pageHeight = i.xpath("child/@height").text().to_f
		   (imgHeight / pageHeight) < 3
		}
		`grep -R 'JPEG' "#{file}" | wc -l`.to_i/2
		(imgs.length).to_i
	end
	def countAllNodes()
		size = @allNodes.size
		@mapTable.allNodesSum += (size != nil) ? size : 0
		size
	end
	def getAllRootNodes()
		roots = []
		redNodes = @xml.xpath("//child[@xsi:type='node' and fillColor/text()='#EA2218']")
		fontSizeLimit = 72
		roots = redNodes.select{ |node|
		   font = node.xpath("font/text()[1]").text()
		   fontSize = font.split("-")[2].to_i
		   fontSize >= fontSizeLimit
		}
		size = roots.size()
		@mapTable.allRootNodesSum += (size != nil) ? size : 0
		roots
	end
	def allRootNodesLabels()
		allRootNodesSorted = @allRootNodes.sort{|a,b| a.xpath("@label").text().downcase <=> b.xpath("@label").text().downcase}
		allRootNodesSorted.map {|n|
		   "<span class='mmRootNodeLink' mapFile='" + @file + "' href='/m?f=" + @file + "&themeBlockX=#{n.xpath("@x").text()}&themeBlockY=#{n.xpath("@y").text()}&themeBlockZ=0.5'>#{n.xpath("@label").text()}</span>"
		}
	end
	def allRootNodesLabelsWithColumns()
		columns = 12
		labels = self.allRootNodesLabels()
		division = labels.size.divmod(columns)
		columnsHeight = division[0] + 1
		remainder = division[1]
		array = labels + [""]*(columns - remainder)
		arraySliced = array.each_slice(columnsHeight).to_a
		if labels.size() > 0
		   i = 1
		   table = "<table class='rootNodes'>"
		   columnsHeight.times.to_a.each{|col|
		      table += "<tr>"
		      arraySliced.each{|a|
		         rootNodeIndex = ""
		         rootNodeIndex = "<span style='font-size:8px'>" + i.to_s + "</span>" if a.size > col && !a[col].nil? && a[col].to_s.length > 0
		         table += "<td style='width:#{100/columns}%;' rootNodeIndex='#{i.to_s}'>" + (a[col] if a.size > col).to_s + rootNodeIndex + "</td>"
		         i = i + 1
		      }
		      table += "</tr>"
		   }
		   table += "</table>"
		   table
		else
		   ""
		end
	end
	def countAllLinks()
		size = @wrappedLinks.wrappedLinksList.size()
		@mapTable.allLinksSum += (size != nil) ? size : 0
		size
	end
	def getNodePositionForLabel(label)
		x = nil
		y = nil
		@xml.xpath("//child/@label").each { |node|
		   line = node.value
		   if line == label
		      nP = node.parent
		      x = nP["x"].to_f
		      y = nP["y"].to_f
		      break
		   end
		}
		raise "ERROR: No coordinates for Node Label found" if x.nil? || y.nil?
		return x, y
	end
	def findThemesPosition()
		@xml.xpath("//child/@label").each { |node|
		   line = node.value
		   if /thZ*ms:.*/ === line
		      nP = node.parent
		      #сохраняем блоки тем
		      @db.execute "insert into themeBlocks(x, y, width, height) values(#{nP["x"].to_f}, #{nP["y"].to_f}, #{nP["width"].to_f}, #{nP["height"].to_f})"
		      themeBlockId = @db.last_insert_row_id
		      @db.execute "insert into themeBlocksAndMaps(tBId, mId) values(#{themeBlockId}, #{@mapDbId})"
		      themesNames = nP["label"].gsub(/thZ*ms:/,"").split(",").map {|tN| tN.strip}
		      #сохраняем найденные темы
		      themesNames.each {|t|
		         tId = nil
		         @db.execute("select * from themes where name = '#{t}'") { |row| tId = row[0]}
		         if tId == nil
		            @db.execute "insert into themes(name) values('#{t}')"
		            themeId = @db.last_insert_row_id
		            @db.execute "insert into themeBlocksAndThemes(tBId, tId) values(#{themeBlockId}, #{themeId})"
		         else
		            @db.execute "insert into themeBlocksAndThemes(tBId, tId) values(#{themeBlockId}, #{tId})"
		         end
		      }
		   end
		}
	end
	def prepareThemes()
		findThemesPosition()
		@themes = Hash.new()
		line = `grep -R 'thZ*ms:' "#{@file}"`
		line = line.scan(/thZ*ms:(.*)\" /)
		allFoundThemesCases = []
		line.each {|l|
		   l.each {|ll|
		      ll = ll.strip
		      ll = ll.split(", ")
		      allFoundThemesCases = allFoundThemesCases + ll
		   }
		}
		allFoundThemesCasesUnique = allFoundThemesCases.uniq
		allFoundThemesCasesUnique.each {|t| @themes[t] = 0}
		allFoundThemesCases.each {|t| @themes[t] = @themes[t] + 1}
	end
	def self.isMM(file)
		extn = File.extname(file)
		/\.vue/ === extn
	end
	def getLeafReadPagesInBook()
		(@leafReadPagesInBook == 0) ? "" : @leafReadPagesInBook.to_s
	end
	def getReadPagesInBook()
		(@readPagesInBook == 0) ? "" : @readPagesInBook.to_s
	end
	def getPagesInBook()
		(@pagesInBook == 0) ? "" : @pagesInBook.to_s
	end
	def listThemeBlocksForThemeAndMap(mapId, themeId)
		themeBlocks = []
		query = "select themeBlocks.id, themeBlocks.x, themeBlocks.y, themeBlocks.width, themeBlocks.height " \
		"from maps, themes, themeBlocks, themeBlocksAndThemes, themeBlocksAndMaps " \
		"where " \
		"maps.id = themeBlocksAndMaps.mId and " \
		"themes.id = themeBlocksAndThemes.tId and " \
		"themeBlocks.id = themeBlocksAndThemes.tBId and " \
		"themeBlocksAndThemes.tBId = themeBlocksAndMaps.tBId and " \
		"maps.id = #{mapId} and " \
		"themes.id = #{themeId} " \
		"order by themeBlocks.x asc"
		@db.execute(query) { |row|
		   themeBlock = ThemeBlock.new(nil, nil, row[0], row[1], row[2], row[3], row[4])
		   themeBlock.conf = @conf
		   themeBlocks << themeBlock
		}
		return themeBlocks
	end
	def listThemeBlocksForTheme(themeId)
		listThemeBlocksForThemeAndMap(@mapDbId, themeId)
	end
	def themesAndBlocksTableLine(allTableThemes)
		line = ""
		allTableThemes.each{|t|
		   themeBlocks = listThemeBlocksForTheme(t[0])
		   if themeBlocks.size > 0
		      line += "<td>"
		      line += themeBlocks.map { |tB|
		         x = tB.x + tB.width/2
		         y = tB.y + tB.height/2
		         "<span class='mmThemeLink' href='/m?f=" + @file + "&themeBlockX=#{x.to_s}&themeBlockY=#{y.to_s}&themeBlockZ=0.3'>#{tB.dbId.to_s}</span>"
		      }.join(", ")
		      line += "</td>\n"
		   else
		      line += "<td></td>"
		   end
		}
		return line
	end
	def getThemes()
		#-
	end
	def getThemeBlocks()
		#-
	end
end
class MMWrappedLink
	attr_accessor :xml, :nodeIdStart, :nodeIdEnd, :label
	def initialize(xml, nodeIdStart, nodeIdEnd)
		@xml = xml
		@nodeIdStart = nodeIdStart
		@nodeIdEnd = nodeIdEnd
		@label = @xml.xpath("@label").text()
	end
end
class MMWrappedLinks
	   attr_accessor :linksXml, :wrappedLinksList
	   def initialize(linksXml)
	   	      @linksXml = linksXml
	   	      @wrappedLinksList = []
	   	      @linksXml.each { |link|
	   	         if !link.at_xpath("ID1").nil? &&
	   	            link.at_xpath("ID1").text.length > 0
	   	            id1 = link.at_xpath("ID1").text.to_i
	   	         else
	   	            id1 = nil
	   	         end
	   	         if !link.at_xpath("ID2").nil? &&
	   	            link.at_xpath("ID2").text.length > 0
	   	            id2 = link.at_xpath("ID2").text.to_i
	   	         else
	   	            id2 = nil
	   	         end
	   	         mmWLink = MMWrappedLink.new(link, id1, id2)
	   	         @wrappedLinksList << mmWLink
	   	      }
	   end
	   def selectAnyLinksConnectedToNode(nodeId)
	   	@wrappedLinksList.select { |link|
	   	   link.nodeIdStart == nodeId || link.nodeIdEnd == nodeId
	   	}
	   end
	   def selectAnyNodesConnectedToNode(nodeId)
	   	connectedLinks = selectAnyLinksConnectedToNode(nodeId)
	   	nodeIds = self.class.getAllNodeIdsFromLinksList(connectedLinks)
	   	nodeIds - [nodeId]
	   end
	   def self.getAllNodeIdsFromLinksList(links)
	   	connectedNodesIds = []
	   	links.each { |link|
	   	   connectedNodesIds << link.nodeIdStart
	   	   connectedNodesIds << link.nodeIdEnd
	   	}
	   	connectedNodesIds = connectedNodesIds.uniq
	   	connectedNodesIds
	   end
end
require 'fileutils'
require 'uri'
require 'neo4j-core'
require_relative 'classes'
class MMInternalConf
	   attr_accessor :confRootNodeXml, :confComment
	   def initialize()
	   	@confComment = ""
	   end
	   def assemble(file, neo4jHelper)
	   	query = "match (n {label: 'conf'})--(conf {label: 'confComment'})--(value) where n.file = '#{URI.escape(file)}' return value.label as conf_comment"
	   	response = neo4jHelper.session.query(query)
	   	@confComment = URI.unescape(response.first[:conf_comment]) if !response.first.nil?
	   end
end
class ShowMMTable
	attr_accessor :conf, :filePath, :themeBlockX, :themeBlockY, :themeBlockZ, :allForTheme, :goalNodeLabel, :listAllNodesInAllBlocksForTheme, :repoPath, :mt, :neo4jHelper, :showStartTime, :rebuildNeo4j, :mapsShowLimit
	def initialize(conf)
		@conf = conf
		@repoPath = @conf.vals["repoPath"]
		@showStartTime = Time.now
	end
	def show()
		if !@filePath.nil? && ( @themeBlockX == nil || @themeBlockY == nil || @themeBlockZ == nil) && @goalNodeLabel.nil?
		   command = 'cd "' + @conf.vals["repoPath"] + '"; '
		   command += '"' + @conf.vals["javaPath"] + '" -jar '
		   command += '"' + @conf.vals["vuePath"] + '" '
		   command += '"' + @filePath + '" & '
		   system(command)
		elsif !@filePath.nil? && @themeBlockX != nil && @themeBlockY != nil && @themeBlockZ != nil && @goalNodeLabel.nil?
		   command = 'cd "' + @conf.vals["repoPath"] + '"; '
		   command += '"' + @conf.vals["javaPath"] + '" -jar '
		   command += '"' + @conf.vals["vuePath"] + '" '
		   command += " -X#{@themeBlockX} -Y#{@themeBlockY} -Z#{@themeBlockZ} "
		   command += '"' + @filePath + '" & '
		   system(command)
		elsif !@filePath.nil? && ( @themeBlockX == nil || @themeBlockY == nil || @themeBlockZ == nil) && !@goalNodeLabel.nil?
		   openMMOnCoordinatesOfNodeByLabel()
		   return
		else
		   @neo4jHelper = Neo4jHelper.new(@conf)
		   @neo4jHelper.rebuildNeo4j = @rebuildNeo4j
		   @neo4jHelper.stopDB()
		   @neo4jHelper.deleteDB() if @neo4jHelper.rebuildNeo4j == "true"
		   @neo4jHelper.startDB()
		   @neo4jHelper.createSession()
		   @neo4jHelper.createIndexes()
		   self.prepareMMTable()
		   self.showMMTable()
		end
	end
	def openMMOnCoordinatesOfNodeByLabel()
		goalFileContent = File.read(filePath).gsub(/^<!--.*-->$/,'')
		goalXml = Nokogiri::XML(goalFileContent) { |config| }
		x = nil
		y = nil
		goalXml.xpath("//child/@label").each { |node|
		   line = node.value
		   if line.gsub("\n"," ") == goalNodeLabel
		      nP = node.parent
		      x = nP["x"].to_f
		      y = nP["y"].to_f
		      break
		   end
		}
		raise "ERROR: No coordinates for Node Label found" if x.nil? || y.nil?
		   command = 'cd "' + @conf.vals["repoPath"] + '"; '
		   command += '"' + @conf.vals["javaPath"] + '" -jar '
		   command += '"' + @conf.vals["vuePath"] + '" '
		   command += ' -X#{x.to_s} -Y#{y.to_s} -Z0.7 '
		   command += '"' + @filePath + '" & '
		   system(command)
	end
	def prepareMMTable()
		all_files = Dir.glob(repoPath+'**/*').select { |fn|
		   File.file? fn
		}
		@mt = MM_Table.new(@conf)
		@mt.neo4jHelper = @neo4jHelper
		i = 0
		maps = all_files.select { |f| MM.isMM(f)}
		maps = maps.take(@mapsShowLimit.to_i) if !@mapsShowLimit.nil?
		maps.each{ |m|
		   mm = MM.new(m, @mt, @conf)
		   @mt.allMaps[mm.fileName] = mm
		   p "Map work time: " + (Time.now - @showStartTime).to_s
		}
		p "Full show work time: " + (Time.now - @showStartTime).to_s
		@mt.prepare
	end
	def pageStyle()
		"<style type='text/css'>\n" \
		"#mmaps {border-collapse:collapse;width:2800px; margin: 10px 0 0 0;}\n" \
		"body > table {border: 1px solid black;}\n" \
		"body > table td, body > table th {border: 1px solid black;}\n" \
		"td, th {padding: 0;font-size:14px;}\n" \
		"table.rootNodes {border-collapse:collapse;border-style:hidden;margin:0;padding:0;width:1300px;}\n" \
		"table.rootNodes td {border: 1px solid black; padding:0;font-size:9px}\n" \
		"table.rootNodes a {text-decoration:none;color: black;}\n" \
		".mmFileLink {color:#0000ff;text-decoration:underline;cursor:pointer;}\n" \
		".mmThemeLink {color:#0000ff;text-decoration:underline;cursor:pointer;}\n" \
		".mmRootNodeLink {color:black;text-decoration:none;font-weight:bold;cursor:pointer;font-size:9px}\n" \
		".plansThemeLink {color:#0000ff;text-decoration:underline;cursor:pointer;}\n" \
		".mmEditTimeline {color:#0000ff;text-decoration:none;cursor:pointer;}\n" \
		"#editTime {width: 50px;}\n" \
		"#nodesNumber {width: 30px;}\n" \
		"#linksNumber {width: 30px;}\n" \
		"</style>\n"
	end
	def pageJSScripts()
		"<script src='" + @conf.vals["jsQueryPath"] + "'></script>" \
		"<script src='" + @conf.vals["jsScriptsPath"] + "'></script>" \
		"<script>" \
		"</script>\n"
	end
	def showMMTable()
		page = "<body>"
		page += ThemeBlock.openNewTab(allForTheme, mt) if !allForTheme.nil? && allForTheme != ""
		page += self.pageStyle()
		page += self.pageJSScripts()
		page += "<table id='mmaps'>\n"
		page += self.mmTableHeaderLine()
		maps = @mt.allMaps
		maps.each_with_index { |(k,v),index|
		   page += self.mmTableLine(k, v, index)
		}
		page += self.mmTableBottomLine()
		page += "</table>\n"
		page += "</br><br>\n"
		self.questions(page)
		self.spheres(page)
		self.themes(page)
		self.blocks(page)
		page += "</body>\n"
		@neo4jHelper.stopDB()
		@neo4jHelper.startDB()
		@neo4jHelper.session = nil
		page
	end
	def mmTableHeaderLine()
		line = "<tr>"
		line += "<th id='mapNumber'></th>"
		line += "<th id='mapName'></th>"
		line += "<th id='nodesNumber'>n</th>"
		line += "<th id='linksNumber'>l</th>"
		line += "<th id='directory' style='width:100px'></th>"
		line += "<th id='pagesInBookCountNumber'>стр</th>"
		line += "<th id='readPagesInBookCountNumber'>ч</th>"
		line += "<th id='leafReadPagesInBookCountNumber'>л</th>"
		line += "<th id='nonReadPagesNumber'></th>"
		line += "<th id='editTime'></th>"
		#line += "#{@mt.themesTableHeader()}"
		line += "<th id='commentsCol'></th>"
		line += "<th></th>"
		line += "<th></th>"
		line += "<th>rts</th>"
		line += "<th></th>"
		line += "<th></th>"
		line += "</tr>\n"
		line
	end
	def mmTableBottomLine()
		line = "<tr>"
		line += "<td></td>"
		line += "<td></td>"
		line += "<td style='font-size:9px;'>#{@mt.allNodesSum.to_s}</td>"
		line += "<td style='font-size:9px;'>#{@mt.allLinksSum.to_s}</td>"
		line += "<td></td>"
		line += "<td style='font-size:9px;'>#{@mt.pagesInBooksSum.to_s}</td>"
		line += "<td style='font-size:9px;'>#{@mt.readPagesInBooksSum.to_s}</td>"
		line += "<td style='font-size:9px;'>#{@mt.leafReadPagesInBooksSum.to_s}</td>"
		line += "<td></td>"
		line += "<td></td>"
		#line += "#{@mt.themesTableHeader()}"
		line += "<th></th>"
		line += "<td></td>"
		line += "<td></td>"
		line += "<td style='font-size:9px;'>#{@mt.allRootNodesSum.to_s}</td>"
		line += "<td></td>"
		line += "<td></td>"
		line += "</tr>\n"
		line
	end
	def showPlans()
	
	end
	def mmTableLine(k, v, index)
		tr_style = ""
		tr_style = "background-color: #8AEE95" if v.getReadPagesInBook.to_i >= v.getPagesInBook.to_i && v.getReadPagesInBook.to_i > 0 && v.getPagesInBook.to_i > 0
		tr_style = "background-color: #C1F780" if (v.getReadPagesInBook.to_i + v.getLeafReadPagesInBook().to_i) >= v.getPagesInBook.to_i && v.getReadPagesInBook.to_i < v.getPagesInBook.to_i && v.getPagesInBook.to_i > 0
		nonReadPages = "<td class='nonReadPagesNumber' style='font-size:9px;' id='nonReadPagesInBookCount'>#{(v.getPagesInBook.to_i - v.getReadPagesInBook.to_i - v.getLeafReadPagesInBook().to_i).to_s}</td>"
		line = "<tr class='map' style='#{tr_style}'>"
		line += "<td class='mapNumber' style='font-size:9px;'>#{index+1}</td>"
		line += "<td class='mapName, link1' mapId='#{index+1}'>"+v.link + "</td>"
		line += "<td class='nodesNumber' style='font-size:9px;'>"+v.allNodesCount.to_s + "</td>"
		line += "<td class='linksNumber' style='font-size:9px;'>"+v.allLinksCount.to_s + "</td>"
		line += "<td class='directory' style='font-size:9px;'>" + v.dirPath.sub( @conf.vals["repoPath"],"")+ "</td>"
		line += "<td class='pagesInBookCountNumber' style='font-size:9px;' id='pagesInBookCount'>" + v.getPagesInBook + "</td>"
		line += "<td class='readPagesInBookCountNumber' style='font-size:9px;' id='readPagesInBookCount'>" + v.getReadPagesInBook + "</td>"
		line += "<td class='leafReadPagesInBookCountNumber' style='font-size:9px;' id='leafReadPagesInBookCount'>" + v.getLeafReadPagesInBook + "</td>"
		line += "#{nonReadPages}"
		line += "<td class='editTime' style='font-size:9px;line-height:80%;'><a class='mmEditTimeline' href='mmEditTimeline?mmFileName=#{k}' target='_blank'>" + v.lastEditDate.to_s + "</a></td>"
		#line += v.themesAndBlocksTableLine(@mt.listAllThemesFromDB)
		line += "<td class='commentsCol' style='font-size:9px;width:200px;'>" + v.mmInternalConf.confComment + "</td>"
		line += "<td style='font-size:9px;'>#{index+1}</td>"
		line += "<td>" + v.linkShort+ "</td>"
		line += "<td style='font-size:9px;'>"+v.allRootNodes.size.to_s + "</td>"
		line += "<td class='lastRoots' mapFile='#{v.file}'>"+ "</td>"
		line += "<td style='border-bottom:2px solid black;'>"+v.allRootNodesLabelsWithColumns() + "</td>"
		line += "</tr>" + "\n"
		line
	end
	def questions(page)
	
	end
	def spheres(page)
	
	end
	def themes(page)
	
	end
	def blocks(page)
	
	end
end
class MM_Table
	#allThemes для логов только
	attr_accessor :conf, :allMaps, :allThemes, :db, :allNodesSum, :allRootNodesSum, :allLinksSum, :pagesInBooksSum, :readPagesInBooksSum, :leafReadPagesInBooksSum, :logsPath, :mmTableYamlDumpPath , :neo4jHelper, :rebuildNeo4j
	def initialize(conf)
		@conf = conf
		@allMaps = Hash.new
		@db = SQLite3::Database.new ":memory:"
		@db.execute "create table maps(id integer primary key, name text, path text)"
		@db.execute "create table themes(id integer primary key, name text)"
		@db.execute "create table themeBlocks(id integer primary key, x real, y real, width real, height real)"
		@db.execute "create table themeBlocksAndThemes(id integer primary key, tBId, tId)"
		@db.execute "create table themeBlocksAndMaps(id integer primary key, tBId, mId)"
		@allNodesSum = 0
		@allRootNodesSum = 0
		@allLinksSum = 0
		@pagesInBooksSum = 0
		@readPagesInBooksSum = 0
		@leafReadPagesInBooksSum = 0
		@logsPath = @conf.vals["logsPath"]
		@mmTableYamlDumpPath = @conf.vals["mmTableYamlDumpPath"]
		@mmsLastEditsHash = nil
	end
	def prepare()
		@allThemes = self.listAllThemesFromDB.map {|t| t[1]}
		@allMaps = @allMaps.sort {|a,b| a[1].fileName <=> b[1].fileName }
		@allMaps = Hash[@allMaps.map { |aM| aM}]
		self.compareOldAndNowMMTablesAndSaveLogs
		self.saveToYaml
		self.getMMsLastEdits
	end
	def getAllMaps()
		@allMaps
	end
	def themesTableHeader()
		line = ""
		self.listAllThemesFromDB.each {|t|
		   line += "<th><a href='/m?allForTheme=" + t[1] +"'>"+t[1]+"</a></th>"
		}
		return line
	end
	def saveToYaml()
		puts "start -> saveToYaml"
		tmpTable = self.clone
		tmpTable.db = nil
		tmpTable.neo4jHelper = nil
		tmpTable.allMaps = self.allMaps.clone
		tmpTable.allMaps = Hash[tmpTable.allMaps.map { |k,v|
		   v = v.clone
		   v.mapTable = nil
		   v.db = nil
		   v.xml = nil
		   v.allNodes = nil
		   v.wrappedLinks = nil
		   v.mmInternalConf = nil
		   v.allRootNodes = nil
		   [k, v]
		}]
		file = File.open(@mmTableYamlDumpPath,"w")
		dump = YAML::dump(tmpTable)
		file.write(dump)
		file.close
		puts "end -> saveToYaml"
	end
	def readOldMMTableFromYaml()
		YAML.load_file(@mmTableYamlDumpPath)
	end
	def getMMsLastEdits()
		logFileLines = File.readlines(@logsPath)
		logFileLines.each {|l|
		   @allMaps.each {|k,v|
		      v.lastEditDate = l.split(": ")[0] if l.include?(k)
		   }
		}
	end
	def saveLog(line)
		file = File.open(@logsPath,"a")
		file.puts(Time.new.strftime("%Y-%m-%d %H:%M:%S") + ": "+ line)
		file.close
	end
	def compareOldAndNowMMTablesAndSaveLogs()
		puts "start -> compareOldAndNowMMTablesAndSaveLogs"
		old_mm_table = self.readOldMMTableFromYaml
		oMT = old_mm_table.allMaps
		o = Hash.new
		oMT.each {|i|
		   o[i[0]] = i[1]
		}
		#p oMT.inspect
		@allMaps.each {|k,v|
		   if o[k] != nil
		      #p v.allNodesCount
		      self.saveLog("pagesInBook: #{o[k].pagesInBook}, #{v.pagesInBook} : #{k}") if o[k].pagesInBook != v.pagesInBook
		      self.saveLog("readPagesInBook: #{o[k].readPagesInBook}, #{v.readPagesInBook} : #{k}") if o[k].readPagesInBook != v.readPagesInBook
		      self.saveLog("leafReadPagesInBook: #{o[k].leafReadPagesInBook}, #{v.leafReadPagesInBook} : #{k}") if o[k].leafReadPagesInBook != v.leafReadPagesInBook
		      self.saveLog("themes: #{o[k].themes.inspect}| #{v.themes.inspect} : #{k}") if o[k].themes != v.themes
		      self.saveLog("nodes: #{o[k].allNodesCount.inspect}| #{v.allNodesCount.inspect} : #{k}") if o[k].allNodesCount != v.allNodesCount
		      self.saveLog("links: #{o[k].allLinksCount.inspect}| #{v.allLinksCount.inspect} : #{k}") if o[k].allLinksCount != v.allLinksCount
		   else
		      self.saveLog("added map #{k}")
		   end
		}
		o.each {|k,v|
		   if @allMaps.keys.include?(k) == false
		      self.saveLog("removed map #{k}")
		   end
		}
		puts "end -> compareOldAndNowMMTablesAndSaveLogs"
	end
	def listAllThemesFromDB()
		@db.execute "select * from themes"
	end
	def listAllThemeBlocksFromDB()
		@db.execute "select * from themeBlocks"
	end
	def listBlocksAndMapsForTheme(themeName)
		mapsAndThemeBlocks = []
		query = "select maps.name, maps.path, themeBlocks.id, themeBlocks.x, themeBlocks.y, themeBlocks.width, themeBlocks.height " \
		"from maps, themes, themeBlocks, themeBlocksAndThemes, themeBlocksAndMaps " \
		"where " \
		"maps.id = themeBlocksAndMaps.mId and " \
		"themes.id = themeBlocksAndThemes.tId and " \
		"themeBlocks.id = themeBlocksAndThemes.tBId and " \
		"themeBlocksAndThemes.tBId = themeBlocksAndMaps.tBId and " \
		"themes.name = '#{themeName}' " \
		"order by themeBlocks.x asc"
		@db.execute(query) { |row|
		   mapsAndThemeBlocks << [row[0], row[1], row[2], themeName, row[3], row[4], row[5], row[6]]
		}
		return mapsAndThemeBlocks
	end
end
class LastRoots
	attr_accessor :mapsLastRoots
end
class Theme
	attr_accessor :themeName, :db
	def initialize(themeName, db)
		@themeName = themeName
		@db = db
	end
	def getMaps()
		#-
	end
	def getThemeBlocks()
		#-
	end
end
class ThemeBlock
	attr_accessor :conf, :mm, :theme, :dbId, :x, :y, :width, :height
	def initialize(mm, theme, dbId, x, y, width, height)
		@mm = mm
		@theme = theme
		@dbId = dbId
		@x = x
		@y = y
		@width = width
		@height = height
	end
	def getMaps()
		#-
	end
	def getThemeBlocks()
		#-
	end
	def self.openMapsForTheme(allForTheme, mt)
		mt.listBlocksAndMapsForTheme(allForTheme).each {|mapAndBlock|
		   x = (mapAndBlock[4].to_i + mapAndBlock[6].to_i/2)
		   y = (mapAndBlock[7].to_i + mapAndBlock[8].to_i/2)
		   #system('"' +@conf.vals["repoPath"] + '"; "' + @conf.vals["javaPath"] + '" -jar "' + @conf.vals["vuePath"] + '" -X#{x.to_s} -Y#{y.to_s} -Z0.7 #{mapAndBlock[1]} & ')
		   command = 'cd "' + @conf.vals["repoPath"] + '"; '
		   command += '"' + @conf.vals["javaPath"] + '" -jar '
		   command += '"' + @conf.vals["vuePath"] + '" '
		   command += ' -X#{x.to_s} -Y#{y.to_s} -Z0.7 '
		   command += '"' + mapAndBlock[1] + '" & '
		   system(command)
		}
	end
	def self.openNewTab(allForTheme, mt)
		"<script type='text/javascript'>\n" \
		"var url = '/m?listAllNodesInAllBlocksForTheme=#{allForTheme}';\n" \
		"var win = window.open(url,'_blank');\n" \
		"win.focus();\n" \
		"</script>\n"
	end
	def self.listAllPlansInAllFiles(listAllNodesInAllBlocksForTheme, mt)
		line = listAllNodesInAllBlocksForTheme + "\n"
		bMT = mt.listBlocksAndMapsForTheme(listAllNodesInAllBlocksForTheme)
		counter = 0
		if bMT.size > 0
		   line += "<table>\n"
		   bMT.each { |node|
		      mapName = node[0]
		      map = mt.allMaps[mapName]
		      blockId = node[2]
		      x = node[4].to_i
		      y = node[5].to_i
		      w = node[6].to_i
		      h = node[7].to_i
		      if !map.nil?
		         nodes = map.xml.xpath("//child[@xsi:type='node']")
		         nodes.each {|n|
		            nx = n.attribute("x").value.to_i
		            ny = n.attribute("y").value.to_i
		            #находим все ноды внутри текущего блока
		            if x < nx && y < ny && (x+w) > nx && (y+h) > ny
		               label = n.attribute("label").value
		               link = "<span class='plansThemeLink' href='/m?f=" + map.file + "&themeBlockX=#{nx.to_s}&themeBlockY=#{ny.to_s}&themeBlockZ=1'>" + blockId.to_s + "</span>"
		               #если тема "plans", то добавляем подкрашивание задачам в соответствие с статусом
		               if listAllNodesInAllBlocksForTheme == "plans"
		                  if label.start_with?("> ") || label.start_with?("+ ")
		                     counter += 1
		                     bgColor = "f1cd0f" if label.start_with?("> ")
		                     bgColor = "2ecc71" if label.start_with?("+ ")
		                     line += "<tr>" \
		                     "<td>"+counter.to_s+"</td>" \
		                     "<td>"+mapName+"</td>" \
		                     "<td>"+link+"</td>" \
		                     "<td bgcolor='#{bgColor}'>"+label.sub(/^> /,"").sub(/^\+ /,"")+"</td>" \
		                     "</tr>\n"
		                  end
		               else
		                  counter += 1
		                  #для всех остальных тем
		                  line += "<tr>" \
		                  "<td>"+counter.to_s+"</td>" \
		                  "<td>"+mapName+"</td>" \
		                  "<td>"+link+"</td>" \
		                  "<td>"+label+"</td>" \
		                  "</tr>\n"
		               end
		            end
		         }
		      end
		   }
		   line += "</table>\n"
		end
		line
	end
end
class Neo4jHelper
	attr_accessor :conf, :neo4jPath, :neo4jUrl, :neo4jUser, :neo4jPass, :session, :rebuildNeo4j, :dataImportCounter, :dataImportDBRebootStep
	def initialize(conf)
		@conf = conf
		@neo4jUrl = @conf.vals["neo4jUrl"]
		@neo4jUser = @conf.vals["neo4jUser"]
		@neo4jPass = @conf.vals["neo4jPass"]
		@neo4jPath = @conf.vals["neo4jPath"]
		@dataImportDBRebootStep = 150
		@dataImportCounter = 0
	end
	def createSession()
		@session = Neo4j::Session.open(:server_db, @neo4jUrl,
		   basic_auth: {username: @neo4jUser, password: @neo4jPass},
		   initialize: {request: { open_timeout: 5, timeout: 1500 }})
	end
	def dataImportQuery(query)
		p "dataImportQuery(query): " + @dataImportCounter.to_s
		@session.query(query)
		@dataImportCounter += 1
		if @dataImportCounter == @dataImportDBRebootStep
		   p "REBOOT DB!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
		   stopDB()
		   startDB()
		   @dataImportCounter = 0
		end
	end
	def startDB()
		system('"' + @neo4jPath + 'bin/neo4j" start')
		sleep(10)
	end
	def stopDB()
		system('"' + @neo4jPath + 'bin/neo4j" stop')
		sleep(10)
		system("for KILLPD in $(ps axu | grep -e java | grep -e neo4j | grep -v grep | awk '{ print $2 }') ; do kill -9 $KILLPD; done")
	end
	def deleteDB()
		system('rm -rf "' + @neo4jPath + 'data/graph.db"')
	end
	def dropIndexes()
		@session.query("drop index on :VueNode(vueId)")
		@session.query("drop index on :VueNode(label)")
		@session.query("drop index on :VueNode(file)")
		@session.query("drop index on :VueNode(fontSize)")
		@session.query("drop index on :VueNode(fillColor)")
		@session.query("drop index on :VueRelation(file)")
		@session.query("drop index on :VueRelation(label)")
		@session.query("MATCH (n) DETACH DELETE n")
	end
	def createIndexes()
		@session.query("create index on :VueNode(vueId)")
		@session.query("create index on :VueNode(label)")
		@session.query("create index on :VueNode(file)")
		@session.query("create index on :VueNode(fontSize)")
		@session.query("create index on :VueNode(fillColor)")
		@session.query("create index on :VueRelation(file)")
		@session.query("create index on :VueRelation(label)")
	end
end

# vim: tabstop=4 softtabstop=0 noexpandtab shiftwidth=4 number
