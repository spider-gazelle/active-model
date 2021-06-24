# :nodoc:
struct Time
  # :nodoc:
  # Parse `Time` from an HTTP param as unix timestamp.
  def self.from_http_param(value : String) : Time
    Time.unix(value.to_i64)
  rescue ArgumentError
    raise TypeCastError.new("Failed to cast #{value} to unix epoch")
  end
end
