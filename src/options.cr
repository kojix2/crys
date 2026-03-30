require "option_parser"

module Crys
  class Options
    property crys_home : String
    property level : String = "2"
    property? mode_n : Bool = false
    property? mode_p : Bool = false
    property? autosplit : Bool = false
    property? slurp : Bool = false
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

    def initialize
      @crys_home = ENV.fetch("CRYS_HOME", File.join(ENV["HOME"], ".local", "share", "crys"))
      @inplace_suffix = nil
    end
  end

  USAGE = <<-USAGE
  Usage:
    crys [options] 'CRYSTAL_CODE' [file ...]

  Examples:
    crys -n 'puts line'
    crys -p 'line.upcase'
    crys -a -F: 'puts f[1]'
    crys --init 'sum = 0' -n 'sum += line.to_i' --final 'puts sum'
    crys -r json -g 'pp JSON.parse(input)'
    crys -pi.bak 'line.gsub("foo", "bar")' file.txt

  Options:
    -n              Read input line by line. Exposes: line, nr, fnr
    -p              Like -n, but assigns body result back to line and prints it
    -a              Auto-split line into f, nf
    -F SEP          Field separator for -a (default: " ", prefix '/' for regex: -F/: +/)
    -N NAMES        Bind split fields to variables (e.g. -N name,count)
    --where COND    Pre-filter lines with COND (repeatable; AND semantics)
    --map EXPR      Shortcut for line mode: puts(EXPR)
    --select COND   Shortcut for line mode: puts line if COND
    --header        Treat first row as header and expose row hash (requires -a)
    --sum EXPR      Sum EXPR across selected rows (__crys_sum)
    --count         Count selected rows (__crys_count)
    -g, --slurp     Read all input into input
    -i[SUFFIX]      Edit files in-place (SUFFIX for backup, e.g. -i.bak)
    -r LIB          Add require "LIB" (repeatable)
    --init CODE     Insert CODE before the main body/loop
    --final CODE    Insert CODE after the main body/loop
    --dump          Print generated Crystal code and exit
    -O LEVEL        Pass optimization level to crystal build (0,1,2,3,s,z)
    --release       Pass --release to crystal build
    --error-trace   Pass --error-trace to crystal build
    -h, --help      Show this help

  Notes:
    * line is always chomped.
    * Implicit variables: line, f, nf, nr, fnr, path, input, row
    * nf: number of fields (only with -a). fnr: per-file line number (same as nr for stdin)
    * row: Hash(String, String) from header columns (only with --header)
    * --sum/--count auto-print at end when --final is not specified.
    * Dependencies are resolved from CRYS_HOME (default: ~/.local/share/crys).
    * Manage shard.yml / shards install there manually.
  USAGE

  private def self.preprocess_args(argv : Array(String), opts : Options) : Array(String)
    processed = [] of String
    i = 0
    while i < argv.size
      arg = argv[i]
      if arg.starts_with?("-i") && !arg.starts_with?("--")
        opts.inplace_suffix = arg.bytesize == 2 ? "" : arg[2..]
        i += 1
        next
      end
      if arg.starts_with?("-F") && arg.bytesize > 2
        raw = arg[2..]
        if raw.starts_with?('/') && raw.ends_with?('/') && raw.bytesize >= 2
          opts.split_sep = raw[1..-2]
          opts.split_regex = true
        else
          opts.split_sep = raw
        end
        i += 1
        next
      end
      if arg.starts_with?("-O") && arg.bytesize > 2
        opts.level = arg[2..]
        i += 1
        next
      end
      processed << arg
      i += 1
    end

    processed
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
    raise ArgumentError.new("-g/--slurp cannot be combined with -n/-p") if opts.slurp? && opts.mode_n?
    raise ArgumentError.new("-i requires at least one file") if !opts.inplace_suffix.nil? && opts.files.empty?
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

  private def self.validate_options(opts : Options) : Nil
    validate_level(opts)
    validate_mode_combinations(opts)
    validate_body_combinations(opts)
    validate_field_names(opts)
  end

  private def self.configure_parser(parser : OptionParser, opts : Options) : Nil
    parser.on("-h", "--help", "Show this help") do
      puts USAGE
      exit 0
    end
    parser.on("-n", "Line loop") { opts.mode_n = true }
    parser.on("-p", "Line loop with print") do
      opts.mode_p = true
      opts.mode_n = true
    end
    parser.on("-a", "Auto-split line into f") { opts.autosplit = true }
    parser.on("-F SEP", "Field separator") do |sep|
      if sep.starts_with?('/') && sep.ends_with?('/') && sep.bytesize >= 2
        opts.split_sep = sep[1..-2]
        opts.split_regex = true
      else
        opts.split_sep = sep
      end
    end
    parser.on("-N NAMES", "Bind split fields to variables") do |names|
      opts.named_fields = names.split(',').map(&.strip).reject(&.empty?)
    end
    parser.on("--where COND", "Pre-filter lines (repeatable)") { |cond| opts.where_conditions << cond }
    parser.on("--map EXPR", "Shortcut: puts(EXPR)") do |expr|
      opts.map_expr = expr
      opts.mode_n = true
    end
    parser.on("--select COND", "Shortcut: puts line if COND") do |cond|
      opts.select_cond = cond
      opts.mode_n = true
    end
    parser.on("--header", "Treat first row as header and expose row") { opts.header_mode = true }
    parser.on("--sum EXPR", "Sum EXPR across selected rows") do |expr|
      opts.sum_expr = expr
      opts.mode_n = true
    end
    parser.on("--count", "Count selected rows") do
      opts.count_mode = true
      opts.mode_n = true
    end
    parser.on("-g", "--slurp", "Read all input into input") { opts.slurp = true }
    parser.on("-r LIB", "Require library") { |req| opts.requires << req }
    parser.on("--init CODE", "Code before loop") { |code| opts.init_code = code }
    parser.on("--final CODE", "Code after loop") { |code| opts.final_code = code }
    parser.on("--dump", "Print generated Crystal code and exit") { opts.dump_only = true }
    parser.on("-O LEVEL", "Pass optimization level to crystal") { |level| opts.level = level }
    parser.on("--release", "Pass --release to crystal") { opts.crystal_flags << "--release" }
    parser.on("--error-trace", "Pass --error-trace to crystal") { opts.crystal_flags << "--error-trace" }
  end

  def self.parse_args(argv : Array(String)) : Options
    opts = Options.new
    parser = OptionParser.new
    configure_parser(parser, opts)

    processed = preprocess_args(argv, opts)
    parser.parse(processed)
    finalize_options(opts, processed)
  end
end
