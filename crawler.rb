#!/usr/bin/ruby -Ku

$LOAD_PATH << "lib"

require "lib/crawler"

require "ostruct"
require "yaml"

opts = OpenStruct.new({
  :file => "config.yaml"
})

begin
  count = 6
  Crawler.run(opts.file, ARGV[0])
rescue
  warn $!
  warn "Connection closed... will retry after #{count} sec."
  sleep count
  count *= 2
  retry
end