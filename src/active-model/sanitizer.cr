require "sanitize"

module ActiveModel::Sanitizer
  class_getter(common) { Sanitize::Policy::HTMLSanitizer.common }
  class_getter(basic) { Sanitize::Policy::HTMLSanitizer.basic }
  class_getter(inline) { Sanitize::Policy::HTMLSanitizer.inline }
  class_getter(text) { Sanitize::Policy::Text.new }

  protected def self.resolve_policy(name : Symbol) : Sanitize::Policy
    case name
    when :common then common
    when :basic  then basic
    when :inline then inline
    when :text   then text
    else              raise ArgumentError.new("Unknown sanitize policy: #{name}")
    end
  end

  def self.sanitize(value : String, policy : Symbol) : String
    resolve_policy(policy).process(value)
  end

  def self.sanitize(value : Array(String), policy : Symbol) : Array(String)
    p = resolve_policy(policy)
    value.map { |s| p.process(s) }
  end

  # NOTE: post-sanitize de-duplication may shrink the set when two distinct
  # input values collapse to the same sanitized value (e.g. `:text` turns
  # both `"<b>x</b>"` and `"x"` into `"x"`).
  def self.sanitize(value : Set(String), policy : Symbol) : Set(String)
    p = resolve_policy(policy)
    result = Set(String).new(initial_capacity: value.size)
    value.each { |s| result << p.process(s) }
    result
  end

  def self.sanitize(value : Hash(String, String), policy : Symbol) : Hash(String, String)
    p = resolve_policy(policy)
    result = Hash(String, String).new(initial_capacity: value.size)
    value.each { |k, v| result[k] = p.process(v) }
    result
  end
end
