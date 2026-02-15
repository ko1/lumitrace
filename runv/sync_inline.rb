# frozen_string_literal: true

index_path = File.expand_path("index.html", __dir__)
record_path = File.expand_path("../lib/lumitrace/record_instrument.rb", __dir__)
html_path = File.expand_path("../lib/lumitrace/generate_resulted_html.rb", __dir__)

index = File.read(index_path)
record_code = File.read(record_path).rstrip
html_code = File.read(html_path).lines.reject { |line|
  line.match?(/^\s*require_relative\s+["']record_instrument["']\s*$/)
}.join.rstrip
html_code = html_code.gsub("</script>", "\#{'</scr' + 'ipt>'}")

generated = +"    # LUMITRACE_INLINE_BEGIN\n"
generated << "    lumitrace_code = <<'LUMITRACE'\n"
generated << record_code
generated << "\n\n"
generated << html_code
generated << "\nLUMITRACE\n"
generated << "    # LUMITRACE_INLINE_END\n"

pattern = /    # LUMITRACE_INLINE_BEGIN\n.*?    # LUMITRACE_INLINE_END\n/m
unless index.match?(pattern)
  abort "inline block markers not found in #{index_path}"
end

index.sub!(pattern, generated)
File.write(index_path, index)
puts "updated #{index_path}"
