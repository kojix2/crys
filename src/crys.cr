require "option_parser"
require "digest/sha256"

VERSION = "0.1.0"

class Options
  property crys_home : String
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
    * Implicit variables: line, f, nf, nr, fnr, path, input
    * nf: number of fields (only with -a). fnr: per-file line number (same as nr for stdin)
    * Dependencies are resolved from CRYS_HOME (default: ~/.local/share/crys).
    * Manage shard.yml / shards install there manually.
  USAGE

private def preprocess_args(argv : Array(String), opts : Options) : Array(String)
  # Pre-process argv to handle -i[SUFFIX], -F[SEP], and -OLEVEL without space
  # These can't be handled cleanly by OptionParser alone, so we transform first.
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
      opts.crystal_flags << "-O#{arg[2..]}"
      i += 1
      next
    end
    processed << arg
    i += 1
  end

  processed
end

private def finalize_options(opts : Options, remaining : Array(String)) : Options
  if opts.autosplit? && opts.split_sep.empty?
    opts.split_sep = " "
  end

  if opts.autosplit? && !opts.mode_n?
    opts.mode_n = true
  end

  if !opts.where_conditions.empty? && !opts.mode_n?
    opts.mode_n = true
  end

  if remaining.empty?
    if opts.map_expr.empty? && opts.select_cond.empty?
      raise ArgumentError.new("missing Crystal code")
    end

    opts.body_code = ""
  else
    opts.body_code = remaining[0]
    opts.files = remaining[1..] if remaining.size > 1
  end

  validate_options(opts)

  opts
end

private def validate_options(opts : Options) : Nil
  if opts.slurp? && opts.mode_n?
    raise ArgumentError.new("-g/--slurp cannot be combined with -n/-p")
  end

  if !opts.inplace_suffix.nil? && opts.files.empty?
    raise ArgumentError.new("-i requires at least one file")
  end

  if !opts.map_expr.empty? && !opts.select_cond.empty?
    raise ArgumentError.new("--map and --select cannot be combined")
  end

  if !opts.map_expr.empty? && opts.mode_p?
    raise ArgumentError.new("--map cannot be combined with -p")
  end

  if !opts.select_cond.empty? && opts.mode_p?
    raise ArgumentError.new("--select cannot be combined with -p")
  end

  if (!opts.map_expr.empty? || !opts.select_cond.empty?) && !opts.body_code.empty?
    raise ArgumentError.new("--map/--select do not take CRYSTAL_CODE argument")
  end

  if !opts.named_fields.empty? && !opts.autosplit?
    raise ArgumentError.new("-N requires -a")
  end

  opts.named_fields.each do |name|
    unless name.matches?(/^[a-z_][a-zA-Z0-9_]*$/)
      raise ArgumentError.new("invalid field name for -N: #{name}")
    end
  end
end

def parse_args(argv : Array(String)) : Options
  opts = Options.new
  parser = OptionParser.new

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
  parser.on("--where COND", "Pre-filter lines (repeatable)") do |cond|
    opts.where_conditions << cond
  end
  parser.on("--map EXPR", "Shortcut: puts(EXPR)") do |expr|
    opts.map_expr = expr
    opts.mode_n = true
  end
  parser.on("--select COND", "Shortcut: puts line if COND") do |cond|
    opts.select_cond = cond
    opts.mode_n = true
  end
  parser.on("-g", "--slurp", "Read all input into input") { opts.slurp = true }
  parser.on("-r LIB", "Require library") do |req|
    opts.requires << req
  end
  parser.on("--init CODE", "Code before loop") do |code|
    opts.init_code = code
  end
  parser.on("--final CODE", "Code after loop") do |code|
    opts.final_code = code
  end
  parser.on("--dump", "Print generated code and exit") { opts.dump_only = true }
  parser.on("-O LEVEL", "Pass optimization level to crystal") do |level|
    opts.crystal_flags << "-O#{level}"
  end
  parser.on("--release", "Pass --release to crystal") { opts.crystal_flags << "--release" }
  parser.on("--error-trace", "Pass --error-trace to crystal") { opts.crystal_flags << "--error-trace" }

  processed = preprocess_args(argv, opts)

  parser.parse(processed)
  finalize_options(opts, processed)
end

