module Kuma
  class CLI
    attr_reader :options, :config_store

    def initialize
      @options = {}
      @config_store = ConfigStore.new
    end

    def run(args = ARGV)
      @options, paths = Options.new.parse(args)
      act_on_options

      runner = Runner.new(@options, @config_store)
      trap_interrupt(runner)
      all_passed = runner.run(paths)
      display_error_summary(runner.errors)

      all_passed && !runner.aborting? ? 0 : 1
    rescue => e
      $stderr.puts e.message
      $stderr.puts e.backtrace
      return 1
    end

    def trap_interrupt(runner)
      Signal.trap('INT') do
        exit!(1) if runner.aborting?
        runner.abort
        $stderr.puts
        $stderr.puts 'Exiting... Interrupt again to exit immediately.'
      end
    end

    private

    def act_on_options
      handle_exiting_options
      # ConfigLoader.debug = @options[:debug]
      # ConfigLoader.auto_gen_config = @options[:auto_gen_config]
      @config_store.options_config = @options[:config] if @options[:config]
    end

    def handle_exiting_options
      return unless Options::EXITING_OPTIONS.any? { |o| @options.key? o }
      
      puts RuboCop::Version.version(false) if @options[:version]
      puts RuboCop::Version.version(true) if @options[:verbose_version]
      exit(0)
    end

    def display_error_summary(errors)
    #   return if errors.empty?
    #
    #   plural = errors.count > 1 ? 's' : ''
    #   warn "\n#{errors.count} error#{plural} occurred:".color(:red)
    #
    #   errors.each { |error| warn error }
    #
    #   warn <<-END.strip_indent
    #     Errors are usually caused by RuboCop bugs.
    #     Please, report your problems to RuboCop's issue tracker.
    #     Mention the following information in the issue report:
    #     #{RuboCop::Version.version(true)}
    #   END
    end
  end
end