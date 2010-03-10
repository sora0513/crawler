#!/usr/bin/ruby -Ku

$LOAD_PATH << "lib"

require "crawler/core"

module Crawler
  class << self
    def run(config, arg_uri=nil)
      core = Core.new(config, arg_uri)
      core.crawl
    end
  end
end
