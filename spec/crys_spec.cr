require "./spec_helper"

alias Options = Crys::Options

private def parse_args(argv : Array(String)) : Options
  Crys.parse_args(argv)
end

private def generate_code(opts : Options) : String
  Crys.generate_code(opts)
end

private def crystal_run_args(opts : Options) : Array(String)
  Crys.crystal_run_args(opts)
end

# Helper: build an Options with defaults; override via keyword args
private def make_opts(
  body_code : String = "puts l",
  mode_n : Bool = false,
  mode_p : Bool = false,
  autosplit : Bool = false,
  split_sep : String = "",
  init_code : String = "",
  final_code : String = "",
  requires : Array(String) = [] of String,
  files : Array(String) = [] of String,
  inplace_suffix : String? = nil,
  where_conditions : Array(String) = [] of String,
  map_expr : String = "",
  select_cond : String = "",
  named_fields : Array(String) = [] of String,
  header_mode : Bool = false,
  sum_expr : String = "",
  count_mode : Bool = false,
  parallel : Bool = false,
  unordered : Bool = false,
  workers : Int32? = nil,
  batch_lines : Int32 = 4096,
  queue_batches : Int32? = nil,
) : Options
  o = Options.new
  o.body_code = body_code
  o.mode_n = mode_n || mode_p
  o.mode_p = mode_p
  o.autosplit = autosplit
  o.split_sep = split_sep
  o.init_code = init_code
  o.final_code = final_code
  o.requires = requires.dup
  o.files = files.dup
  o.inplace_suffix = inplace_suffix
  o.where_conditions = where_conditions.dup
  o.map_expr = map_expr
  o.select_cond = select_cond
  o.named_fields = named_fields.dup
  o.header_mode = header_mode
  o.sum_expr = sum_expr
  o.count_mode = count_mode
  o.parallel = parallel
  o.unordered = unordered
  o.workers = workers
  o.batch_lines = batch_lines
  o.queue_batches = queue_batches
  o
end

