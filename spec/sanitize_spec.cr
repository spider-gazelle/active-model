require "./spec_helper"

class SanitizedText < ActiveModel::Model
  attribute content : String, sanitize: :text
  attribute title : String # no sanitize
end

class SanitizedCommon < ActiveModel::Model
  attribute body : String?, sanitize: :common
end

class SanitizedInline < ActiveModel::Model
  attribute snippet : String?, sanitize: :inline
end

class SanitizedBasic < ActiveModel::Model
  attribute description : String?, sanitize: :basic
end

class SanitizedWithSetter < ActiveModel::Model
  attribute name : String, sanitize: :text do |value|
    value.try &.upcase
  end
end

class SanitizedMixed < ActiveModel::Model
  attribute safe_html : String?, sanitize: :common
  attribute plain : String?
end

class SanitizedArrayText < ActiveModel::Model
  attribute tags : Array(String), sanitize: :text
end

class SanitizedNilableArrayCommon < ActiveModel::Model
  attribute paragraphs : Array(String)?, sanitize: :common
end

class SanitizedSetText < ActiveModel::Model
  attribute keywords : Set(String), sanitize: :text
end

class SanitizedNilableSetInline < ActiveModel::Model
  attribute snippets : Set(String)?, sanitize: :inline
end

class SanitizedHashCommon < ActiveModel::Model
  attribute fields : Hash(String, String), sanitize: :common
end

class SanitizedNilableHashBasic < ActiveModel::Model
  attribute metadata : Hash(String, String)?, sanitize: :basic
end

class SanitizedArrayWithSetter < ActiveModel::Model
  attribute tags : Array(String), sanitize: :text do |value|
    value.try &.map(&.upcase)
  end
end

class SanitizedArrayOfArrays < ActiveModel::Model
  attribute matrix : Array(Array(String)), sanitize: :text
end

class SanitizedArrayOfHashes < ActiveModel::Model
  attribute records : Array(Hash(String, String)), sanitize: :common
end

class SanitizedHashOfArrays < ActiveModel::Model
  attribute buckets : Hash(String, Array(String)), sanitize: :basic
end

class SanitizedHashOfHashes < ActiveModel::Model
  attribute tree : Hash(String, Hash(String, String)), sanitize: :inline
end

class SanitizedSetInArray < ActiveModel::Model
  attribute groups : Array(Set(String)), sanitize: :text
end

class SanitizedNilableArrayOfArrays < ActiveModel::Model
  attribute matrix : Array(Array(String))?, sanitize: :text
end

class SanitizedNilableHashOfHashes < ActiveModel::Model
  attribute tree : Hash(String, Hash(String, String))?, sanitize: :common
end

class SanitizedJsonAny < ActiveModel::Model
  attribute payload : JSON::Any, sanitize: :text
end

class SanitizedNilableJsonAny < ActiveModel::Model
  attribute payload : JSON::Any?, sanitize: :common
end

class SanitizedJsonAnyWithSetter < ActiveModel::Model
  attribute payload : JSON::Any, sanitize: :text do |value|
    JSON::Any.new({"wrapped" => value})
  end
end

