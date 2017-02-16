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
require 'gruff'
require 'fileutils'
require 'uri'
require 'neo4j-core'

require_relative "classes"

class Conf
	attr_accessor :vals
	def initialize()
	   scriptPath = File.expand_path File.dirname(__FILE__)
	   @vals = {
	      "repoPath" => scriptPath + "/",
	      "javaPath" => "java",
	      "vuePath" => scriptPath + "/VUE.jar",
	      "lastRootsFilePath" => scriptPath + "/lastRoots.yaml",
	      "jsQueryPath" => "js/jquery-2.0.3.min.js",
	      "jsScriptsPath" => "js/scripts.js",
	      "logsPath" => scriptPath + "/logs_mm_table.log",
	      "mmTableYamlDumpPath" => scriptPath + "/mm_table.yaml",
	      "neo4jUrl" => "http://localhost:7474",
	      "neo4jUser" => "neo4j",
	      "neo4jPass" => "neo4j",
	      "neo4jPath" => scriptPath + "/neo4j/" ,
	   }
	end
end
get '/' do
   'Hello!<br><a href="/m">Mind maps table</a><br><a href="/m?mapsShowLimit=5">Mind maps table mapsShowLimit=5</a><br><a href="/m?rebuildNeo4j=true">Mind maps table rebuildNeo4j=true</a>'
end
get '/ajaxRootLinks' do

   conf = Conf.new()

   lastRootsFilePath = conf.vals["lastRootsFilePath"]
   lastRoots = YAML.load_file(lastRootsFilePath)
   lastRoots.mapsLastRoots = {} if lastRoots.mapsLastRoots.nil?

   JSON.dump(lastRoots.mapsLastRoots)

end
get '/ajaxRootLinksSave' do

   conf = Conf.new()
   lastRootsFilePath = conf.vals["lastRootsFilePath"]
   lastRoots = YAML.load_file(lastRootsFilePath)
   lastRoots.mapsLastRoots = {} if lastRoots.mapsLastRoots.nil?

   if !params[:line].nil? and !params[:mapFile].nil?
      line = params[:line]
      mapFile = params[:mapFile]

      #lastRoots = LastRoots.new
      #lastRoots.mapsLastRoots = Hash.new
      lastRoots.mapsLastRoots[mapFile] = [] if lastRoots.mapsLastRoots[mapFile].nil?
      lastRootsNodes = lastRoots.mapsLastRoots[mapFile].last(6)
      lastRootsNodes = lastRootsNodes << line
      lastRootsNodes = lastRootsNodes.reverse.uniq.reverse
      lastRoots.mapsLastRoots[mapFile] = lastRootsNodes

      file = File.open(lastRootsFilePath,"w")
      dump = YAML::dump(lastRoots)
      file.write(dump)
      file.close
   end

   JSON.dump(lastRoots.mapsLastRoots)

end
get '/m' do
   p params
   conf = Conf.new()
   showMMTable = ShowMMTable.new(conf)
   showMMTable.filePath = params[:f]
   showMMTable.themeBlockX = params[:themeBlockX]
   showMMTable.themeBlockY = params[:themeBlockY]
   showMMTable.themeBlockZ = params[:themeBlockZ]
   showMMTable.allForTheme = params[:allForTheme]
   showMMTable.goalNodeLabel = params[:goalNodeLabel]
   showMMTable.rebuildNeo4j = params[:rebuildNeo4j]
   showMMTable.rebuildNeo4j = "true" if params[:rebuildNeo4j].nil?
   showMMTable.mapsShowLimit = params[:mapsShowLimit]
   showMMTable.listAllNodesInAllBlocksForTheme = params[:listAllNodesInAllBlocksForTheme]
   showMMTable.show()
end

# vim: tabstop=4 softtabstop=0 noexpandtab shiftwidth=4 number
