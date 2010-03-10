#!/usr/bin/ruby -Ku

require "rubygems"
require "mechanize"

require "ostruct"
require "logger"
require "yaml"

require "ruby-debug"

module Crawler
  class CrawlerListener
    def notify_begin
    end
    def pre_request
    end
    def notify_response(result)
      puts %Q{#{result[:method]} #{result[:uri]} #{result[:query] ? result[:query].inspect : ""}}
    end
    def post_request
    end
    def notify_end
    end
  end

  class Core

    PRODUCT = "Crawler 0.1"

    attr_accessor :listener, :results, :bad_results, :excludes
    attr_reader :config

    def initialize(config, arg_uri=nil, listener=CrawlerListener.new)
      @listener = listener
      @excludes = /\.(jpg|png|gif|js|css|ico|)$/i
      @own_excludes = /\#$/i

      if config.is_a? Hash
        @config = OpenStruct.new({
          "general" => {},
        }.merge(config))
      else
        @config_file = config.to_s
        reload_config
      end

      @logger = Logger.new(@config.general["log"] || $stdout)
      @logger.level = eval("Logger::#{@config.general['log_level'].upcase}") if @config.general['log_level']
      @logger.progname = File.basename($0)

      @uri = (arg_uri.nil?) ? @config.general["host"] : arg_uri
      @username = @config.general["username"]
      @password = @config.general["password"]
    end

    def reload_config
      raise "Passed not filename but Hash to new." unless @config_file
      @config = OpenStruct.new(File.open(@config_file) {|f| YAML.load(f) })
    end

    def crawl
      uri = @uri
      raise if uri.nil? or uri.empty?
      @uris = {}
      @results = []
      @bad_results = []
      @root_uri = uri
      @listener.notify_begin
      crawl_r(uri.is_a?(URI) ? uri : URI.parse(uri))
      @listener.notify_end
      true
    end

  private
    def create_agent
      agent = Mechanize.new
      @user_agent = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; #{PRODUCT})"
      agent.user_agent = @user_agent
      agent.auth(@username, @password)
      agent
    end

    def http_request(method, uri, query={})
      agent = create_agent
      begin
        if method == "GET"
          page = agent.get(uri, query)
        elsif method == "POST"
          page = agent.post(uri, query)
        end
        #agent.page.encoding = "UTF-8"
        page
      rescue => ex
        result = {
          :method => method,
          :uri => uri,
          :query => query,
          :error => ex
        }
        @bad_results << result
        puts %Q{bad request = #{uri} : #{ex}}
        log %Q{bad request = #{uri} : #{ex}}
        nil
      end
    end

    def get_links(page)
      links = []
      (page.links + page.meta + page.frames + page.iframes).each do |link|
        begin
          if link.uri
            links << page.uri + link.uri
          end
        rescue URI::InvalidURIError => ex
        end
      end

      imgsrcs = page.root.search("img").map{|e| e["src"]}
      imgsrcs.each do |uri|
        links << page.uri + uri
      end
      links
    end

    def child_uri?(uri)
      uri.to_s.index(@root_uri.gsub(/\/[^\/]*?$/, "/")) == 0 and uri.to_s.index(@root_uri.gsub(/^http:\/\//, ""))
    end

    def crawl_r(uri, referer=nil, query=nil, method="GET")
      return false unless child_uri?(uri)
      return false if uri.to_s =~ @excludes
      @listener.pre_request
      page = http_request(method, uri, query)
      @listener.post_request
      result = {
        :method => method,
        :uri => uri,
        :query => query,
        :referer => referer,
        :user_agent => @user_agent
      }
      if page
        result.update({
          :code => page.code,
          :body => page.body,
          :header => page.response
        })
      end
      @listener.notify_response(result)
      @results << result
      if page.is_a?(Mechanize::Page)
        links = get_links(page)
        links.each do |u|
          unless @uris.has_key?(u.to_s)
            @uris[u.to_s] = true
            crawl_r(u, uri)
          end
        end
        page.forms.each do |f|
          next if page.uri.to_s == f.action.to_s
          u = page.uri + f.action
          log %Q{bad request = #{u.to_s} : sharp} if uri.to_s =~ @own_excludes
          next if u.to_s.index("?" + f.request_data)
          k = u.to_s + "?" + f.request_data
          unless @uris.has_key?(k)
            @uris[k] = true
            crawl_r(u, uri, f.build_query, f.method)
          end
        end
      end
      true
    end

    def log(l)
      @logger.info(l)
    end
  end
end