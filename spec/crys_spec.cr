require "./spec_helper"

# Helper: build an Options with defaults; override via keyword args
private def make_opts(
  body_code : String = "puts line",
  mode_n : Bool = false,
  mode_p : Bool = false,
  autosplit : Bool = false,
  slurp : Bool = false,
  split_sep : String = "",
  init_code : String = "",
  final_code : String = "",
  requires : Array(String) = [] of String,
  files : Array(String) = [] of String,
  inplace_suffix : String? = nil,
) : Options
  o = Options.new
  o.body_code = body_code
  o.mode_n = mode_n || mode_p
  o.mode_p = mode_p
  o.autosplit = autosplit
  o.slurp = slurp
  o.split_sep = split_sep
  o.init_code = init_code
  o.final_code = final_code
  o.requires = requires.dup
  o.files = files.dup
  o.inplace_suffix = inplace_suffix
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

  it "emits no require line when requires is empty" do
    code = generate_code(make_opts)
    code.should_not contain("require")
  end

  # ── mode_n ────────────────────────────────────────────────────────────────

  it "emits each_line loop for -n" do
    code = generate_code(make_opts(mode_n: true))
    code.should contain("STDIN.each_line")
    code.should contain("nr += 1")
    code.should contain("line = __raw_line.chomp")
  end

  it "indents body_code inside each_line loop for -n" do
    code = generate_code(make_opts(mode_n: true, body_code: "puts line"))
    code.should contain("  puts line")
  end

  it "emits no each_line without -n" do
    code = generate_code(make_opts(body_code: "puts 1"))
    code.should_not contain("each_line")
  end

  # ── mode_p ────────────────────────────────────────────────────────────────

  it "emits each_line + line=begin/end + puts line for -p" do
    code = generate_code(make_opts(mode_p: true, body_code: "line.upcase"))
    code.should contain("STDIN.each_line")
    code.should contain("line = begin")
    code.should contain("end")
    code.should contain("puts line")
  end

  it "-p wraps body inside begin/end block" do
    code = generate_code(make_opts(mode_p: true, body_code: "line.upcase"))
    code.should contain("    line.upcase")
  end

  # ── autosplit ─────────────────────────────────────────────────────────────

  it "emits f= split for -a" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should contain("f =")
    code.should contain("split")
  end

  it "-a without explicit sep uses line.split (whitespace)" do
    code = generate_code(make_opts(mode_n: true, autosplit: true, split_sep: " "))
    code.should contain("line.split")
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

  # ── slurp ─────────────────────────────────────────────────────────────────

  it "emits gets_to_end and input variable for -g" do
    code = generate_code(make_opts(slurp: true, body_code: "puts input.size"))
    code.should contain("STDIN.gets_to_end")
    code.should contain("input")
  end

  it "-g does not emit each_line" do
    code = generate_code(make_opts(slurp: true, body_code: "puts input"))
    code.should_not contain("each_line")
  end

  # ── init / final ──────────────────────────────────────────────────────────

  it "--init inserts code before body" do
    code = generate_code(make_opts(mode_n: true, init_code: "sum = 0", body_code: "sum += line.to_i"))
    init_pos = code.index!("sum = 0")
    body_pos = code.index!("sum += line.to_i")
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
    code.should contain(%("CRYS_FILE"))
  end

  it "does not emit ENV[CRYS_FILE] without -i and without files" do
    code = generate_code(make_opts)
    code.should_not contain(%("CRYS_FILE"))
  end
end

describe "parse_args" do
  it "raises ArgumentError when body_code is missing" do
    expect_raises(ArgumentError, /missing Crystal code/) do
      parse_args([] of String)
    end
  end

  it "raises ArgumentError when -g and -n are combined" do
    expect_raises(ArgumentError, /cannot be combined/) do
      parse_args(["-g", "-n", "puts line"])
    end
  end

  it "-F: (no space) sets split_sep to colon" do
    opts = parse_args(["-F:", "puts line"])
    opts.split_sep.should eq(":")
  end

  it "-F : (with space) sets split_sep to colon" do
    opts = parse_args(["-F", ":", "puts line"])
    opts.split_sep.should eq(":")
  end

  it "-p sets mode_n and mode_p" do
    opts = parse_args(["-p", "line.upcase"])
    opts.mode_p?.should be_true
    opts.mode_n?.should be_true
  end

  it "-a without -F sets split_sep to space and enables mode_n" do
    opts = parse_args(["-a", "puts f[0]"])
    opts.autosplit?.should be_true
    opts.split_sep.should eq(" ")
    opts.mode_n?.should be_true
  end

  it "--slurp enables slurp mode" do
    opts = parse_args(["--slurp", "puts input"])
    opts.slurp?.should be_true
  end

  it "-r multiple times fills requires array" do
    opts = parse_args(["-r", "json", "-r", "yaml", "puts 1"])
    opts.requires.should eq(["json", "yaml"])
  end

  it "remaining args split into body_code and files" do
    opts = parse_args(["puts line", "a.txt", "b.txt"])
    opts.body_code.should eq("puts line")
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

  it "-i.bak sets inplace_suffix to .bak" do
    opts = parse_args(["-i.bak", "puts line", "file.txt"])
    opts.inplace_suffix.should eq(".bak")
  end

  it "-i (no suffix) sets inplace_suffix to empty string" do
    opts = parse_args(["-i", "puts line", "file.txt"])
    opts.inplace_suffix.should eq("")
  end

  it "raises ArgumentError when -i is used without files" do
    expect_raises(ArgumentError, /-i requires at least one file/) do
      parse_args(["-i", "puts line"])
    end
  end
end
