module Sample3
  def self.bucketize(values)
    values.group_by { |v| v % 2 == 0 ? :even : :odd }
  end

  def self.series(n)
    (1..n).map { |i| i * i }
  end
end
