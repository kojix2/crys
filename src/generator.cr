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

    cond = opts.where_conditions.map { |where_cond| "(#{where_cond})" }.join(" && ")
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
    io << "\n" if !opts.sum_expr.empty? || opts.count_mode?
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
    if opts.parallel?
      generate_parallel_line_mode(io, opts)
      return
    end

    generate_line_mode_setup(io, opts)

    if reads_from_files?(opts)
      generate_line_mode_for_files(io, opts)
    else
      generate_line_mode_for_stdin(io, opts)
    end
  end

  private def self.generate_parallel_mode_setup(io : IO, opts : Options) : Nil
    io << "alias CrysLine = Tuple(String, Int32, Int32, String)\n"
    io << "alias CrysBatch = Tuple(Int32, Array(CrysLine))\n"
    io << "alias CrysBatchResult = Tuple(Int32, Array(String))\n\n"

    configured_workers = opts.workers || 0
    configured_queue = opts.queue_batches || 0

    io << "__crys_workers = #{configured_workers}\n"
    io << "if __crys_workers < 1\n"
    io << "  __crys_workers = Fiber::ExecutionContext.default_workers_count\n"
    io << "end\n"
    io << "__crys_batch_lines = #{opts.batch_lines}\n"
    io << "__crys_queue_batches = #{configured_queue}\n"
    io << "if __crys_queue_batches < 1\n"
    io << "  __crys_queue_batches = __crys_workers * 2\n"
    io << "  __crys_queue_batches = 2 if __crys_queue_batches < 2\n"
    io << "  __crys_queue_batches = 64 if __crys_queue_batches > 64\n"
    io << "end\n"
    io << "__crys_ordered = #{opts.unordered? ? "false" : "true"}\n"
    io << "__crys_ctx = Fiber::ExecutionContext::Parallel.new(\"crys\", __crys_workers)\n"
    io << "__crys_in = Channel(CrysBatch?).new(__crys_queue_batches)\n"
    io << "__crys_out = Channel(CrysBatchResult).new(__crys_queue_batches)\n"
    io << "__crys_batch_id = 0\n"
    io << "__crys_total_batches = 0\n"
    io << "__crys_next_nr = 0\n"
    io << "__crys_next_fnr = 0\n\n"
  end

  private def self.generate_parallel_worker(io : IO, opts : Options) : Nil
    io << "__crys_workers.times do\n"
    io << "  __crys_ctx.spawn do\n"
    io << "    loop do\n"
    io << "      __crys_batch = __crys_in.receive\n"
    io << "      break if __crys_batch.nil?\n"
    io << "      __crys_batch = __crys_batch.not_nil!\n"
    io << "      __crys_batch_id = __crys_batch[0]\n"
    io << "      __crys_batch_payload = __crys_batch[1]\n"
    io << "      __crys_out_lines = [] of String\n"
    io << "      __crys_batch_payload.each do |__crys_line|\n"
    io << "        l = __crys_line[0]\n"
    io << "        nr = __crys_line[1]\n"
    io << "        fnr = __crys_line[2]\n"
    io << "        path = __crys_line[3]\n"

    if opts.mode_p?
      io << "        l = begin\n"
      append_indented_code(io, opts.body_code, "          ")
      io << "        end\n"
      io << "        __crys_out_lines << l.to_s\n"
    elsif !opts.map_expr.empty?
      io << "        __crys_out_lines << (#{opts.map_expr}).to_s\n"
    else
      io << "        __crys_out_lines << l if #{opts.select_cond}\n"
    end

    io << "      end\n"
    io << "      __crys_out.send({__crys_batch_id, __crys_out_lines})\n"
    io << "    end\n"
    io << "  end\n"
    io << "end\n\n"
  end

  private def self.generate_parallel_source_stdin(io : IO) : Nil
    io << "__crys_lines = [] of CrysLine\n"
    io << "STDIN.each_line do |__raw_line|\n"
    io << "  __crys_next_nr += 1\n"
    io << "  __crys_next_fnr += 1\n"
    io << "  __crys_lines << {__raw_line.chomp, __crys_next_nr, __crys_next_fnr, \"\"}\n"
    io << "  if __crys_lines.size >= __crys_batch_lines\n"
    io << "    __crys_in.send({__crys_batch_id, __crys_lines})\n"
    io << "    __crys_batch_id += 1\n"
    io << "    __crys_lines = [] of CrysLine\n"
    io << "  end\n"
    io << "end\n"
    io << "unless __crys_lines.empty?\n"
    io << "  __crys_in.send({__crys_batch_id, __crys_lines})\n"
    io << "  __crys_batch_id += 1\n"
    io << "end\n"
    io << "__crys_total_batches = __crys_batch_id\n\n"
  end

  private def self.generate_parallel_source_single_file(io : IO) : Nil
    io << "__crys_input_path = ARGV[0]? || \"\"\n"
    io << "__crys_lines = [] of CrysLine\n"
    io << "File.open(__crys_input_path) do |__crys_file|\n"
    io << "  __crys_file.each_line do |__raw_line|\n"
    io << "    __crys_next_nr += 1\n"
    io << "    __crys_next_fnr += 1\n"
    io << "    __crys_lines << {__raw_line.chomp, __crys_next_nr, __crys_next_fnr, __crys_input_path}\n"
    io << "    if __crys_lines.size >= __crys_batch_lines\n"
    io << "      __crys_in.send({__crys_batch_id, __crys_lines})\n"
    io << "      __crys_batch_id += 1\n"
    io << "      __crys_lines = [] of CrysLine\n"
    io << "    end\n"
    io << "  end\n"
    io << "end\n"
    io << "unless __crys_lines.empty?\n"
    io << "  __crys_in.send({__crys_batch_id, __crys_lines})\n"
    io << "  __crys_batch_id += 1\n"
    io << "end\n"
    io << "__crys_total_batches = __crys_batch_id\n\n"
  end

  private def self.generate_parallel_consumer(io : IO) : Nil
    io << "__crys_workers.times { __crys_in.send(nil) }\n"
    io << "if __crys_ordered\n"
    io << "  __crys_expected = 0\n"
    io << "  __crys_pending = Hash(Int32, Array(String)).new\n"
    io << "  __crys_total_batches.times do\n"
    io << "    __crys_result = __crys_out.receive\n"
    io << "    __crys_pending[__crys_result[0]] = __crys_result[1]\n"
    io << "    while __crys_ready = __crys_pending.delete(__crys_expected)\n"
    io << "      __crys_ready.each { |__line| puts __line }\n"
    io << "      __crys_expected += 1\n"
    io << "    end\n"
    io << "  end\n"
    io << "else\n"
    io << "  __crys_total_batches.times do\n"
    io << "    __crys_result = __crys_out.receive\n"
    io << "    __crys_result[1].each { |__line| puts __line }\n"
    io << "  end\n"
    io << "end\n"
  end

  private def self.generate_parallel_line_mode(io : IO, opts : Options) : Nil
    generate_parallel_mode_setup(io, opts)
    generate_parallel_worker(io, opts)

    if reads_from_files?(opts)
      generate_parallel_source_single_file(io)
    else
      generate_parallel_source_stdin(io)
    end

    generate_parallel_consumer(io)
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
