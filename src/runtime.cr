require "digest/sha256"

module Crys
  def self.crystal_run_args(opts : Options) : Array(String)
    opts.inplace_suffix.nil? ? opts.files : [] of String
  end

  private def self.crystal_build_args(opts : Options, binary_path : String) : Array(String)
    args = ["build", "-O#{opts.level}"]
    if opts.parallel?
      args << "-Dpreview_mt"
      args << "-Dexecution_context"
    end

    args + opts.crystal_flags + ["-o", binary_path, "src/__crys_main.cr"]
  end

  private def self.cached_binary_path(opts : Options, code : String) : String
    cache_dir = File.join(opts.crys_home, "cache")
    Dir.mkdir_p(cache_dir)
    cache_key = Digest::SHA256.hexdigest(opts.level + "\0" + opts.crystal_flags.join("\0") + "\0" + code)
    File.join(cache_dir, cache_key)
  end

  private def self.ensure_cached_binary(opts : Options, code : String) : String
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

  private def self.run_inplace_file(binary_path : String, filepath : String, inplace_suffix : String) : Int32
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

  def self.run(opts : Options) : NoReturn
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
end
