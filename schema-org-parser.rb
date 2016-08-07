#!/usr/bin/env ruby

##
# Schema.org parser
#
# This command fetches web pages from http://schema.org,
# then parses the pages to extract schema names, properties,
# and expected types. Finally, this command outputs the results.
#
# Example:
#
#     $ schema-org-parser.rb Person
#     {"Person"=>
#       {:properties=>
#         [{"additionalName"=>{:expected_types=>["Text"]}},
#          {"address"=>{:expected_types=>["PostalAddress", "Text"]}},
#          {"affiliation"=>{:expected_types=>["Organization"]}},
#          …
#
# Example with output format SQL:
#
#     $ schema-org-parser.rb --output sql Person
#     create table person (
#       additional_name text,
#       address postal_address,
#       affiliation organization,
#       …
#
# This command is a work in progress:
#
#  * It outputs preetty pprit infformation that's usable.
#  * It outputs SQL that is a similar format, but not valid.
#
# Command: schema-org-parser.rb
# Version: 0.5.0
# Created: 2016-08-05
# Updated: 2016-08-07
# License: GPL
# Contact: Joel Parker Henderson (joel@joelparkerhenderson.com)
##

require 'optparse'
require 'ostruct'
require 'pp'
require 'open-uri'
require 'nokogiri'

# Script options.
#
# The user can set these by using command line options,
# which are parsed by the ScriptOptionsManager parser.
#
class ScriptOptions

  OutputFormatList = [:text, :sql]

  attr_accessor \
    :output, 
    :verbose

  def initialize
    self.output = OutputFormatList.first
    self.verbose = false
  end

end

# Script options manager.
#
# Use this class to parse command line options 
# to a new ScriptOption object that is set correctly.
#
class ScriptOptionsManager

  attr_reader :options, :parser

  def self.parse!(args)
    x = self.new
    x.parser.parse!(args)
    x.options
  end

  def options
    @options ||= ScriptOptions.new
  end

  def parser
    @parser ||= OptionParser.new do |o|
      o.banner = "Usage: schema-org-cooker.rb [options]"
      o.separator ""
      o.separator "Specific options:"

      o.on(
	"-o", "--output [FORMAT]", ScriptOptions::OutputFormatList,
	"Output format",
	"Select output format type (text, sql)"
      ) do |x|
	options.output = x
      end

      o.on(
	"-v", "--[no-]verbose",
	"Verbose printing",
      ) do |x|
	options.verbose = x
      end
    end
  end
  
end

module SchemaOrg

  class Term < Hash
  end

  class TermsLoader

    # Load terms.
    #
    # This implementation uses fetch for downloading a web page.
    # If you're doing a lot with this, consider creating a local
    # cache because it will be faster and use no bandwidth.
    #
    # @return [List] terms
    #
    def self.load
      parse(fetch())
    end

    # Fetch the full list of terms.
    #
    # @return [String] Schema.org full terms HTML page
    #
    def self.fetch()
      open("http://schema.org/docs/full.html")
    end

    # Parse the full list of terms from input HTML to output text set.
    #
    # @param [String] Schema.org full terms HTML page
    # @return [List] term set
    #
    def self.parse(html)
      doc = Nokogiri::HTML(html)
      return doc.xpath("//div[@id='thing_tree']//li//a/@href").map{|attr| attr.value.sub(/^\//,'')}
    end

  end

  class TermLoader

    # Load term.
    #
    # This implementation uses fetch for downloading a web page.
    # If you're doing a lot with this, consider creating a local
    # cache because it will be faster and use no bandwidth.
    #
    # @return [Term] term
    #
    def self.load(term)
      parse(fetch(term))
    end

    # Fetch one schema.org term.
    #
    # @param [String] term keyword
    # @return [String] Schema.org term HTML page
    #
    def self.fetch(term)
      open("http://schema.org/#{term}")
    end

    # Parse the term from input HTML to output property set.
    #
    # @param [String] Schema.org term HTML page
    # @return [List] property set
    #
    def self.parse(html)
      doc = Nokogiri::HTML(html)
      return doc.xpath("//table[@class='definition-table']/tbody/tr").map{|tr| parse_tr(tr)}
    end

    # Parse an element row.
    #
    # @param [Element] element, typically the tbody tr
    # @return [List<String => Set>] set of property key to expected types
    #
    def self.parse_tr(elem)
      property_key = parse_to_property_key(elem)
      expected_types = parse_to_expected_types(elem)
      return { property_key => { :expected_types => expected_types }}
    end

    # Parse an element to a property key.
    #
    # @param [Element] element, typically the tbody tr.
    # @return [String] property key
    #
    def self.parse_to_property_key(elem)
      return elem.xpath("th/code").text    
    end

    # Parse to expected types
    #
    # @param [Element] element, typically the tbody tr
    # @return [List] expected types
    #
    def self.parse_to_expected_types(elem)
      text = elem.xpath("td[@class='prop-ect']//text()")
      expected_types = text.map{|x| x.text.to_s.gsub(/\s/,'')}.select{|x| x =~ /[A-Z]/}
      return expected_types
    end

  end

end

class OutputFormatSQL

  def self.output(term_info_list)
    term_info_list.map{|o| term_info(o)}.join
  end

  def self.output_term_info(term_info)
    term = term_info.keys.first
    "create table " + table_name(term) + " (\n" + columns(term_info[term][:properties]) + "\n);"
  end

  def self.table_name(term)
    term.underscore
  end

  def self.column_name(property_key)
    property_key.underscore
  end

  def self.column_type(expected_types)
    expected_types.first.underscore
  end

  def self.columns(properties)
    s = []
    properties.each{|property|
      expected_types = property.values.first[:expected_types]
      if (!expected_types.empty?) 
        s << "  #{column_name(property.keys.first)} #{column_type(expected_types)}"
      end
    }
    return s.join(",\n")
  end

end

## Extensions

class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

## Main

options = ScriptOptionsManager.parse!(ARGV)
ARGV.each{|arg|
  term = arg
  term_info = { term => { :properties => SchemaOrg::TermLoader.load(term) }}
  case options.output
  when :sql
    puts OutputFormatSQL.output_term_info(term_info)
  else
    pp term_info
  end
}
