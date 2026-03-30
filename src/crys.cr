require "./options"
require "./generator"
require "./runtime"

module Crys
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
end
