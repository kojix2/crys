require "option_parser"

module Crys
  class Options
    HELP_BANNER        = "Usage: crys [options] 'CRYSTAL_CODE' [file ...]"
    HELP_SUMMARY_WIDTH = 20

    property crys_home : String
    property level : String = "2"
    property? mode_n : Bool = false
    property? mode_p : Bool = false
    property? autosplit : Bool = false
    property split_sep : String = ""
    property init_code : String = ""
    property final_code : String = ""
    property body_code : String = ""
    property requires : Array(String) = [] of String
    property files : Array(String) = [] of String
    property crystal_flags : Array(String) = [] of String
    property? dump_only : Bool = false
    property inplace_suffix : String?
    property? split_regex : Bool = false
    property where_conditions : Array(String) = [] of String
    property map_expr : String = ""
    property select_cond : String = ""
    property named_fields : Array(String) = [] of String
    property? header_mode : Bool = false
    property sum_expr : String = ""
    property? count_mode : Bool = false
    property? parallel : Bool = false
    property? unordered : Bool = false
    property workers : Int32?
    property batch_lines : Int32 = 4096
    property queue_batches : Int32?

    def initialize
      @crys_home = ENV.fetch("CRYS_HOME", File.join(ENV["HOME"], ".local", "share", "crys"))
      @inplace_suffix = nil
      @workers = nil
      @queue_batches = nil
    end
  end

  private def self.append_footer(parser : OptionParser, block : String) : Nil
    block.each_line(chomp: true) do |line|
      parser.separator line
    end
  end

  def self.usage : String
    opts = Options.new
    remaining = [] of String
    parser = OptionParser.new(gnu_optional_args: true)
    configure_parser(parser, opts, remaining)
    parser.to_s
  end

  private def self.apply_implicit_modes(opts : Options) : Nil
    opts.split_sep = " " if opts.autosplit? && opts.split_sep.empty?

    if opts.autosplit? || !opts.where_conditions.empty? || !opts.sum_expr.empty? || opts.count_mode?
      opts.mode_n = true unless opts.mode_n?
    end
  end

  private def self.assign_body_and_files(opts : Options, remaining : Array(String)) : Nil
    if remaining.empty?
      if opts.map_expr.empty? && opts.select_cond.empty? && opts.sum_expr.empty? && !opts.count_mode?
        raise ArgumentError.new("missing Crystal code")
      end

      opts.body_code = ""
      return
    end

    opts.body_code = remaining[0]
    opts.files = remaining[1..] if remaining.size > 1
  end

  private def self.finalize_options(opts : Options, remaining : Array(String)) : Options
    apply_implicit_modes(opts)
    assign_body_and_files(opts, remaining)
    validate_options(opts)
    opts
  end

  private def self.validate_level(opts : Options) : Nil
    return if {"0", "1", "2", "3", "s", "z"}.includes?(opts.level)

    raise ArgumentError.new("-O LEVEL must be one of: 0,1,2,3,s,z")
  end

  private def self.validate_mode_combinations(opts : Options) : Nil
    raise ArgumentError.new("-i/-I requires at least one file") if !opts.inplace_suffix.nil? && opts.files.empty?
    raise ArgumentError.new("--map and --select cannot be combined") if !opts.map_expr.empty? && !opts.select_cond.empty?
    raise ArgumentError.new("--map cannot be combined with -p") if !opts.map_expr.empty? && opts.mode_p?
    raise ArgumentError.new("--select cannot be combined with -p") if !opts.select_cond.empty? && opts.mode_p?
  end

  private def self.validate_body_combinations(opts : Options) : Nil
    if (!opts.map_expr.empty? || !opts.select_cond.empty?) && !opts.body_code.empty?
      raise ArgumentError.new("--map/--select do not take CRYSTAL_CODE argument")
    end

    if (!opts.sum_expr.empty? || opts.count_mode?) && !opts.body_code.empty?
      raise ArgumentError.new("--sum/--count do not take CRYSTAL_CODE argument")
    end
  end

  private def self.validate_field_names(opts : Options) : Nil
    raise ArgumentError.new("-N requires -a") if !opts.named_fields.empty? && !opts.autosplit?
    raise ArgumentError.new("--header requires -a") if opts.header_mode? && !opts.autosplit?

    opts.named_fields.each do |name|
      unless name.matches?(/^[a-z_][a-zA-Z0-9_]*$/)
        raise ArgumentError.new("invalid field name for -N: #{name}")
      end
    end
  end

  private def self.validate_parallel_mode_requirements(opts : Options) : Nil
    raise ArgumentError.new("--parallel requires line mode (-n, -p, --map or --select)") unless opts.mode_n?
    raise ArgumentError.new("--parallel cannot be combined with -i/-I") unless opts.inplace_suffix.nil?
    raise ArgumentError.new("--parallel currently supports at most one input file") if opts.files.size > 1
    raise ArgumentError.new("--parallel currently supports only -p, --map, or --select") if !opts.mode_p? && opts.map_expr.empty? && opts.select_cond.empty?
  end

  private def self.validate_parallel_unsupported_combinations(opts : Options) : Nil
    raise ArgumentError.new("--parallel does not support -a/-N/--header yet") if opts.autosplit? || !opts.named_fields.empty? || opts.header_mode?
    raise ArgumentError.new("--parallel does not support --where yet") unless opts.where_conditions.empty?
    raise ArgumentError.new("--parallel does not support --sum/--count yet") if !opts.sum_expr.empty? || opts.count_mode?
    raise ArgumentError.new("--parallel does not support --init/--final yet") unless opts.init_code.empty? && opts.final_code.empty?
  end

  private def self.validate_parallel_numeric_options(opts : Options) : Nil
    if workers = opts.workers
      raise ArgumentError.new("--workers must be >= 1") if workers < 1
    end

    raise ArgumentError.new("--batch-lines must be >= 1") if opts.batch_lines < 1

    if queue_batches = opts.queue_batches
      raise ArgumentError.new("--queue-batches must be >= 1") if queue_batches < 1
    end
  end

  private def self.validate_parallel_options(opts : Options) : Nil
    raise ArgumentError.new("--unordered requires --parallel") if opts.unordered? && !opts.parallel?
    return unless opts.parallel?

    validate_parallel_mode_requirements(opts)
    validate_parallel_unsupported_combinations(opts)
    validate_parallel_numeric_options(opts)
  end

  private def self.validate_options(opts : Options) : Nil
    validate_level(opts)
    validate_mode_combinations(opts)
    validate_body_combinations(opts)
    validate_field_names(opts)
    validate_parallel_options(opts)
  end

  private def self.configure_parser(parser : OptionParser, opts : Options, remaining : Array(String)) : Nil
    parser.banner = Options::HELP_BANNER
    parser.summary_width = Options::HELP_SUMMARY_WIDTH
    parser.separator ""
    parser.separator "Options:"
    parser.invalid_option do |flag|
      raise ArgumentError.new("invalid option: #{flag}")
    end
    parser.missing_option do |flag|
      raise ArgumentError.new("missing option: #{flag}")
    end
    parser.unknown_args do |args, after_dash|
      remaining.concat(args)
      remaining.concat(after_dash)
    end
    parser.on("-n", "Run CODE for each input line") { opts.mode_n = true }
    parser.on("-p", "--print", "Replace each line with CODE result and print it") do
      opts.mode_p = true
      opts.mode_n = true
    end
    parser.on("-a", "--auto-split", "Split each line into f and nf") { opts.autosplit = true }
    parser.on("-d", "--delimiter SEP", "Use SEP as field separator for -a") do |sep|
      if sep.starts_with?('/') && sep.ends_with?('/') && sep.bytesize >= 2
        opts.split_sep = sep[1..-2]
        opts.split_regex = true
      else
        opts.split_sep = sep
      end
    end
    parser.on("-N", "--names NAMES", "Bind split fields to variables, e.g. name,count") do |names|
      opts.named_fields = names.split(',').map(&.strip).reject(&.empty?)
    end
    parser.on("-W", "--where COND", "Process only lines where COND is true") { |cond| opts.where_conditions << cond }
    parser.on("-M", "--map EXPR", "Print EXPR for each selected line") do |expr|
      opts.map_expr = expr
      opts.mode_n = true
    end
    parser.on("-F", "--filter COND", "Print l when COND is true") do |cond|
      opts.select_cond = cond
      opts.mode_n = true
    end
    parser.on("-H", "--header", "Use the first split row as headers and expose row") { opts.header_mode = true }
    parser.on("-S", "--sum EXPR", "Add EXPR to a running total for selected lines") do |expr|
      opts.sum_expr = expr
      opts.mode_n = true
    end
    parser.on("-C", "--count", "Count selected rows") do
      opts.count_mode = true
      opts.mode_n = true
    end
    parser.on("-P", "--parallel", "Enable parallel batch processing (experimental)") { opts.parallel = true }
    parser.on("-U", "--unordered", "Allow out-of-order output in parallel mode") { opts.unordered = true }
    parser.on("-@", "--workers N", "Set parallel workers for --parallel") do |value|
      opts.workers = value.to_i
    rescue ex : ArgumentError
      raise ArgumentError.new("invalid --workers value: #{value}")
    end
    parser.on("-B", "--batch-lines N", "Set batch size in lines for --parallel [#{opts.batch_lines}]") do |value|
      opts.batch_lines = value.to_i
    rescue ex : ArgumentError
      raise ArgumentError.new("invalid --batch-lines value: #{value}")
    end
    parser.on("-Q", "--queue N", "Set producer queue capacity for --parallel") do |value|
      opts.queue_batches = value.to_i
    rescue ex : ArgumentError
      raise ArgumentError.new("invalid --queue value: #{value}")
    end
    parser.on("-i", "--inplace", "Edit files in place") { opts.inplace_suffix = "" }
    parser.on("-I SUFFIX", "Edit files in place and keep backups with SUFFIX") { |suffix| opts.inplace_suffix = suffix }
    parser.on("-r", "--require LIB", "Add require \"LIB\" to the generated program") { |req| opts.requires << req }
    parser.on("-A", "--init CODE", "Run CODE before processing input") { |code| opts.init_code = code }
    parser.on("-E", "--final CODE", "Run CODE after processing input") { |code| opts.final_code = code }
    parser.on("-D", "--dump", "Print the generated Crystal program and exit") { opts.dump_only = true }
    parser.on("-O LEVEL", "Build with crystal optimization level LEVEL [#{opts.level}]") { |level| opts.level = level }
    parser.on("-R", "--release", "Build with crystal --release") { opts.crystal_flags << "--release" }
    parser.on("--error-trace", "Build with crystal --error-trace") { opts.crystal_flags << "--error-trace" }
    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit 0
    end
    parser.on("--version", "Show version") do
      puts "crys #{VERSION}"
      exit 0
    end
    append_footer(parser, <<-TEXT)

      Notes:
        Input lines are chomped before evaluation.
        Variables: l, f, nf, nr, fnr, path, row (f/nf require -a; row requires --header).
        --sum/--count print totals automatically unless --final is given.
        --parallel is experimental and supports only -p, --map, and --select.
        Dependencies are loaded from CRYS_HOME (default: #{opts.crys_home}).
        Manage shard.yml and run shards install in CRYS_HOME manually.

      Examples:
        crys -n 'puts l'
        crys -p 'l.upcase'
        crys -a -d: 'puts f[1]'
        crys -A 'sum = 0' -n 'sum += l.to_i' -E 'puts sum'
        crys -r json 'pp JSON.parse(ARGF)'
        crys -I .bak -p 'l.gsub("foo", "bar")' file.txt
      TEXT
  end

  def self.parse_args(argv : Array(String)) : Options
    opts = Options.new
    remaining = [] of String
    parser = OptionParser.new(gnu_optional_args: true)
    configure_parser(parser, opts, remaining)
    parser.parse(argv.dup)
    finalize_options(opts, remaining)
  end
end
