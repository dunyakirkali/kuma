# encoding: utf-8

module Kuma
  class Runner
    attr_reader :errors, :aborting
    alias_method :aborting?, :aborting

    def initialize(options, config_store)
      @options = options
      @config_store = config_store
      @errors = []
      @aborting = false
    end

    def run(paths)
      puts '# Flay'
      puts %x(flay .)
      puts '# Flog'
      puts %x(flog .)
      puts '# Rubocop'
      puts %x(rubocop .)
    end
  end
end