describe "generate_code" do
  # ── requires ──────────────────────────────────────────────────────────────

  it "emits require for -r json" do
    code = generate_code(make_opts(requires: ["json"]))
    code.should contain(%(require "json"))
  end

  it "emits multiple requires for -r json -r yaml" do
    code = generate_code(make_opts(requires: ["json", "yaml"]))
    code.should contain(%(require "json"))
    code.should contain(%(require "yaml"))
  end

  it "emits no require l when requires is empty" do
    code = generate_code(make_opts)
    code.should_not contain("require")
  end

  # ── mode_n ────────────────────────────────────────────────────────────────

  it "emits each_line loop for -n" do
    code = generate_code(make_opts(mode_n: true))
    code.should contain("STDIN.each_line")
    code.should contain("nr += 1")
    code.should contain("l = __raw_line.chomp")
  end

  it "indents body_code inside each_line loop for -n" do
    code = generate_code(make_opts(mode_n: true, body_code: "puts l"))
    code.should contain("  puts l")
  end

  it "emits no each_line without -n" do
    code = generate_code(make_opts(body_code: "puts 1"))
    code.should_not contain("each_line")
  end

  # ── mode_p ────────────────────────────────────────────────────────────────

  it "emits each_line + l=begin/end + puts l for -p" do
    code = generate_code(make_opts(mode_p: true, body_code: "l.upcase"))
    code.should contain("STDIN.each_line")
    code.should contain("l = begin")
    code.should contain("end")
    code.should contain("puts l")
  end

  it "-p wraps body inside begin/end block" do
    code = generate_code(make_opts(mode_p: true, body_code: "l.upcase"))
    code.should contain("    l.upcase")
  end

  # ── autosplit ─────────────────────────────────────────────────────────────

  it "emits f= split for -a" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should contain("f =")
    code.should contain("split")
  end

  it "-a without explicit sep uses l.split (whitespace)" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should contain("l.split")
  end

  it "-a -F: uses colon separator in generated code" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: ":"))
    code.should contain("__crys_sep")
    code.should contain("\":\"")
  end

  it "emits no f= without -a" do
    code = generate_code(make_opts(mode_n: true))
    code.should_not contain("f =")
  end

  # ── init / final ──────────────────────────────────────────────────────────

  it "--init inserts code before body" do
    code = generate_code(make_opts(mode_n: true, init_code: "sum = 0", body_code: "sum += l.to_i"))
    init_pos = code.index!("sum = 0")
    body_pos = code.index!("sum += l.to_i")
    init_pos.should be < body_pos
  end

  it "--final inserts code after body" do
    code = generate_code(make_opts(mode_n: true, final_code: "puts total", body_code: "process"))
    body_pos = code.index!("process")
    final_pos = code.index!("puts total")
    body_pos.should be < final_pos
  end

  it "init → body → final ordering" do
    code = generate_code(make_opts(
      mode_n: true,
      init_code: "INIT_MARKER",
      body_code: "BODY_MARKER",
      final_code: "FINAL_MARKER"
    ))
    init_pos = code.index!("INIT_MARKER")
    body_pos = code.index!("BODY_MARKER")
    final_pos = code.index!("FINAL_MARKER")
    init_pos.should be < body_pos
    body_pos.should be < final_pos
  end

  # ── path variable ─────────────────────────────────────────────────────────

  it "emits ENV[CRYS_FILE] when -i is used" do
    code = generate_code(make_opts(inplace_suffix: ".bak"))
    code.should contain(%("CRYS_FILE"))
  end

  it "emits ENV[CRYS_FILE] when files are specified" do
    code = generate_code(make_opts(files: ["input.txt"]))
    code.should contain(%(path = ""))
  end

  it "does not emit ENV[CRYS_FILE] without -i and without files" do
    code = generate_code(make_opts)
    code.should_not contain(%("CRYS_FILE"))
  end

  it "iterates through files in l mode when files are specified" do
    code = generate_code(make_opts(mode_n: true, files: ["a.txt", "b.txt"]))
    code.should contain("ARGV.each do |path|")
    code.should contain("File.open(path)")
    code.should contain("__crys_file.each_line")
  end
end

