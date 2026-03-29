require "./crys"

begin
  opts = parse_args(ARGV.to_a)
  run(opts)
rescue e : ArgumentError
  STDERR.puts "crys: #{e.message}"
  STDERR.puts USAGE
  exit 1
end