def crystal_run_args(opts : Options) : Array(String)
  opts.inplace_suffix.nil? ? opts.files : [] of String
end

private def crystal_build_args(opts : Options, binary_path : String) : Array(String)
  ["build"] + opts.crystal_flags + ["-o", binary_path, "src/__crys_main.cr"]
end

private def cached_binary_path(opts : Options, code : String) : String
  cache_dir = File.join(opts.crys_home, "cache")
  Dir.mkdir_p(cache_dir)
  cache_key = Digest::SHA256.hexdigest(opts.crystal_flags.join("\0") + "\0" + code)
  File.join(cache_dir, cache_key)
end

private def ensure_cached_binary(opts : Options, code : String) : String
  binary_path = cached_binary_path(opts, code)
  return binary_path if File.exists?(binary_path)

  status = Process.run(
    "crystal",
    args: crystal_build_args(opts, binary_path),
    output: :inherit,
    error: :inherit,
    chdir: opts.crys_home
  )
  exit status.exit_code unless status.success?

  binary_path
end

private def reads_from_files?(opts : Options) : Bool
  opts.inplace_suffix.nil? && !opts.files.empty?
end

private def generate_requires(io : IO, opts : Options) : Nil
  opts.requires.each do |req|
    io << "require #{req.inspect}\n"
  end
  io << "\n" unless opts.requires.empty?
end

private def generate_path_binding(io : IO, opts : Options) : Nil
  if !opts.inplace_suffix.nil?
    io << "path = ENV[\"CRYS_FILE\"]? || \"\"\n\n"
  elsif reads_from_files?(opts)
    io << "path = \"\"\n\n"
  end
end

private def generate_init_code(io : IO, opts : Options) : Nil
  return if opts.init_code.empty?

  io << "# --init\n"
  io << opts.init_code << "\n\n"
end

private def append_indented_code(io : IO, code : String, indent : String) : Nil
  code.each_line do |body_line|
    io << indent << body_line << "\n"
  end
end

private def generate_autosplit(io : IO, regex : Bool = false) : Nil
  if regex
    io << "  f = line.split(__crys_sep_re)\n"
  else
    io << "  f =\n"
    io << "    if __crys_sep == \" \"\n"
    io << "      line.split\n"
    io << "    else\n"
    io << "      line.split(__crys_sep)\n"
    io << "    end\n"
  end
  io << "  nf = f.size\n"
end

private def generate_autosplit_indented(io : IO, regex : Bool, indent : String) : Nil
  if regex
    io << "#{indent}f = line.split(__crys_sep_re)\n"
  else
    io << "#{indent}f =\n"
    io << "#{indent}  if __crys_sep == \" \"\n"
    io << "#{indent}    line.split\n"
    io << "#{indent}  else\n"
    io << "#{indent}    line.split(__crys_sep)\n"
    io << "#{indent}  end\n"
  end
  io << "#{indent}nf = f.size\n"
end

private def generate_named_fields(io : IO, opts : Options, indent : String) : Nil
  opts.named_fields.each_with_index do |name, index|
    io << "#{indent}#{name} = f[#{index}]?\n"
  end
end

private def emit_line_action(io : IO, opts : Options, indent : String) : Nil
  if !opts.select_cond.empty?
    io << "#{indent}puts line if #{opts.select_cond}\n"
  elsif !opts.map_expr.empty?
    io << "#{indent}puts(#{opts.map_expr})\n"
  elsif opts.mode_p?
    io << "#{indent}line = begin\n"
    append_indented_code(io, opts.body_code, indent + "  ")
    io << "#{indent}end\n"
    io << "#{indent}puts line\n"
  else
    append_indented_code(io, opts.body_code, indent)
  end
end

private def emit_where_wrapped_action(io : IO, opts : Options, indent : String) : Nil
  if opts.where_conditions.empty?
    emit_line_action(io, opts, indent)
    return
  end

  cond = opts.where_conditions.map { |c| "(#{c})" }.join(" && ")
  io << "#{indent}if #{cond}\n"
  emit_line_action(io, opts, indent + "  ")
  io << "#{indent}end\n"
end