describe "Sanitization" do
  describe ":text policy" do
    it "strips all HTML tags on initialization" do
      model = SanitizedText.new(content: "<b>Hello</b> World")
      model.content.should eq "Hello World"
    end

    it "strips all HTML tags on direct assignment" do
      model = SanitizedText.new(content: "clean")
      model.clear_changes_information
      model.content = "<em>dirty</em>"
      model.content.should eq "dirty"
    end

    it "does not affect non-sanitized attributes" do
      model = SanitizedText.new(content: "test", title: "<b>Bold Title</b>")
      model.title.should eq "<b>Bold Title</b>"
    end

    it "sanitizes values from JSON" do
      model = SanitizedText.from_json(%({"content": "<b>Hello</b>", "title": "<b>Title</b>"}))
      model.content.should eq "Hello"
      model.title.should eq "<b>Title</b>"
    end

    it "sanitizes values from trusted JSON" do
      model = SanitizedText.from_trusted_json(%({"content": "<b>Hello</b>", "title": "<b>Title</b>"}))
      model.content.should eq "Hello"
      model.title.should eq "<b>Title</b>"
    end

    it "sanitizes values from YAML" do
      model = SanitizedText.from_yaml(%({"content": "<b>Hello</b>", "title": "<b>Title</b>"}))
      model.content.should eq "Hello"
      model.title.should eq "<b>Title</b>"
    end
  end

  describe ":common policy" do
    it "strips dangerous tags but keeps common HTML" do
      model = SanitizedCommon.new
      model.body = "<p>Hello</p><script>alert('xss')</script>"
      model.body.should eq "<p>Hello</p>"
    end

    it "preserves common formatting tags" do
      model = SanitizedCommon.new(body: "<p>Hello <b>World</b></p>")
      model.body.should eq "<p>Hello <b>World</b></p>"
    end

    it "handles nil values for nilable fields" do
      model = SanitizedCommon.new
      model.body.should be_nil
    end

    it "handles assigning nil" do
      model = SanitizedCommon.new(body: "<p>Hello</p>")
      model.body = nil
      model.body.should be_nil
    end
  end

  describe ":basic policy" do
    it "strips dangerous tags" do
      model = SanitizedBasic.new(description: "<p>Hello</p><script>alert('xss')</script>")
      model.description.should eq "<p>Hello</p>"
    end

    it "preserves basic formatting" do
      model = SanitizedBasic.new(description: "<b>Bold</b> and <i>italic</i>")
      model.description.should eq "<b>Bold</b> and <i>italic</i>"
    end
  end

  describe ":inline policy" do
    it "strips block elements but keeps inline elements" do
      model = SanitizedInline.new(snippet: "<p>Hello <b>World</b></p>")
      model.snippet.should eq "Hello <b>World</b>"
    end

    it "strips script tags" do
      model = SanitizedInline.new(snippet: "<b>OK</b><script>bad</script>")
      model.snippet.should eq "<b>OK</b>"
    end
  end

  describe "with custom setter block" do
    it "sanitizes before the custom setter runs" do
      model = SanitizedWithSetter.new(name: "<b>hello</b>")
      # First sanitize (text strips tags): "<b>hello</b>" -> "hello"
      # Then custom setter (upcase): "hello" -> "HELLO"
      model.name.should eq "HELLO"
    end

    it "sanitizes then applies setter on direct assignment" do
      model = SanitizedWithSetter.new(name: "init")
      model.name = "<em>world</em>"
      model.name.should eq "WORLD"
    end

    it "sanitizes and applies setter block from JSON" do
      model = SanitizedWithSetter.from_json(%({"name": "<b>hello</b>"}))
      model.name.should eq "HELLO"
    end

    it "sanitizes and applies setter block from YAML" do
      model = SanitizedWithSetter.from_yaml(%({"name": "<b>hello</b>"}))
      model.name.should eq "HELLO"
    end
  end

  describe "mixed sanitized and non-sanitized fields" do
    it "only sanitizes fields with the option set" do
      model = SanitizedMixed.new(safe_html: "<script>xss</script><p>OK</p>", plain: "<script>xss</script><p>OK</p>")
      model.safe_html.should eq "<p>OK</p>"
      model.plain.should eq "<script>xss</script><p>OK</p>"
    end
  end

  describe "change tracking with sanitization" do
    it "tracks changes based on sanitized values" do
      model = SanitizedText.new(content: "hello")
      model.clear_changes_information

      model.content = "<b>world</b>"
      model.content_changed?.should be_true
      model.content.should eq "world"
      model.content_was.should eq "hello"
    end

    it "does not mark as changed when sanitized value matches current" do
      model = SanitizedText.new(content: "hello")
      model.clear_changes_information

      # Assigning the same text wrapped in tags should still result in "hello"
      model.content = "hello"
      model.content_changed?.should be_false
    end
  end

  describe "assign_attributes" do
    it "sanitizes when assigning from named params" do
      model = SanitizedText.new(content: "clean", title: "ok")
      model.assign_attributes(content: "<b>updated</b>")
      model.content.should eq "updated"
    end

    it "sanitizes when assigning from JSON" do
      model = SanitizedText.new(content: "clean", title: "ok")
      model.clear_changes_information

      model.assign_attributes_from_json(%({"content": "<b>updated</b>"}))
      model.content.should eq "updated"
    end

    it "sanitizes when assigning from trusted JSON" do
      model = SanitizedText.new(content: "clean", title: "ok")
      model.clear_changes_information

      model.assign_attributes_from_trusted_json(%({"content": "<b>updated</b>"}))
      model.content.should eq "updated"
    end

    it "sanitizes when assigning from YAML" do
      model = SanitizedText.new(content: "clean", title: "ok")
      model.clear_changes_information

      model.assign_attributes_from_yaml(%({"content": "<b>updated</b>"}))
      model.content.should eq "updated"
    end

    it "sanitizes when assigning from another model" do
      source = SanitizedText.new(content: "<b>dirty</b>", title: "ok")
      target = SanitizedText.new(content: "clean", title: "ok")
      target.clear_changes_information

      target.assign_attributes(source)
      # Source model already sanitized on construction, so target gets sanitized value
      target.content.should eq "dirty"
    end
  end

  describe "HTTP params" do
    it "sanitizes when initializing from HTTP params" do
      params = HTTP::Params.new({"content" => ["<b>Hello</b>"], "title" => ["<b>Title</b>"]})
      model = SanitizedText.new(params)
      model.content.should eq "Hello"
      model.title.should eq "<b>Title</b>"
    end

    it "sanitizes when assigning from HTTP params" do
      model = SanitizedText.new(content: "clean", title: "ok")
      params = HTTP::Params.new({"content" => ["<b>Dirty</b>"]})
      model.assign_attributes(params)
      model.content.should eq "Dirty"
    end
  end

  describe "HTML entities and encoding edge cases" do
    it "passes through entity-encoded markup in :text mode" do
      model = SanitizedText.new(content: "&lt;b&gt;Hello&lt;/b&gt;")
      # Entities are not real tags, so :text leaves them as-is
      model.content.should eq "&lt;b&gt;Hello&lt;/b&gt;"
    end

    it "decodes numeric character references after stripping tags" do
      model = SanitizedText.new(content: "<b>&#72;ello</b>")
      model.content.should eq "Hello"
    end

    it "strips tags that mix entities and real markup" do
      model = SanitizedText.new(content: "<script>alert(&quot;xss&quot;)</script>Safe")
      model.content.should eq "Safe"
    end

    it "handles empty string without error" do
      model = SanitizedText.new(content: "")
      model.content.should eq ""
    end

    it "handles string with only whitespace" do
      model = SanitizedText.new(content: "   ")
      model.content.should eq ""
    end

    it "preserves safe entities in :common mode" do
      model = SanitizedCommon.new(body: "<p>Tom &amp; Jerry</p>")
      model.body.should eq "<p>Tom &amp; Jerry</p>"
    end
  end

  describe "Array(String) fields" do
    it "sanitizes each element on initialization" do
      model = SanitizedArrayText.new(tags: ["<b>one</b>", "<i>two</i>"])
      model.tags.should eq ["one", "two"]
    end

    it "preserves array length when sanitization produces empty strings" do
      model = SanitizedArrayText.new(tags: ["hello", "<script>x</script>"])
      model.tags.should eq ["hello", ""]
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedArrayText.new(tags: ["clean"])
      model.tags = ["<em>dirty</em>", "ok"]
      model.tags.should eq ["dirty", "ok"]
    end

    it "handles empty array without error" do
      model = SanitizedArrayText.new(tags: [] of String)
      model.tags.should eq [] of String
    end

    it "sanitizes from JSON" do
      model = SanitizedArrayText.from_json(%({"tags": ["<b>a</b>", "<i>b</i>"]}))
      model.tags.should eq ["a", "b"]
    end

    it "sanitizes from YAML" do
      model = SanitizedArrayText.from_yaml(%({"tags": ["<b>a</b>", "<i>b</i>"]}))
      model.tags.should eq ["a", "b"]
    end

    it "sanitizes when assigning from JSON" do
      model = SanitizedArrayText.new(tags: ["clean"])
      model.clear_changes_information
      model.assign_attributes_from_json(%({"tags": ["<b>updated</b>"]}))
      model.tags.should eq ["updated"]
    end

    it "tracks changes based on sanitized values" do
      model = SanitizedArrayText.new(tags: ["hello"])
      model.clear_changes_information

      model.tags = ["hello"]
      model.tags_changed?.should be_false
    end

    it "handles nilable Array(String)? with nil value" do
      model = SanitizedNilableArrayCommon.new
      model.paragraphs.should be_nil
    end

    it "sanitizes nilable Array(String)? from JSON" do
      model = SanitizedNilableArrayCommon.from_json(%({"paragraphs": ["<p>safe</p>", "<script>xss</script>"]}))
      model.paragraphs.should eq ["<p>safe</p>", ""]
    end

    it "runs custom setter block after sanitization" do
      model = SanitizedArrayWithSetter.new(tags: ["<b>hello</b>", "world"])
      model.tags.should eq ["HELLO", "WORLD"]
    end
  end

  describe "Set(String) fields" do
    it "sanitizes each element on initialization" do
      model = SanitizedSetText.new(keywords: Set{"<b>foo</b>", "bar"})
      model.keywords.should eq Set{"foo", "bar"}
    end

    it "deduplicates when sanitization collapses two values to the same string" do
      model = SanitizedSetText.new(keywords: Set{"<b>foo</b>", "foo"})
      model.keywords.size.should eq 1
      model.keywords.should eq Set{"foo"}
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedSetText.new(keywords: Set{"clean"})
      model.keywords = Set{"<em>dirty</em>", "ok"}
      model.keywords.should eq Set{"dirty", "ok"}
    end

    it "handles empty set without error" do
      model = SanitizedSetText.new(keywords: Set(String).new)
      model.keywords.empty?.should be_true
    end

    it "sanitizes nilable Set(String)? on initialization" do
      model = SanitizedNilableSetInline.new(snippets: Set{"<p>block</p>", "<b>inline</b>"})
      model.snippets.should eq Set{"block", "<b>inline</b>"}
    end

    it "handles nilable Set(String)? with nil value" do
      model = SanitizedNilableSetInline.new
      model.snippets.should be_nil
    end

    it "sanitizes from JSON" do
      model = SanitizedSetText.from_json(%({"keywords": ["<b>a</b>", "<i>b</i>"]}))
      model.keywords.should eq Set{"a", "b"}
    end

    it "sanitizes from YAML" do
      model = SanitizedSetText.from_yaml(%({"keywords": ["<b>a</b>", "<i>b</i>"]}))
      model.keywords.should eq Set{"a", "b"}
    end
  end

  describe "Hash(String, String) fields" do
    it "sanitizes values but not keys" do
      model = SanitizedHashCommon.new(fields: {"<b>k</b>" => "<p>v</p><script>x</script>"})
      model.fields.should eq({"<b>k</b>" => "<p>v</p>"})
    end

    it "sanitizes each value on initialization" do
      model = SanitizedHashCommon.new(fields: {"a" => "<p>one</p>", "b" => "<p>two</p><script>x</script>"})
      model.fields.should eq({"a" => "<p>one</p>", "b" => "<p>two</p>"})
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedHashCommon.new(fields: {} of String => String)
      model.fields = {"k" => "<p>v</p><script>x</script>"}
      model.fields.should eq({"k" => "<p>v</p>"})
    end

    it "handles empty hash without error" do
      model = SanitizedHashCommon.new(fields: {} of String => String)
      model.fields.empty?.should be_true
    end

    it "handles nilable Hash(String, String)? with nil value" do
      model = SanitizedNilableHashBasic.new
      model.metadata.should be_nil
    end

    it "sanitizes nilable Hash(String, String)? from JSON" do
      model = SanitizedNilableHashBasic.from_json(%({"metadata": {"a": "<b>bold</b>", "b": "<script>x</script>"}}))
      model.metadata.should eq({"a" => "<b>bold</b>", "b" => ""})
    end

    it "sanitizes from YAML" do
      model = SanitizedHashCommon.from_yaml(%({"fields": {"k": "<p>v</p><script>x</script>"}}))
      model.fields.should eq({"k" => "<p>v</p>"})
    end
  end

  describe "Array(Array(String)) fields" do
    it "sanitizes each leaf string on initialization" do
      model = SanitizedArrayOfArrays.new(matrix: [["<b>a</b>", "<i>b</i>"], ["<em>c</em>"]])
      model.matrix.should eq [["a", "b"], ["c"]]
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedArrayOfArrays.new(matrix: [] of Array(String))
      model.matrix = [["<b>x</b>"], ["<i>y</i>", "z"]]
      model.matrix.should eq [["x"], ["y", "z"]]
    end

    it "handles empty outer and inner arrays" do
      model = SanitizedArrayOfArrays.new(matrix: [[] of String, [] of String])
      model.matrix.should eq [[] of String, [] of String]
    end

    it "sanitizes from JSON" do
      model = SanitizedArrayOfArrays.from_json(%({"matrix": [["<b>a</b>"], ["<i>b</i>", "c"]]}))
      model.matrix.should eq [["a"], ["b", "c"]]
    end

    it "sanitizes from YAML" do
      model = SanitizedArrayOfArrays.from_yaml(%({"matrix": [["<b>a</b>"], ["<i>b</i>"]]}))
      model.matrix.should eq [["a"], ["b"]]
    end

    it "tracks changes based on sanitized values" do
      model = SanitizedArrayOfArrays.new(matrix: [["hi"]])
      model.clear_changes_information
      model.matrix = [["hi"]]
      model.matrix_changed?.should be_false
    end
  end

  describe "Array(Hash(String, String)) fields" do
    it "sanitizes hash values on initialization" do
      model = SanitizedArrayOfHashes.new(records: [{"k" => "<p>ok</p><script>x</script>"}])
      model.records.should eq [{"k" => "<p>ok</p>"}]
    end

    it "sanitizes from JSON" do
      model = SanitizedArrayOfHashes.from_json(%({"records": [{"k": "<p>v</p><script>x</script>"}]}))
      model.records.should eq [{"k" => "<p>v</p>"}]
    end
  end

  describe "Hash(String, Array(String)) fields" do
    it "sanitizes inner array elements on initialization" do
      model = SanitizedHashOfArrays.new(buckets: {"a" => ["<b>one</b>", "<i>two</i>"]})
      model.buckets.should eq({"a" => ["<b>one</b>", "<i>two</i>"]})
    end

    it "does not sanitize keys" do
      model = SanitizedHashOfArrays.new(buckets: {"<b>k</b>" => ["<script>x</script>v"]})
      model.buckets.should eq({"<b>k</b>" => ["v"]})
    end

    it "sanitizes from JSON" do
      model = SanitizedHashOfArrays.from_json(%({"buckets": {"a": ["<b>x</b>"]}}))
      model.buckets.should eq({"a" => ["<b>x</b>"]})
    end
  end

  describe "Hash(String, Hash(String, String)) fields" do
    it "sanitizes the innermost values on initialization" do
      # :inline strips block-level wrappers (keeping the text) and preserves inline tags.
      model = SanitizedHashOfHashes.new(tree: {"outer" => {"inner" => "<p>block</p><b>bold</b>"}})
      model.tree.should eq({"outer" => {"inner" => "block<b>bold</b>"}})
    end

    it "preserves keys at every level" do
      model = SanitizedHashOfHashes.new(tree: {"<b>o</b>" => {"<i>i</i>" => "<script>x</script>safe"}})
      model.tree.should eq({"<b>o</b>" => {"<i>i</i>" => "safe"}})
    end

    it "sanitizes from JSON" do
      model = SanitizedHashOfHashes.from_json(%({"tree": {"o": {"i": "<p>block</p><b>bold</b>"}}}))
      model.tree.should eq({"o" => {"i" => "block<b>bold</b>"}})
    end
  end

  describe "Array(Set(String)) fields" do
    it "sanitizes each set element on initialization" do
      model = SanitizedSetInArray.new(groups: [Set{"<b>x</b>", "y"}, Set{"<i>z</i>"}])
      model.groups.should eq [Set{"x", "y"}, Set{"z"}]
    end

    it "sanitizes from JSON" do
      model = SanitizedSetInArray.from_json(%({"groups": [["<b>a</b>", "b"], ["<i>c</i>"]]}))
      model.groups.should eq [Set{"a", "b"}, Set{"c"}]
    end
  end

  describe "nilable nested fields" do
    it "handles Array(Array(String))? with nil" do
      model = SanitizedNilableArrayOfArrays.new
      model.matrix.should be_nil
    end

    it "sanitizes Array(Array(String))? when present" do
      model = SanitizedNilableArrayOfArrays.new(matrix: [["<b>x</b>"]])
      model.matrix.should eq [["x"]]
    end

    it "sanitizes Array(Array(String))? from JSON" do
      model = SanitizedNilableArrayOfArrays.from_json(%({"matrix": [["<b>a</b>"], ["b"]]}))
      model.matrix.should eq [["a"], ["b"]]
    end

    it "handles Hash(String, Hash(String, String))? with nil" do
      model = SanitizedNilableHashOfHashes.new
      model.tree.should be_nil
    end

    it "sanitizes Hash(String, Hash(String, String))? when present" do
      model = SanitizedNilableHashOfHashes.new(tree: {"o" => {"i" => "<p>v</p><script>x</script>"}})
      model.tree.should eq({"o" => {"i" => "<p>v</p>"}})
    end
  end

  describe "JSON::Any fields" do
    it "sanitizes a string leaf on initialization" do
      model = SanitizedJsonAny.new(payload: JSON::Any.new("<b>hello</b>"))
      model.payload.as_s.should eq "hello"
    end

    it "leaves non-string scalars untouched" do
      int_model = SanitizedJsonAny.new(payload: JSON::Any.new(42_i64))
      int_model.payload.as_i64.should eq 42

      float_model = SanitizedJsonAny.new(payload: JSON::Any.new(3.14))
      float_model.payload.as_f.should eq 3.14

      bool_model = SanitizedJsonAny.new(payload: JSON::Any.new(true))
      bool_model.payload.as_bool.should be_true

      nil_model = SanitizedJsonAny.new(payload: JSON::Any.new(nil))
      nil_model.payload.raw.should be_nil
    end

    it "walks nested arrays and sanitizes string leaves" do
      model = SanitizedJsonAny.from_json(%({"payload": ["<b>a</b>", "b", "<i>c</i>"]}))
      model.payload.as_a.map(&.as_s).should eq ["a", "b", "c"]
    end

    it "walks nested objects, sanitizes string values, preserves keys" do
      model = SanitizedJsonAny.from_json(%({"payload": {"<b>k</b>": "<b>v</b>"}}))
      raw = model.payload.as_h
      raw.keys.should eq ["<b>k</b>"]
      raw["<b>k</b>"].as_s.should eq "v"
    end

    it "sanitizes only string elements in mixed-type arrays" do
      model = SanitizedJsonAny.from_json(%({"payload": [1, "<b>x</b>", true, null]}))
      arr = model.payload.as_a
      arr[0].as_i64.should eq 1
      arr[1].as_s.should eq "x"
      arr[2].as_bool.should be_true
      arr[3].raw.should be_nil
    end

    it "walks arbitrarily-nested JSON::Any" do
      model = SanitizedJsonAny.from_json(%({"payload": {"a": {"b": [{"c": "<b>deep</b>"}]}}}))
      model.payload["a"]["b"][0]["c"].as_s.should eq "deep"
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedJsonAny.new(payload: JSON::Any.new("clean"))
      model.payload = JSON::Any.new("<em>dirty</em>")
      model.payload.as_s.should eq "dirty"
    end

    it "sanitizes from JSON" do
      model = SanitizedJsonAny.from_json(%({"payload": "<b>hello</b>"}))
      model.payload.as_s.should eq "hello"
    end

    it "round-trip sanitization is idempotent" do
      first = SanitizedJsonAny.from_json(%({"payload": {"a": "<b>x</b>"}}))
      second = SanitizedJsonAny.from_json(first.to_json)
      first.payload.should eq second.payload
    end

    it "tracks changes based on sanitized values" do
      model = SanitizedJsonAny.new(payload: JSON::Any.new("hello"))
      model.clear_changes_information
      model.payload = JSON::Any.new("hello")
      model.payload_changed?.should be_false
    end
  end

  describe "JSON::Any? fields" do
    it "handles nil value" do
      model = SanitizedNilableJsonAny.new
      model.payload.should be_nil
    end

    it "sanitizes when present" do
      model = SanitizedNilableJsonAny.new(payload: JSON::Any.new("<p>x</p><script>bad</script>"))
      model.payload.not_nil!.as_s.should eq "<p>x</p>"
    end

    it "sanitizes from JSON" do
      model = SanitizedNilableJsonAny.from_json(%({"payload": "<p>safe</p><script>x</script>"}))
      model.payload.not_nil!.as_s.should eq "<p>safe</p>"
    end

    it "handles assigning nil" do
      model = SanitizedNilableJsonAny.new(payload: JSON::Any.new("<b>x</b>"))
      model.payload = nil
      model.payload.should be_nil
    end
  end

  describe "JSON::Any with custom setter block" do
    it "runs setter block after sanitization" do
      model = SanitizedJsonAnyWithSetter.new(payload: JSON::Any.new("<b>hi</b>"))
      # Sanitization strips the tag, then the setter wraps it.
      model.payload["wrapped"].as_s.should eq "hi"
    end
  end
end
