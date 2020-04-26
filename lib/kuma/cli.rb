require 'thor'

module Kuma
  class CLI < Thor
    desc "smell PATH", "find smelly code in PATH"
    def smell(path)
      puts %x(flay #{path})
      puts %x(flog #{path})
      puts %x(rubocop #{path})
    end
  end
end