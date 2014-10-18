module Kuma
  class ConfigStore
    def initialize
      @options_config = nil
      @path_cache = {}
      @object_cache = {}
    end

    def options_config=(options_config)
      loaded_config = ConfigLoader.load_file(options_config)
      @options_config = ConfigLoader.merge_with_default(loaded_config,
                                                        options_config)
    end

    def for(file_or_dir)
      return @options_config if @options_config

      dir = if File.directory?(file_or_dir)
              file_or_dir
            else
              File.dirname(file_or_dir)
            end
      @path_cache[dir] ||= ConfigLoader.configuration_file_for(dir)
      path = @path_cache[dir]
      @object_cache[path] ||= begin
                                print "For #{dir}: " if ConfigLoader.debug?
                                ConfigLoader.configuration_from_file(path)
                              end
    end
  end
end