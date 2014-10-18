# encoding: utf-8

require 'fileutils'
require 'tmpdir'
require 'spec_helper'
require 'timeout'

describe Kuma::CLI, :isolated_environment do
  include FileHelper

  let(:cli) { described_class.new }

  before(:each) do
    $stdout = StringIO.new
    $stderr = StringIO.new
    # Kuma::ConfigLoader.debug = false
  end

  after(:each) do
    $stdout = STDOUT
    $stderr = STDERR
  end

  def abs(path)
    File.expand_path(path)
  end

  context 'when interrupted' do
    it 'returns 1' do
      allow_any_instance_of(Kuma::Runner)
        .to receive(:aborting?).and_return(true)
      create_file('example.rb', '# encoding: utf-8')
      expect(cli.run(['example.rb'])).to eq(1)
    end
  end

  describe '#trap_interrupt' do
    let(:runner) { Kuma::Runner.new({}, Kuma::ConfigStore.new) }
    let(:interrupt_handlers) { [] }

    before do
      allow(Signal).to receive(:trap).with('INT') do |&block|
        interrupt_handlers << block
      end
    end

    def interrupt
      interrupt_handlers.each(&:call)
    end

    it 'adds a handler for SIGINT' do
      expect(interrupt_handlers).to be_empty
      cli.trap_interrupt(runner)
      expect(interrupt_handlers.size).to eq(1)
    end

    context 'with SIGINT once' do
      it 'aborts processing' do
        cli.trap_interrupt(runner)
        expect(runner).to receive(:abort)
        interrupt
      end

      it 'does not exit immediately' do
        cli.trap_interrupt(runner)
        expect_any_instance_of(Object).not_to receive(:exit)
        expect_any_instance_of(Object).not_to receive(:exit!)
        interrupt
      end
    end

    context 'with SIGINT twice' do
      it 'exits immediately' do
        cli.trap_interrupt(runner)
        expect_any_instance_of(Object).to receive(:exit!).with(1)
        interrupt
        interrupt
      end
    end
  end

  it 'checks a given correct file and returns 0' do
    create_file('example.rb', ['# encoding: utf-8',
                               'x = 0',
                               'puts x'])
    expect(cli.run(['--format', 'simple', 'example.rb'])).to eq(0)
    expect($stdout.string)
      .to eq(['',
              '1 file inspected, no offenses detected',
              ''].join("\n"))
  end

  it 'checks a given file with faults and returns 1' do
    create_file('example.rb', ['# encoding: utf-8',
                               'x = 0 ',
                               'puts x'])
    expect(cli.run(['--format', 'simple', 'example.rb'])).to eq(1)
    expect($stdout.string)
      .to eq ['== example.rb ==',
              'C:  2:  6: Trailing whitespace detected.',
              '',
              '1 file inspected, 1 offense detected',
              ''].join("\n")
  end

  it 'registers an offense for a syntax error' do
    create_file('example.rb', ['# encoding: utf-8',
                               'class Test',
                               'en'])
    expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
    expect($stdout.string)
      .to eq(["#{abs('example.rb')}:4:1: E: unexpected " \
              'token $end',
              ''].join("\n"))
  end

  it 'registers an offense for Parser warnings' do
    create_file('example.rb', ['# encoding: utf-8',
                               'puts *test',
                               'if a then b else c end'])
    expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
    expect($stdout.string)
      .to eq(["#{abs('example.rb')}:2:6: W: " \
              'Ambiguous splat operator. Parenthesize the method arguments ' \
              "if it's surely a splat operator, or add a whitespace to the " \
              'right of the `*` if it should be a multiplication.',
              "#{abs('example.rb')}:3:1: C: " \
              'Favor the ternary operator (?:) over if/then/else/end ' \
              'constructs.',
              ''].join("\n"))
  end

  it 'can process a file with an invalid UTF-8 byte sequence' do
    create_file('example.rb', ['# encoding: utf-8',
                               "# #{'f9'.hex.chr}#{'29'.hex.chr}"])
    expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
    expect($stdout.string)
      .to eq(["#{abs('example.rb')}:1:1: F: Invalid byte sequence in utf-8.",
              ''].join("\n"))
  end

  context 'when errors are raised while processing files due to bugs' do
    let(:errors) do
      ['An error occurred while Encoding cop was inspecting file.rb.']
    end

    before do
      allow_any_instance_of(Kuma::Runner)
        .to receive(:errors).and_return(errors)
    end

    it 'displays an error message to stderr' do
      cli.run([])
      expect($stderr.string)
        .to include('1 error occurred:').and include(errors.first)
    end
  end

  describe 'rubocop:disable comment' do
    it 'can disable all cops in a code section' do
      src = ['# encoding: utf-8',
             '# rubocop:disable all',
             '#' * 90,
             'x(123456)',
             'y("123")',
             'def func',
             '  # rubocop: enable Metrics/LineLength,Style/StringLiterals',
             '  ' + '#' * 93,
             '  x(123456)',
             '  y("123")',
             'end']
      create_file('example.rb', src)
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
      # all cops were disabled, then 2 were enabled again, so we
      # should get 2 offenses reported.
      expect($stdout.string)
        .to eq(["#{abs('example.rb')}:8:81: C: Line is too long. [95/80]",
                "#{abs('example.rb')}:10:5: C: Prefer single-quoted " \
                "strings when you don't need string interpolation or " \
                'special symbols.',
                ''].join("\n"))
    end

    it 'can disable selected cops in a code section' do
      create_file('example.rb',
                  ['# encoding: utf-8',
                   '# rubocop:disable Style/LineLength,' \
                   'Style/NumericLiterals,Style/StringLiterals',
                   '#' * 90,
                   'x(123456)',
                   'y("123")',
                   'def func',
                   '  # rubocop: enable Metrics/LineLength, ' \
                   'Style/StringLiterals',
                   '  ' + '#' * 93,
                   '  x(123456)',
                   '  y("123")',
                   'end'])
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
      expect($stderr.string)
        .to eq(["#{abs('example.rb')}: Style/LineLength has the wrong " \
                'namespace - should be Metrics',
                ''].join("\n"))
      # 3 cops were disabled, then 2 were enabled again, so we
      # should get 2 offenses reported.
      expect($stdout.string)
        .to eq(["#{abs('example.rb')}:8:81: C: Line is too long. [95/80]",
                "#{abs('example.rb')}:10:5: C: Prefer single-quoted " \
                "strings when you don't need string interpolation or " \
                'special symbols.',
                ''].join("\n"))
    end

    it 'can disable all cops on a single line' do
      create_file('example.rb', ['# encoding: utf-8',
                                 'y("123", 123456) # rubocop:disable all'
                                ])
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(0)
      expect($stdout.string).to be_empty
    end

    it 'can disable selected cops on a single line' do
      create_file('example.rb',
                  ['# encoding: utf-8',
                   'a' * 90 + ' # rubocop:disable Metrics/LineLength',
                   '#' * 95,
                   'y("123") # rubocop:disable Metrics/LineLength,' \
                   'Style/StringLiterals'
                  ])
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
      expect($stdout.string)
        .to eq(
               ["#{abs('example.rb')}:3:81: C: Line is too long. [95/80]",
                ''].join("\n"))
    end

    context 'without using namespace' do
      it 'can disable selected cops on a single line' do
        create_file('example.rb',
                    ['# encoding: utf-8',
                     'a' * 90 + ' # rubocop:disable LineLength',
                     '#' * 95,
                     'y("123") # rubocop:disable StringLiterals'
                    ])
        expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
        expect($stdout.string)
          .to eq(
                 ["#{abs('example.rb')}:3:81: C: Line is too long. [95/80]",
                  ''].join("\n"))
      end
    end
  end

  it 'finds a file with no .rb extension but has a shebang line' do
    create_file('example', ['#!/usr/bin/env ruby',
                            '# encoding: utf-8',
                            'x = 0',
                            'puts x'
                           ])
    expect(cli.run(%w(--format simple))).to eq(0)
    expect($stdout.string)
      .to eq(['', '1 file inspected, no offenses detected', ''].join("\n"))
  end

  it 'does not register any offenses for an empty file' do
    create_file('example.rb', '')
    expect(cli.run(%w(--format simple))).to eq(0)
    expect($stdout.string)
      .to eq(['', '1 file inspected, no offenses detected', ''].join("\n"))
  end

  describe 'rails cops' do
    describe 'enabling/disabling' do
      it 'by default does not run rails cops' do
        create_file('app/models/example1.rb', ['# encoding: utf-8',
                                               'read_attribute(:test)'])
        expect(cli.run(['--format', 'simple', 'app/models/example1.rb']))
          .to eq(0)
      end

      it 'with -R given runs rails cops' do
        create_file('app/models/example1.rb', ['# encoding: utf-8',
                                               'read_attribute(:test)'])
        expect(cli.run(['--format', 'simple', '-R', 'app/models/example1.rb']))
          .to eq(1)
        expect($stdout.string).to include('Prefer self[:attr]')
      end

      it 'with configation option true in one dir runs rails cops there' do
        source = ['# encoding: utf-8',
                  'read_attribute(:test)']
        create_file('dir1/app/models/example1.rb', source)
        create_file('dir1/.rubocop.yml', ['AllCops:',
                                          '  RunRailsCops: true',
                                          '',
                                          'Rails/ReadWriteAttribute:',
                                          '  Include:',
                                          '    - app/models/**/*.rb'])
        create_file('dir2/app/models/example2.rb', source)
        create_file('dir2/.rubocop.yml', ['AllCops:',
                                          '  RunRailsCops: false',
                                          '',
                                          'Rails/ReadWriteAttribute:',
                                          '  Include:',
                                          '    - app/models/**/*.rb'])
        expect(cli.run(%w(--format simple dir1 dir2))).to eq(1)
        expect($stdout.string)
          .to eq(['== dir1/app/models/example1.rb ==',
                  'C:  2:  1: Prefer self[:attr] over read_attribute' \
                  '(:attr).',
                  '',
                  '2 files inspected, 1 offense detected',
                  ''].join("\n"))
      end

      it 'with configation option false but -R given runs rails cops' do
        create_file('app/models/example1.rb', ['# encoding: utf-8',
                                               'read_attribute(:test)'])
        create_file('.rubocop.yml', ['AllCops:',
                                     '  RunRailsCops: false'])
        expect(cli.run(['--format', 'simple', '-R', 'app/models/example1.rb']))
          .to eq(1)
        expect($stdout.string).to include('Prefer self[:attr]')
      end
    end

    describe 'including/excluding' do
      it 'includes some directories by default' do
        source = ['# encoding: utf-8',
                  'read_attribute(:test)',
                  "default_scope order: 'position'"]
        # Several rails cops include app/models by default.
        create_file('dir1/app/models/example1.rb', source)
        create_file('dir1/app/models/example2.rb', source)
        # No rails cops include app/views by default.
        create_file('dir1/app/views/example3.rb', source)
        # The .rubocop.yml file inherits from default.yml where the Include
        # config parameter is set for the rails cops. The paths are interpreted
        # as relative to dir1 because .rubocop.yml is placed there.
        create_file('dir1/.rubocop.yml', ['AllCops:',
                                          '  RunRailsCops: true',
                                          '',
                                          'Rails/ReadWriteAttribute:',
                                          '  Exclude:',
                                          '    - "**/example2.rb"',
                                          '',
                                          'Rails/DefaultScope:',
                                          '  Exclude:',
                                          '    - "**/example2.rb"'])
        # No .rubocop.yml file in dir2 means that the paths from default.yml
        # are interpreted as relative to the current directory, so they don't
        # match.
        create_file('dir2/app/models/example4.rb', source)

        expect(cli.run(%w(--format simple dir1 dir2))).to eq(1)
        expect($stdout.string)
          .to eq(['== dir1/app/models/example1.rb ==',
                  'C:  2:  1: Prefer self[:attr] over read_attribute' \
                  '(:attr).',
                  'C:  3: 15: default_scope expects a block as its sole' \
                  ' argument.',
                  '',
                  '4 files inspected, 2 offenses detected',
                  ''].join("\n"))
      end
    end
  end

  describe 'cops can exclude files based on config' do
    it 'ignores excluded files' do
      create_file('example.rb', ['# encoding: utf-8',
                                 'x = 0'])
      create_file('regexp.rb', ['# encoding: utf-8',
                                'x = 0'])
      create_file('exclude_glob.rb', ['#!/usr/bin/env ruby',
                                      '# encoding: utf-8',
                                      'x = 0'])
      create_file('dir/thing.rb', ['# encoding: utf-8',
                                   'x = 0'])
      create_file('.rubocop.yml', ['Lint/UselessAssignment:',
                                   '  Exclude:',
                                   '    - example.rb',
                                   '    - !ruby/regexp /regexp.rb\z/',
                                   '    - "exclude_*"',
                                   '    - "dir/*"'])
      expect(cli.run(%w(--format simple))).to eq(0)
      expect($stdout.string)
        .to eq(['', '4 files inspected, no offenses detected',
                ''].join("\n"))
    end

  end

  describe 'configuration from file' do
    it 'allows the default configuration file as the -c argument' do
      create_file('example.rb', ['# encoding: utf-8',
                                 'x = 0',
                                 'puts x'
                                ])
      create_file('.rubocop.yml', [])

      expect(cli.run(%w(--format simple -c .rubocop.yml))).to eq(0)
      expect($stdout.string)
        .to eq(['', '1 file inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'finds included files' do
      create_file('example', ['# encoding: utf-8',
                              'x = 0',
                              'puts x'
                             ])
      create_file('regexp', ['# encoding: utf-8',
                             'x = 0',
                             'puts x'
                            ])
      create_file('.rubocop.yml', ['AllCops:',
                                   '  Include:',
                                   '    - example',
                                   '    - !ruby/regexp /regexp$/'
                                  ])
      expect(cli.run(%w(--format simple))).to eq(0)
      expect($stdout.string)
        .to eq(['', '2 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'ignores excluded files' do
      create_file('example.rb', ['# encoding: utf-8',
                                 'x = 0',
                                 'puts x'
                                ])
      create_file('regexp.rb', ['# encoding: utf-8',
                                'x = 0',
                                'puts x'
                               ])
      create_file('exclude_glob.rb', ['#!/usr/bin/env ruby',
                                      '# encoding: utf-8',
                                      'x = 0',
                                      'puts x'
                                     ])
      create_file('.rubocop.yml', ['AllCops:',
                                   '  Exclude:',
                                   '    - example.rb',
                                   '    - !ruby/regexp /regexp.rb$/',
                                   '    - "exclude_*"'
                                  ])
      expect(cli.run(%w(--format simple))).to eq(0)
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'matches included/excluded files corectly when . argument is given' do
      create_file('example.rb', 'x = 0')
      create_file('special.dsl', ['# encoding: utf-8',
                                  'setup { "stuff" }'
                                 ])
      create_file('.rubocop.yml', ['AllCops:',
                                   '  Include:',
                                   '    - "*.dsl"',
                                   '  Exclude:',
                                   '    - example.rb'
                                  ])
      expect(cli.run(%w(--format simple .))).to eq(1)
      expect($stdout.string)
        .to eq(['== special.dsl ==',
                "C:  2:  9: Prefer single-quoted strings when you don't " \
                'need string interpolation or special symbols.',
                '',
                '1 file inspected, 1 offense detected',
                ''].join("\n"))
    end

    # With rubinius 2.0.0.rc1 + rspec 2.13.1,
    # File.stub(:open).and_call_original causes SystemStackError.
    it 'does not read files in excluded list', broken: :rbx do
      %w(rb.rb non-rb.ext without-ext).each do |filename|
        create_file("example/ignored/#{filename}", ['# encoding: utf-8',
                                                    '#' * 90
                                                   ])
      end

      create_file('example/.rubocop.yml', ['AllCops:',
                                           '  Exclude:',
                                           '    - ignored/**'])
      expect(File).not_to receive(:open).with(%r{/ignored/})
      allow(File).to receive(:open).and_call_original
      expect(cli.run(%w(--format simple example))).to eq(0)
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'can be configured with option to disable a certain error' do
      create_file('example1.rb', 'puts 0 ')
      create_file('rubocop.yml', ['Style/Encoding:',
                                  '  Enabled: false',
                                  '',
                                  'Style/CaseIndentation:',
                                  '  Enabled: false'])
      expect(cli.run(['--format', 'simple',
                      '-c', 'rubocop.yml', 'example1.rb'])).to eq(1)
      expect($stdout.string)
        .to eq(['== example1.rb ==',
                'C:  1:  7: Trailing whitespace detected.',
                '',
                '1 file inspected, 1 offense detected',
                ''].join("\n"))
    end

    context 'without using namespace' do
      it 'can be configured with option to disable a certain error' do
        create_file('example1.rb', 'puts 0 ')
        create_file('rubocop.yml', ['Encoding:',
                                    '  Enabled: false',
                                    '',
                                    'CaseIndentation:',
                                    '  Enabled: false'])
        expect(cli.run(['--format', 'simple',
                        '-c', 'rubocop.yml', 'example1.rb'])).to eq(1)
        expect($stdout.string)
          .to eq(['== example1.rb ==',
                  'C:  1:  7: Trailing whitespace detected.',
                  '',
                  '1 file inspected, 1 offense detected',
                  ''].join("\n"))
      end
    end

    it 'can disable parser-derived offenses with warning severity' do
      # `-' interpreted as argument prefix
      create_file('example.rb', 'puts -1')
      create_file('.rubocop.yml', ['Style/Encoding:',
                                   '  Enabled: false',
                                   '',
                                   'Lint/AmbiguousOperator:',
                                   '  Enabled: false'
                                  ])
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(0)
    end

    it 'cannot disable Syntax offenses with fatal/error severity' do
      create_file('example.rb', 'class Test')
      create_file('.rubocop.yml', ['Style/Encoding:',
                                   '  Enabled: false',
                                   '',
                                   'Syntax:',
                                   '  Enabled: false'
                                  ])
      expect(cli.run(['--format', 'emacs', 'example.rb'])).to eq(1)
      expect($stdout.string).to include('unexpected token $end')
    end

    it 'can be configured to merge a parameter that is a hash' do
      create_file('example1.rb',
                  ['# encoding: utf-8',
                   'puts %w(a b c)',
                   'puts %q|hi|'])
      # We want to change the preferred delimiters for word arrays. The other
      # settings from default.yml are unchanged.
      create_file('rubocop.yml',
                  ['Style/PercentLiteralDelimiters:',
                   '  PreferredDelimiters:',
                   "    '%w': '[]'",
                   "    '%W': '[]'"])
      cli.run(['--format', 'simple', '-c', 'rubocop.yml', 'example1.rb'])
      expect($stdout.string)
        .to eq(['== example1.rb ==',
                'C:  2:  6: %w-literals should be delimited by [ and ]',
                'C:  3:  6: %q-literals should be delimited by ( and )',
                'C:  3:  6: Use %q only for strings that contain both single ' \
                'quotes and double quotes.',
                '',
                '1 file inspected, 3 offenses detected',
                ''].join("\n"))
    end

    it 'can be configured to override a parameter that is a hash in a ' \
       'special case' do
      create_file('example1.rb',
                  ['# encoding: utf-8',
                   'arr.select { |e| e > 0 }.collect { |e| e * 2 }',
                   'a2.find_all { |e| e > 0 }'])
      # We prefer find_all over select. This setting overrides the default
      # select over find_all. Other preferred methods appearing in the default
      # config (e.g., map over collect) are kept.
      create_file('rubocop.yml',
                  ['Style/CollectionMethods:',
                   '  PreferredMethods:',
                   '    select: find_all'])
      cli.run(['--format', 'simple', '-c', 'rubocop.yml', 'example1.rb'])
      expect($stdout.string)
        .to eq(['== example1.rb ==',
                'C:  2:  5: Prefer find_all over select.',
                'C:  2: 26: Prefer map over collect.',
                '',
                '1 file inspected, 2 offenses detected',
                ''].join("\n"))
    end

    it 'works when a cop that others depend on is disabled' do
      create_file('example1.rb', ['if a',
                                  '  b',
                                  'end'])
      create_file('rubocop.yml', ['Style/Encoding:',
                                  '  Enabled: false',
                                  '',
                                  'Metrics/LineLength:',
                                  '  Enabled: false'
                                 ])
      result = cli.run(['--format', 'simple',
                        '-c', 'rubocop.yml', 'example1.rb'])
      expect($stdout.string)
        .to eq(['== example1.rb ==',
                'C:  1:  1: Favor modifier if usage when having ' \
                'a single-line body. Another good alternative is the ' \
                'usage of control flow &&/||.',
                '',
                '1 file inspected, 1 offense detected',
                ''].join("\n"))
      expect(result).to eq(1)
    end

    it 'can be configured with project config to disable a certain error' do
      create_file('example_src/example1.rb', 'puts 0 ')
      create_file('example_src/.rubocop.yml', ['Style/Encoding:',
                                               '  Enabled: false',
                                               '',
                                               'Style/CaseIndentation:',
                                               '  Enabled: false'
                                              ])
      expect(cli.run(['--format', 'simple',
                      'example_src/example1.rb'])).to eq(1)
      expect($stdout.string)
        .to eq(['== example_src/example1.rb ==',
                'C:  1:  7: Trailing whitespace detected.',
                '',
                '1 file inspected, 1 offense detected',
                ''].join("\n"))
    end

    it 'can use an alternative max line length from a config file' do
      create_file('example_src/example1.rb', ['# encoding: utf-8',
                                              '#' * 90
                                             ])
      create_file('example_src/.rubocop.yml', ['Metrics/LineLength:',
                                               '  Enabled: true',
                                               '  Max: 100'
                                              ])
      expect(cli.run(['--format', 'simple',
                      'example_src/example1.rb'])).to eq(0)
      expect($stdout.string)
        .to eq(['', '1 file inspected, no offenses detected', ''].join("\n"))
    end

    it 'can have different config files in different directories' do
      %w(src lib).each do |dir|
        create_file("example/#{dir}/example1.rb", ['# encoding: utf-8',
                                                   '#' * 90
                                                  ])
      end
      create_file('example/src/.rubocop.yml', ['Metrics/LineLength:',
                                               '  Enabled: true',
                                               '  Max: 100'
                                              ])
      expect(cli.run(%w(--format simple example))).to eq(1)
      expect($stdout.string).to eq(
                                   ['== example/lib/example1.rb ==',
                                    'C:  2: 81: Line is too long. [90/80]',
                                    '',
                                    '2 files inspected, 1 offense detected',
                                    ''].join("\n"))
    end

    it 'prefers a config file in ancestor directory to another in home' do
      create_file('example_src/example1.rb', ['# encoding: utf-8',
                                              '#' * 90
                                             ])
      create_file('example_src/.rubocop.yml', ['Metrics/LineLength:',
                                               '  Enabled: true',
                                               '  Max: 100'
                                              ])
      create_file("#{Dir.home}/.rubocop.yml", ['Metrics/LineLength:',
                                               '  Enabled: true',
                                               '  Max: 80'
                                              ])
      expect(cli.run(['--format', 'simple',
                      'example_src/example1.rb'])).to eq(0)
      expect($stdout.string)
        .to eq(['', '1 file inspected, no offenses detected', ''].join("\n"))
    end

    it 'can exclude directories relative to .rubocop.yml' do
      %w(src etc/test etc/spec tmp/test tmp/spec).each do |dir|
        create_file("example/#{dir}/example1.rb", ['# encoding: utf-8',
                                                   '#' * 90
                                                  ])
      end

      create_file('example/.rubocop.yml', ['AllCops:',
                                           '  Exclude:',
                                           '    - src/**',
                                           '    - etc/**/*',
                                           '    - tmp/spec/**'])

      expect(cli.run(%w(--format simple example))).to eq(1)
      expect($stdout.string).to eq(
                                   ['== example/tmp/test/example1.rb ==',
                                    'C:  2: 81: Line is too long. [90/80]',
                                    '',
                                    '1 file inspected, 1 offense detected',
                                    ''].join("\n"))
    end

    it 'can exclude a typical vendor directory' do
      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/.rubocop.yml',
                  ['AllCops:',
                   '  Exclude:',
                   '    - lib/parser/lexer.rb'])

      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/lib/ex.rb',
                  ['# encoding: utf-8',
                   '#' * 90])

      create_file('.rubocop.yml',
                  ['AllCops:',
                   '  Exclude:',
                   '    - vendor/**/*'])

      cli.run(%w(--format simple))
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'excludes the vendor directory by default' do
      create_file('vendor/ex.rb',
                  ['# encoding: utf-8',
                   '#' * 90])

      cli.run(%w(--format simple))
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    # Being immune to bad configuration files in excluded directories has
    # become important due to a bug in rubygems
    # (https://github.com/rubygems/rubygems/issues/680) that makes
    # installations of, for example, rubocop lack their .rubocop.yml in the
    # root directory.
    it 'can exclude a vendor directory with an erroneous config file' do
      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/.rubocop.yml',
                  ['inherit_from: non_existent.yml'])

      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/lib/ex.rb',
                  ['# encoding: utf-8',
                   '#' * 90])

      create_file('.rubocop.yml',
                  ['AllCops:',
                   '  Exclude:',
                   '    - vendor/**/*'])

      cli.run(%w(--format simple))
      expect($stderr.string).to eq('')
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    # Relative exclude paths in .rubocop.yml files are relative to that file,
    # but in configuration files with other names they will be relative to
    # whatever file inherits from them.
    it 'can exclude a vendor directory indirectly' do
      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/.rubocop.yml',
                  ['AllCops:',
                   '  Exclude:',
                   '    - lib/parser/lexer.rb'])

      create_file('vendor/bundle/ruby/1.9.1/gems/parser-2.0.0/lib/ex.rb',
                  ['# encoding: utf-8',
                   '#' * 90])

      create_file('.rubocop.yml',
                  ['inherit_from: config/default.yml'])

      create_file('config/default.yml',
                  ['AllCops:',
                   '  Exclude:',
                   '    - vendor/**/*'])

      cli.run(%w(--format simple))
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'prints a warning for an unrecognized cop name in .rubocop.yml' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('example/.rubocop.yml', ['Style/LyneLenth:',
                                           '  Enabled: true',
                                           '  Max: 100'])

      expect(cli.run(%w(--format simple example))).to eq(1)
      expect($stderr.string)
        .to eq(['Warning: unrecognized cop Style/LyneLenth found in ' +
                abs('example/.rubocop.yml'),
                ''].join("\n"))
    end

    it 'prints a warning for an unrecognized configuration parameter' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('example/.rubocop.yml', ['Metrics/LineLength:',
                                           '  Enabled: true',
                                           '  Min: 10'])

      expect(cli.run(%w(--format simple example))).to eq(1)
      expect($stderr.string)
        .to eq(['Warning: unrecognized parameter Metrics/LineLength:Min ' \
                'found in ' + abs('example/.rubocop.yml'),
                ''].join("\n"))
    end

    it 'works when a configuration file passed by -c specifies Exclude ' \
       'with regexp' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('rubocop.yml', ['AllCops:',
                                  '  Exclude:',
                                  '    - !ruby/regexp /example1\.rb$/'])

      cli.run(%w(--format simple -c rubocop.yml))
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'works when a configuration file passed by -c specifies Exclude ' \
       'with strings' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('rubocop.yml', ['AllCops:',
                                  '  Exclude:',
                                  '    - example/**'])

      cli.run(%w(--format simple -c rubocop.yml))
      expect($stdout.string)
        .to eq(['', '0 files inspected, no offenses detected',
                ''].join("\n"))
    end

    it 'works when a configuration file specifies a Severity' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('rubocop.yml', ['Metrics/LineLength:',
                                  '  Severity: error'])

      cli.run(%w(--format simple -c rubocop.yml))
      expect($stdout.string)
        .to eq(['== example/example1.rb ==',
                'E:  2: 81: Line is too long. [90/80]',
                '',
                '1 file inspected, 1 offense detected',
                ''].join("\n"))
      expect($stderr.string).to eq('')
    end

    it 'fails when a configuration file specifies an invalid Severity' do
      create_file('example/example1.rb', ['# encoding: utf-8',
                                          '#' * 90])

      create_file('rubocop.yml', ['Metrics/LineLength:',
                                  '  Severity: superbad'])

      cli.run(%w(--format simple -c rubocop.yml))
      expect($stderr.string)
        .to eq(["Warning: Invalid severity 'superbad'. " \
                'Valid severities are refactor, convention, ' \
                'warning, error, fatal.',
                ''].join("\n"))
    end

    context 'when a file inherits from the old auto generated file' do
      before do
        create_file('rubocop-todo.yml', '')
        create_file('.rubocop.yml', ['inherit_from: rubocop-todo.yml'])
      end

      it 'prints no warning when --auto-gen-config is not set' do
        expect { cli.run(%w(-c .rubocop.yml)) }.not_to exit_with_code(1)
      end

      it 'prints a warning when --auto-gen-config is set' do
        expect { cli.run(%w(-c .rubocop.yml --auto-gen-config)) }
          .to exit_with_code(1)
        expect($stderr.string)
          .to eq(['Attention: rubocop-todo.yml has been renamed to ' \
                  '.rubocop_todo.yml',
                  ''].join("\n"))
      end
    end
  end
end