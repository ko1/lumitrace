require './sample/sample2'
require './sample/sample3'

def score(n)
  base = n + 1
  scaled = Sample2.scale(base)
  squares = Sample3.series(n)
  squares.sum + scaled
end

labels = []
totals = []

3.times do
  n = it
  total = score(n)
  labels << Sample2.format("n#{n}", total)
  totals << total
end

flags = totals.map { |v| v > 5 }
stats = {
  count: totals.length,
  max: totals.max,
  min: totals.min
}

buckets = Sample3.bucketize(totals)
summary = "#{stats[:count]} items, max=#{stats[:max]}"

puts labels.join(", ")
p flags
p stats
p buckets
p summary