describe "parse_args" do
  it "raises ArgumentError when body_code is missing" do
    expect_raises(ArgumentError, /missing Crystal code/) do
      parse_args([] of String)
    end
  end

  it "-d: (no space) sets split_sep to colon" do
    opts = parse_args(["-d:", "puts l"])
    opts.split_sep.should eq(":")
  end

  it "-d : (with space) sets split_sep to colon" do
    opts = parse_args(["-d", ":", "puts l"])
    opts.split_sep.should eq(":")
  end

  it "-p sets mode_n and mode_p" do
    opts = parse_args(["-p", "l.upcase"])
    opts.mode_p?.should be_true
    opts.mode_n?.should be_true
  end

  it "-a without -d sets split_sep to space and enables mode_n" do
    opts = parse_args(["-a", "puts f[0]"])
    opts.autosplit?.should be_true
    opts.split_sep.should eq(" ")
    opts.mode_n?.should be_true
  end

  it "-r multiple times fills requires array" do
    opts = parse_args(["-r", "json", "-r", "yaml", "puts 1"])
    opts.requires.should eq(["json", "yaml"])
  end

  it "remaining args split into body_code and files" do
    opts = parse_args(["puts l", "a.txt", "b.txt"])
    opts.body_code.should eq("puts l")
    opts.files.should eq(["a.txt", "b.txt"])
  end

  it "--release goes into crystal_flags" do
    opts = parse_args(["--release", "puts 1"])
    opts.crystal_flags.should contain("--release")
  end

  it "--error-trace goes into crystal_flags" do
    opts = parse_args(["--error-trace", "puts 1"])
    opts.crystal_flags.should contain("--error-trace")
  end

  it "-O LEVEL sets level" do
    opts = parse_args(["-O", "2", "puts 1"])
    opts.level.should eq("2")
  end

  it "-O2 sets level" do
    opts = parse_args(["-O2", "puts 1"])
    opts.level.should eq("2")
  end

  it "defaults level to 2" do
    opts = parse_args(["puts 1"])
    opts.level.should eq("2")
  end

  it "raises ArgumentError for invalid -O level" do
    expect_raises(ArgumentError, /must be one of/) do
      parse_args(["-O", "x", "puts 1"])
    end
  end

  it "raises ArgumentError for invalid options" do
    expect_raises(ArgumentError, /invalid option: --nope/) do
      parse_args(["--nope"])
    end
  end

  it "raises ArgumentError when an option argument is missing" do
    expect_raises(ArgumentError, /missing option: -d/) do
      parse_args(["-d"])
    end
  end

  it "-I .bak sets inplace_suffix to .bak" do
    opts = parse_args(["-I", ".bak", "puts l", "file.txt"])
    opts.inplace_suffix.should eq(".bak")
  end

  it "-i (no suffix) sets inplace_suffix to empty string" do
    opts = parse_args(["-i", "puts l", "file.txt"])
    opts.inplace_suffix.should eq("")
  end

  it "raises ArgumentError when -i or -I is used without files" do
    expect_raises(ArgumentError, /-i\/-I requires at least one file/) do
      parse_args(["-i", "puts l"])
    end
  end

  it "raises ArgumentError when -I is used without files" do
    expect_raises(ArgumentError, /-i\/-I requires at least one file/) do
      parse_args(["-I", ".bak", "puts l"])
    end
  end

  it "--where can be repeated" do
    opts = parse_args(["--where", "l =~ /a/", "--where", "nr > 2", "puts l"])
    opts.where_conditions.should eq(["l =~ /a/", "nr > 2"])
  end

  it "--map sets map expression and enables mode_n" do
    opts = parse_args(["--map", "l.upcase"])
    opts.mode_n?.should be_true
    opts.map_expr.should eq("l.upcase")
  end

  it "-F/--filter sets condition and enables mode_n" do
    opts = parse_args(["-F", "l =~ /err/"])
    opts.mode_n?.should be_true
    opts.select_cond.should eq("l =~ /err/")
  end

  it "-N parses comma-separated field names" do
    opts = parse_args(["-a", "-N", "name, count, status", "puts name"])
    opts.named_fields.should eq(["name", "count", "status"])
  end

  it "raises ArgumentError when --map and --filter are combined" do
    expect_raises(ArgumentError, /cannot be combined/) do
      parse_args(["--map", "l", "-F", "nr > 1"])
    end
  end

  it "raises ArgumentError when --map has a body code argument" do
    expect_raises(ArgumentError, /do not take CRYSTAL_CODE/) do
      parse_args(["--map", "l", "puts l"])
    end
  end

  it "raises ArgumentError when -N is used without -a" do
    expect_raises(ArgumentError, /-N requires -a/) do
      parse_args(["-N", "name", "puts l"])
    end
  end

  it "raises ArgumentError for invalid names passed to -N" do
    expect_raises(ArgumentError, /invalid field name/) do
      parse_args(["-a", "-N", "1name", "puts l"])
    end
  end

  it "-H enables header mode" do
    opts = parse_args(["-a", "-H", "puts row[\"name\"]"])
    opts.header_mode?.should be_true
  end

  it "--header enables header mode" do
    opts = parse_args(["-a", "--header", "puts row[\"name\"]"])
    opts.header_mode?.should be_true
  end

  it "raises ArgumentError when --header is used without -a" do
    expect_raises(ArgumentError, /--header requires -a/) do
      parse_args(["--header", "puts l"])
    end
  end

  it "--sum enables mode_n and stores expression" do
    opts = parse_args(["--sum", "l.to_i"])
    opts.mode_n?.should be_true
    opts.sum_expr.should eq("l.to_i")
  end

  it "--count enables mode_n" do
    opts = parse_args(["--count"])
    opts.mode_n?.should be_true
    opts.count_mode?.should be_true
  end

  it "raises ArgumentError when --sum has a body code argument" do
    expect_raises(ArgumentError, /--sum\/--count do not take CRYSTAL_CODE/) do
      parse_args(["--sum", "l.to_i", "puts l"])
    end
  end

  # ── regex -F ──────────────────────────────────────────────────────────────

  it "-d/: +/ sets split_regex and stores the inner pattern" do
    opts = parse_args(["-d/: +/", "puts f[1]"])
    opts.split_regex?.should be_true
    opts.split_sep.should eq(": +")
  end

  it "-d /: +/ with space sets split_regex" do
    opts = parse_args(["-d", "/: +/", "puts f[1]"])
    opts.split_regex?.should be_true
    opts.split_sep.should eq(": +")
  end

  it "-d: without slashes does not set split_regex" do
    opts = parse_args(["-d:", "puts f[1]"])
    opts.split_regex?.should be_false
    opts.split_sep.should eq(":")
  end

  it "parses --parallel and --unordered" do
    opts = parse_args(["--parallel", "--unordered", "--map", "l.upcase"])
    opts.parallel?.should be_true
    opts.unordered?.should be_true
  end

  it "parses --workers, --batch-lines and --queue" do
    opts = parse_args(["--parallel", "--workers", "4", "--batch-lines", "2048", "--queue", "8", "--map", "l"])
    opts.workers.should eq(4)
    opts.batch_lines.should eq(2048)
    opts.queue_batches.should eq(8)
  end

  it "raises when --unordered is used without --parallel" do
    expect_raises(ArgumentError, /--unordered requires --parallel/) do
      parse_args(["--unordered", "--map", "l"])
    end
  end

  it "raises when --parallel is used with unsupported -a" do
    expect_raises(ArgumentError, /does not support -a/) do
      parse_args(["--parallel", "-a", "-p", "l"])
    end
  end

  it "raises when --parallel is used with multiple files" do
    expect_raises(ArgumentError, /at most one input file/) do
      parse_args(["--parallel", "-p", "l", "a.txt", "b.txt"])
    end
  end

  it "raises when --parallel is used with plain -n body" do
    expect_raises(ArgumentError, /supports only -p, --map, or --select/) do
      parse_args(["--parallel", "-n", "puts l"])
    end
  end
