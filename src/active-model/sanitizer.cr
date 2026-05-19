require "json"
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

  # Base case: a single String.
  def self.sanitize(value : String, policy : Symbol) : String
    resolve_policy(policy).process(value)
  end

  # Recursive Array(T) — dispatches to the appropriate `sanitize` for each element.
  def self.sanitize(value : Array(T), policy : Symbol) : Array(T) forall T
    value.map { |v| sanitize(v, policy).as(T) }
  end

  # Recursive Set(T).
  # NOTE: post-sanitize de-duplication may shrink the set when two distinct
  # input values collapse to the same sanitized value (e.g. `:text` turns
  # both `"<b>x</b>"` and `"x"` into `"x"`). For nested element types,
  # equality is element-wise — two arrays that sanitize to identical content
  # will also merge.
  def self.sanitize(value : Set(T), policy : Symbol) : Set(T) forall T
    result = Set(T).new(initial_capacity: value.size)
    value.each { |v| result << sanitize(v, policy).as(T) }
    result
  end

  # Recursive Hash(String, V). Keys are identifiers and are not sanitized.
  def self.sanitize(value : Hash(String, V), policy : Symbol) : Hash(String, V) forall V
    result = Hash(String, V).new(initial_capacity: value.size)
    value.each { |k, v| result[k] = sanitize(v, policy).as(V) }
    result
  end

  # JSON::Any — walk the tree, sanitize string leaves only.
  # Non-string scalars (Int64, Float64, Bool, Nil) pass through untouched.
  def self.sanitize(value : JSON::Any, policy : Symbol) : JSON::Any
    raw = value.raw
    case raw
    when String
      JSON::Any.new(resolve_policy(policy).process(raw))
    when Array
      JSON::Any.new(raw.map { |item| sanitize(item, policy).as(JSON::Any) })
    when Hash
      result = Hash(String, JSON::Any).new(initial_capacity: raw.size)
      raw.each { |k, v| result[k] = sanitize(v, policy) }
      JSON::Any.new(result)
    else
      value
    end
  end
end
