require "sanitize"

module ActiveModel::Sanitizer
  class_getter(common) { Sanitize::Policy::HTMLSanitizer.common }
  class_getter(basic) { Sanitize::Policy::HTMLSanitizer.basic }
  class_getter(inline) { Sanitize::Policy::HTMLSanitizer.inline }
  class_getter(text) { Sanitize::Policy::Text.new }
end
