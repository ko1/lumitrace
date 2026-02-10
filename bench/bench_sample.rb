# frozen_string_literal: true

# Small-ish workload for lumitrace timing.
# Run:
#   time lumitrace bench_sample.rb

WORDS = %w[alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega].freeze

class MiniReport
  def initialize(size)
    @size = size
  end

  def run
    data = build_data
    counts = count_words(data)
    stats = summarize(counts)
    format_output(stats)
  end

  private

  def build_data
    out = []
    @size.times do |i|
      base = WORDS[i % WORDS.length]
      out << "#{base}-#{i}"
      if i % 7 == 0
        out << base.upcase
      elsif i % 5 == 0
        out << base.reverse
      end
    end
    out
  end

  def count_words(data)
    counts = Hash.new(0)
    data.each do |w|
      key = w.downcase
      counts[key] += 1
    end
    counts
  end

  def summarize(counts)
    top = counts.sort_by { |_, v| -v }.first(5)
    total = counts.values.sum
    {
      total: total,
      unique: counts.length,
      top: top
    }
  end

  def format_output(stats)
    lines = []
    lines << "total=#{stats[:total]} unique=#{stats[:unique]}"
    stats[:top].each_with_index do |(k, v), idx|
      lines << "#{idx + 1}. #{k}=#{v}"
    end
    lines.join("\n")
  end
end

n = (ENV["N"] || 1000).to_i
report = MiniReport.new(n)
result = report.run

# Keep output minimal but non-empty
puts result if ENV["PRINT"] == "1"
