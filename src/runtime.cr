require "digest/sha256"

module Crys
  def self.crystal_run_args(opts : Options) : Array(String)
    opts.inplace_suffix.nil? ? opts.files : [] of String
  end

  private def self.ensure_dir(path : String) : Nil
    Dir.mkdir_p(path)
  rescue ex : File::AlreadyExistsError
    raise ex unless Dir.exists?(path)
  end

  private def self.crystal_build_args(opts : Options, source_path : String, binary_path : String) : Array(String)
    args = ["build", "-O#{opts.level}"]
    if opts.parallel?
      args << "-Dpreview_mt"
      args << "-Dexecution_context"
    end

    args + opts.crystal_flags + ["-o", binary_path, source_path]
  end

  private def self.cache_key(opts : Options, code : String) : String
    Digest::SHA256.hexdigest(opts.level + "\0" + opts.crystal_flags.join("\0") + "\0" + code)
  end

  private def self.cached_binary_path(opts : Options, cache_key : String) : String
    cache_dir = File.join(opts.crys_home, "cache")
    ensure_dir(cache_dir)
    File.join(cache_dir, cache_key)
  end

  private def self.cached_source_path(opts : Options, cache_key : String) : String
    source_dir = File.join(opts.crys_home, "src")
    ensure_dir(source_dir)
    File.join(source_dir, "#{cache_key}.cr")
  end

  private def self.temp_path(path : String) : String
    "#{path}.tmp.#{Process.pid}"
  end

  private def self.inplace_temp_path(filepath : String) : String
    dirname = File.dirname(filepath)
    basename = File.basename(filepath)
    File.join(dirname, ".#{basename}.crys_tmp_#{Process.pid}")
  end

  private def self.write_atomic(path : String, content : String) : Nil
    tmp_path = temp_path(path)
    File.write(tmp_path, content)
    File.rename(tmp_path, path)
  ensure
    File.delete(tmp_path) if tmp_path && File.exists?(tmp_path)
  end

  private def self.build_binary(opts : Options, source_path : String, tmp_binary_path : String) : Nil
    status = Process.run(
      "crystal",
      args: crystal_build_args(opts, source_path, tmp_binary_path),
      output: :inherit,
      error: :inherit,
      chdir: opts.crys_home,
    )
    exit status.exit_code unless status.success?
  end

  private def self.publish_binary(tmp_binary_path : String, binary_path : String) : Nil
    File.rename(tmp_binary_path, binary_path)
  rescue ex : File::AlreadyExistsError
    # Another process may have published the same cache key first.
    raise ex unless File.exists?(binary_path)
  end

  private def self.ensure_cached_binary(opts : Options, code : String) : String
    key = cache_key(opts, code)
    binary_path = cached_binary_path(opts, key)
    return binary_path if File.exists?(binary_path)

    source_path = cached_source_path(opts, key)
    write_atomic(source_path, code)

    tmp_binary_path = temp_path(binary_path)

    begin
      build_binary(opts, source_path, tmp_binary_path)
      publish_binary(tmp_binary_path, binary_path)
    ensure
      File.delete(tmp_binary_path) if File.exists?(tmp_binary_path)
    end

    binary_path
  end

  private def self.run_inplace_file(binary_path : String, filepath : String, inplace_suffix : String) : Int32
    path_info = File.info(filepath, follow_symlinks: false)
    if path_info.type.symlink?
      STDERR.puts "crys: refusing to edit symlink in place: #{filepath}"
      return 1
    end

    file_info = File.info(filepath)
    tmp_file = inplace_temp_path(filepath)

    unless inplace_suffix.empty?
      File.copy(filepath, filepath + inplace_suffix)
    end

    env = {"CRYS_FILE" => filepath}
    status = File.open(filepath) do |input_file|
      File.open(tmp_file, "w", perm: file_info.permissions.value) do |output_file|
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

    File.chmod(tmp_file, file_info.permissions.value)
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
    code = generate_code(opts)

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
