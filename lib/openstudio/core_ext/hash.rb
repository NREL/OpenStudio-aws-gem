class Hash
  def except!(*keys)
    keys.each { |key| delete(key) }
    self
  end
end