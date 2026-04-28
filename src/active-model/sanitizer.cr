require "sanitize"

module ActiveModel::Sanitizer
  COMMON = Sanitize::Policy::HTMLSanitizer.common
  BASIC  = Sanitize::Policy::HTMLSanitizer.basic
  INLINE = Sanitize::Policy::HTMLSanitizer.inline
  TEXT   = Sanitize::Policy::Text.new
end