end

describe "generate_code (fnr / nf / regex separator)" do
  # ── fnr ───────────────────────────────────────────────────────────────────

  it "emits fnr initialization in -n mode" do
    code = generate_code(make_opts(mode_n: true))
    code.should contain("fnr = 0")
  end

  it "emits fnr increment in stdin mode" do
    code = generate_code(make_opts(mode_n: true))
    code.should contain("fnr += 1")
  end

  it "emits fnr reset logic in file mode" do
    code = generate_code(make_opts(mode_n: true, files: ["a.txt"]))
    code.should contain("fnr = 0")
    code.should contain("fnr += 1")
    code.should_not contain("__crys_last_path")
  end

  # ── nf ────────────────────────────────────────────────────────────────────

  it "emits nf = f.size after autosplit" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: ":"))
    code.should contain("nf = f.size")
  end

  it "emits nf in stdin path" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should contain("nf = f.size")
  end

  it "does not emit nf without -a" do
    code = generate_code(make_opts(mode_n: true))
    code.should_not contain("nf")
  end

  # ── regex separator ───────────────────────────────────────────────────────

  it "emits Regex.new(...) for regex separator" do
    o = make_opts(mode_n: true, autosplit: true, split_sep: ": +")
    o.split_regex = true
    code = generate_code(o)
    code.should contain("Regex.new")
    code.should contain("__crys_sep_re")
  end

  it "emits l.split(__crys_sep_re) for regex separator" do
    o = make_opts(mode_n: true, autosplit: true, split_sep: "[ /]+")
    o.split_regex = true
    code = generate_code(o)
    code.should contain("l.split(__crys_sep_re)")
  end

  it "emits l.split (whitespace) for default string separator" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should_not contain("Regex.new")
    code.should contain("l.split")
  end

  it "emits string split for non-whitespace literal separator" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: ":"))
    code.should_not contain("Regex.new")
    code.should contain("__crys_sep")
  end

  it "emits parallel batch scaffolding for --parallel --map" do
    code = generate_code(make_opts(mode_n: true, map_expr: "l.upcase", body_code: "", parallel: true, workers: 4))
    code.should contain("Fiber::ExecutionContext::Parallel")
    code.should contain("alias CrysBatch")
    code.should contain("Channel(CrysBatch?)")
  end

  it "emits ordered flag false when unordered mode is enabled" do
    code = generate_code(make_opts(mode_n: true, map_expr: "l", body_code: "", parallel: true, unordered: true))
    code.should contain("__crys_ordered = false")
  end