private def generate_line_mode(io : IO, opts : Options) : Nil
  if opts.autosplit?
    if opts.split_regex?
      io << "__crys_sep_re = Regex.new(#{opts.split_sep.inspect})\n\n"
    else
      sep_literal = opts.split_sep.inspect
      io << "__crys_sep = #{sep_literal}\n\n"
    end
  end

  io << "nr = 0\n"
  io << "fnr = 0\n"
  if reads_from_files?(opts)
    io << "ARGV.each do |path|\n"
    io << "  fnr = 0\n"
    io << "  File.open(path) do |__crys_file|\n"
    io << "    __crys_file.each_line do |__raw_line|\n"
    io << "      nr += 1\n"
    io << "      fnr += 1\n"
    io << "      line = __raw_line.chomp\n"

    if opts.autosplit?
      generate_autosplit_indented(io, opts.split_regex?, "      ")
      generate_named_fields(io, opts, "      ")
    end

    emit_where_wrapped_action(io, opts, "      ")

    io << "    end\n"
    io << "  end\n"
    io << "end\n"
  else
    io << "STDIN.each_line do |__raw_line|\n"
    io << "  nr += 1\n"
    io << "  fnr += 1\n"
    io << "  line = __raw_line.chomp\n"

    if opts.autosplit?
      generate_autosplit(io, opts.split_regex?)
      generate_named_fields(io, opts, "  ")
    end

    emit_where_wrapped_action(io, opts, "  ")

    io << "end\n"
  end
end

private def generate_final_code(io : IO, opts : Options) : Nil
  return if opts.final_code.empty?

  io << "\n# --final\n"
  io << opts.final_code << "\n"
end

private def run_inplace_file(binary_path : String, filepath : String, inplace_suffix : String) : Int32
  tmp_file = filepath + ".crys_tmp_#{Process.pid}"

  unless inplace_suffix.empty?
    File.copy(filepath, filepath + inplace_suffix)
  end

  env = {"CRYS_FILE" => filepath}
  status = File.open(filepath) do |input_file|
    File.open(tmp_file, "w", perm: 0o600) do |output_file|
      Process.run(
        binary_path,
        env: env,
        input: input_file,
        output: output_file,
        error: :inherit,
      )
    end
  end

  return status.exit_code unless status.success?

  File.rename(tmp_file, filepath)
  0
rescue ex : File::Error
  STDERR.puts "crys: File operation failed: #{ex.message}"
  1
rescue ex : IO::Error
  STDERR.puts "crys: Process execution failed: #{ex.message}"
  1
rescue ex
  STDERR.puts "crys: Unexpected error: #{ex.class}: #{ex.message}"
  1
ensure
  if existing_tmp_file = tmp_file
    File.delete(existing_tmp_file) if File.exists?(existing_tmp_file)
  end
end

def generate_code(opts : Options) : String
  io = IO::Memory.new

  io << "# generated by crys\n\n"

  generate_requires(io, opts)
  generate_path_binding(io, opts)
  generate_init_code(io, opts)

  if opts.slurp?
    if reads_from_files?(opts)
      io << "ARGV.each do |path|\n"
      io << "  input = File.read(path)\n\n"
      append_indented_code(io, opts.body_code, "  ")
      io << "end\n"
    else
      io << "input = STDIN.gets_to_end\n\n"
      io << opts.body_code << "\n"
    end
  elsif opts.mode_n?
    generate_line_mode(io, opts)
  else
    if reads_from_files?(opts)
      io << "ARGV.each do |path|\n"
      append_indented_code(io, opts.body_code, "  ")
      io << "end\n"
    else
      io << opts.body_code << "\n"
    end
  end

  generate_final_code(io, opts)

  io.to_s
end

def run(opts : Options) : NoReturn
  Dir.mkdir_p(File.join(opts.crys_home, "src"))
  main_file = File.join(opts.crys_home, "src", "__crys_main.cr")

  code = generate_code(opts)
  File.write(main_file, code)

  if opts.dump_only?
    print code
    exit 0
  end

  binary_path = ensure_cached_binary(opts, code)

  if inplace_suffix = opts.inplace_suffix
    # In-place editing: process each file individually
    opts.files.each do |filepath|
      exit_code = run_inplace_file(binary_path, filepath, inplace_suffix)
      exit exit_code unless exit_code == 0
    end
    exit 0
  end

  status = Process.run(
    binary_path,
    args: crystal_run_args(opts),
    input: :inherit,
    output: :inherit,
    error: :inherit,
  )
  exit status.exit_code
end
