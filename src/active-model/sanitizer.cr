require "json"
require "sanitize"

# Opt-in interface for user-defined types that want to participate in
# `attribute foo : MyType, sanitize: :text` declarations. Include this
# module and implement `sanitize(policy : Symbol) : self`. The macro-time
# type walker accepts any type `<` this module, and the runtime delegates
# to the type's own `sanitize` method.
module ActiveModel::Sanitizable
  abstract def sanitize(policy : Symbol) : self
end

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
  # both `"<b>x</b>"` and `"x"` into `"x"`). Use `Array(T)` if order/length
  # must be preserved.
  def self.sanitize(value : Set(T), policy : Symbol) : Set(T) forall T
    result = Set(T).new(initial_capacity: value.size)
    value.each { |v| result << sanitize(v, policy).as(T) }
    result
  end

  # Recursive Hash. Keys are identifiers and are not sanitized,
  # so K can be any type; only V is walked.
  def self.sanitize(value : Hash(K, V), policy : Symbol) : Hash(K, V) forall K, V
    result = Hash(K, V).new(initial_capacity: value.size)
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

  # User-defined types opt in by including `ActiveModel::Sanitizable`.
  def self.sanitize(value : ::ActiveModel::Sanitizable, policy : Symbol)
    value.sanitize(policy)
  end

  # Catch-all for union types. The strongly-typed overloads above win for
  # concrete static types; this fires only when `value`'s compile-time type
  # is a union — which the macro walker has verified contains at least one
  # sanitizable arm. Used both for top-level union attributes (e.g.
  # `String | Int32`) and for union elements inside accepted containers
  # (e.g. `Array(String | Int32)`). The recursive `sanitize(value, policy)`
  # calls dispatch back to the strongly-typed overloads because Crystal
  # narrows `value`'s type inside each `is_a?` branch.
  def self.sanitize(value, policy : Symbol)
    if value.is_a?(String)
      resolve_policy(policy).process(value)
    elsif value.is_a?(JSON::Any)
      sanitize(value, policy)
    elsif value.is_a?(::ActiveModel::Sanitizable)
      value.sanitize(policy)
    elsif value.is_a?(Array) || value.is_a?(Set) || value.is_a?(Hash)
      sanitize(value, policy)
    else
      value
    end
  end
end
