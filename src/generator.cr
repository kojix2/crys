module Crys
  private def self.reads_from_files?(opts : Options) : Bool
    opts.inplace_suffix.nil? && !opts.files.empty?
  end

  private def self.generate_requires(io : IO, opts : Options) : Nil
    opts.requires.each do |req|
      io << "require #{req.inspect}\n"
    end
    io << "\n" unless opts.requires.empty?
  end

  private def self.generate_path_binding(io : IO, opts : Options) : Nil
    if !opts.inplace_suffix.nil?
      io << "path = ENV[\"CRYS_FILE\"]? || \"\"\n\n"
    elsif reads_from_files?(opts)
      io << "path = \"\"\n\n"
    end
  end

  private def self.generate_init_code(io : IO, opts : Options) : Nil
    return if opts.init_code.empty?

    io << "# --init\n"
    io << opts.init_code << "\n\n"
  end

  private def self.append_indented_code(io : IO, code : String, indent : String) : Nil
    code.each_line do |body_line|
      io << indent << body_line << "\n"
    end
  end

  private def self.generate_autosplit(io : IO, regex : Bool = false) : Nil
    if regex
      io << "  f = l.split(__crys_sep_re)\n"
    else
      io << "  f =\n"
      io << "    if __crys_sep == \" \"\n"
      io << "      l.split\n"
      io << "    else\n"
      io << "      l.split(__crys_sep)\n"
      io << "    end\n"
    end
    io << "  nf = f.size\n"
  end

  private def self.generate_autosplit_indented(io : IO, regex : Bool, indent : String) : Nil
    if regex
      io << "#{indent}f = l.split(__crys_sep_re)\n"
    else
      io << "#{indent}f =\n"
      io << "#{indent}  if __crys_sep == \" \"\n"
      io << "#{indent}    l.split\n"
      io << "#{indent}  else\n"
      io << "#{indent}    l.split(__crys_sep)\n"
      io << "#{indent}  end\n"
    end
    io << "#{indent}nf = f.size\n"
  end

  private def self.generate_named_fields(io : IO, opts : Options, indent : String) : Nil
    opts.named_fields.each_with_index do |name, index|
      io << "#{indent}#{name} = f[#{index}]?\n"
    end
  end

  private def self.generate_header_row(io : IO, indent : String) : Nil
    io << "#{indent}if !__crys_have_header\n"
    io << "#{indent}  __crys_headers = f.map(&.to_s)\n"
    io << "#{indent}  __crys_have_header = true\n"
    io << "#{indent}  next\n"
    io << "#{indent}end\n"
    io << "#{indent}row = Hash(String, String).new\n"
    io << "#{indent}__crys_headers.each_with_index do |__crys_h, __crys_i|\n"
    io << "#{indent}  row[__crys_h] = f[__crys_i]? || \"\"\n"
    io << "#{indent}end\n"
  end

  private def self.emit_aggregate_actions(io : IO, opts : Options, indent : String) : Nil
    io << "#{indent}__crys_sum += (#{opts.sum_expr}).to_f\n" unless opts.sum_expr.empty?
    io << "#{indent}__crys_count += 1\n" if opts.count_mode?
  end

  private def self.emit_line_action(io : IO, opts : Options, indent : String) : Nil
    if !opts.select_cond.empty?
      io << "#{indent}puts l if #{opts.select_cond}\n"
    elsif !opts.map_expr.empty?
      io << "#{indent}puts(#{opts.map_expr})\n"
    elsif opts.mode_p?
      io << "#{indent}l = begin\n"
      append_indented_code(io, opts.body_code, indent + "  ")
      io << "#{indent}end\n"
      io << "#{indent}puts l\n"
    else
      append_indented_code(io, opts.body_code, indent)
    end
  end

  private def self.has_main_action?(opts : Options) : Bool
    !opts.select_cond.empty? || !opts.map_expr.empty? || opts.mode_p? || !opts.body_code.empty?
  end

  private def self.emit_where_wrapped_action(io : IO, opts : Options, indent : String) : Nil
    if opts.where_conditions.empty?
      emit_aggregate_actions(io, opts, indent)
      emit_line_action(io, opts, indent) if has_main_action?(opts)
      return
    end

    cond = opts.where_conditions.map { |c| "(#{c})" }.join(" && ")
    io << "#{indent}if #{cond}\n"
    emit_aggregate_actions(io, opts, indent + "  ")
    emit_line_action(io, opts, indent + "  ") if has_main_action?(opts)
    io << "#{indent}end\n"
  end

  private def self.generate_line_mode_setup(io : IO, opts : Options) : Nil
    if opts.autosplit?
      if opts.split_regex?
        io << "__crys_sep_re = Regex.new(#{opts.split_sep.inspect})\n\n"
      else
        sep_literal = opts.split_sep.inspect
        io << "__crys_sep = #{sep_literal}\n\n"
      end
    end

    if opts.header_mode?
      io << "__crys_headers = [] of String\n"
      io << "__crys_have_header = false\n\n"
    end

    io << "__crys_sum = 0.0\n" unless opts.sum_expr.empty?
    io << "__crys_count = 0_i64\n" if opts.count_mode?
    io << "\n" unless opts.sum_expr.empty? && !opts.count_mode?
    io << "nr = 0\n"
    io << "fnr = 0\n"
  end

  private def self.emit_line_bindings(io : IO, opts : Options, indent : String) : Nil
    return unless opts.autosplit?

    if indent == "  "
      generate_autosplit(io, opts.split_regex?)
    else
      generate_autosplit_indented(io, opts.split_regex?, indent)
    end
    generate_named_fields(io, opts, indent)
    generate_header_row(io, indent) if opts.header_mode?
  end

  private def self.generate_line_mode_for_files(io : IO, opts : Options) : Nil
    io << "ARGV.each do |path|\n"
    io << "  fnr = 0\n"
    io << "  __crys_have_header = false\n" if opts.header_mode?
    io << "  File.open(path) do |__crys_file|\n"
    io << "    __crys_file.each_line do |__raw_line|\n"
    io << "      nr += 1\n"
    io << "      fnr += 1\n"
    io << "      l = __raw_line.chomp\n"
    emit_line_bindings(io, opts, "      ")
    emit_where_wrapped_action(io, opts, "      ")
    io << "    end\n"
    io << "  end\n"
    io << "end\n"
  end

  private def self.generate_line_mode_for_stdin(io : IO, opts : Options) : Nil
    io << "STDIN.each_line do |__raw_line|\n"
    io << "  nr += 1\n"
    io << "  fnr += 1\n"
    io << "  l = __raw_line.chomp\n"
    emit_line_bindings(io, opts, "  ")
    emit_where_wrapped_action(io, opts, "  ")
    io << "end\n"
  end

  private def self.generate_line_mode(io : IO, opts : Options) : Nil
    generate_line_mode_setup(io, opts)

    if reads_from_files?(opts)
      generate_line_mode_for_files(io, opts)
    else
      generate_line_mode_for_stdin(io, opts)
    end
  end

  private def self.generate_final_code(io : IO, opts : Options) : Nil
    if (!opts.sum_expr.empty? || opts.count_mode?) && opts.final_code.empty?
      io << "\n# --aggregate-final\n"
      io << "puts __crys_sum\n" unless opts.sum_expr.empty?
      io << "puts __crys_count\n" if opts.count_mode?
    end

    return if opts.final_code.empty?

    io << "\n# --final\n"
    io << opts.final_code << "\n"
  end

  def self.generate_code(opts : Options) : String
    io = IO::Memory.new

    io << "# generated by crys\n\n"

    generate_requires(io, opts)
    generate_path_binding(io, opts)
    generate_init_code(io, opts)

    if opts.mode_n?
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
end