end

describe "generate_code (ergonomic shortcuts)" do
  it "emits --where conditions with AND semantics" do
    code = generate_code(make_opts(
      mode_n: true,
      body_code: "puts l",
      where_conditions: ["l =~ /error/", "nr > 1"]
    ))

    code.should contain("if (l =~ /error/) && (nr > 1)")
  end

  it "emits puts(EXPR) for --map" do
    code = generate_code(make_opts(mode_n: true, map_expr: "l.upcase", body_code: ""))
    code.should contain("puts(l.upcase)")
  end

  it "emits conditional print for --select" do
    code = generate_code(make_opts(mode_n: true, select_cond: "l =~ /x/", body_code: ""))
    code.should contain("puts l if l =~ /x/")
  end

  it "emits named field bindings when -N is used" do
    code = generate_code(make_opts(
      mode_n: true,
      autosplit: true,
      split_sep: ":",
      named_fields: ["name", "count"]
    ))

    code.should contain("name = f[0]?")
    code.should contain("count = f[1]?")
  end

  it "emits header parsing and row hash for --header" do
    code = generate_code(make_opts(
      mode_n: true,
      autosplit: true,
      split_sep: ",",
      header_mode: true,
      body_code: "puts row[\"name\"]?"
    ))

    code.should contain("__crys_headers = [] of String")
    code.should contain("if !__crys_have_header")
    code.should contain("row = Hash(String, String).new")
  end

  it "emits aggregate counters for --sum/--count" do
    code = generate_code(make_opts(mode_n: true, sum_expr: "l.to_i", count_mode: true, body_code: ""))
    code.should contain("__crys_sum = 0.0")
    code.should contain("__crys_count = 0_i64")
    code.should contain("__crys_sum += (l.to_i).to_f")
    code.should contain("__crys_count += 1")
    code.should contain("puts __crys_sum")
    code.should contain("puts __crys_count")
  end

  it "does not auto-print aggregates when --final is provided" do
    code = generate_code(make_opts(
      mode_n: true,
      sum_expr: "l.to_i",
      body_code: "",
      final_code: "puts __crys_sum"
    ))

    code.should_not contain("# --aggregate-final")
  end
end

describe "crystal_run_args" do
  it "passes file arguments to cached binaries" do
    opts = make_opts(files: ["a.txt", "b.txt"])
    crystal_run_args(opts).should eq(["a.txt", "b.txt"])
  end

  it "does not pass file arguments during in-place editing" do
    opts = make_opts(files: ["a.txt"], inplace_suffix: ".bak")
    crystal_run_args(opts).should eq([] of String)
  end
end
