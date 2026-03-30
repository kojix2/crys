require "./crys"

begin
  opts = Crys.parse_args(ARGV.to_a)
  Crys.run(opts)
rescue e : ArgumentError
  STDERR.puts "crys: #{e.message}"
  STDERR.puts Crys::USAGE
  exit 1
end
