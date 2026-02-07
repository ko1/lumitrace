module Sample2
  FACTOR = 2

  def self.format(label, value)
    "#{label}=#{value}"
  end

  def self.scale(value)
    value * FACTOR
  end
end
