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

class SanitizedHashSymbolKey < ActiveModel::Model
  attribute fields : Hash(Symbol, String), sanitize: :common
end

class SanitizedHashIntKey < ActiveModel::Model
  attribute fields : Hash(Int32, String), sanitize: :text
end

class SanitizedHashSymbolNested < ActiveModel::Model
  attribute fields : Hash(Symbol, Array(String)), sanitize: :basic
end

class SanitizedDequeText < ActiveModel::Model
  attribute history : Deque(String), sanitize: :text
end

class SanitizedNilableDequeCommon < ActiveModel::Model
  attribute history : Deque(String)?, sanitize: :common
end

class SanitizedArrayOfDeques < ActiveModel::Model
  attribute groups : Array(Deque(String)), sanitize: :text
end

class SanitizedTuplePair < ActiveModel::Model
  attribute pair : Tuple(String, String), sanitize: :text
end

class SanitizedTupleNested < ActiveModel::Model
  attribute payload : Tuple(String, Array(String)), sanitize: :common
end

class SanitizedNilableTuple < ActiveModel::Model
  attribute pair : Tuple(String, String)?, sanitize: :basic
end

class SanitizedNamedTupleSimple < ActiveModel::Model
  attribute fields : NamedTuple(a: String, b: String), sanitize: :common
end

class SanitizedNamedTupleNested < ActiveModel::Model
  attribute fields : NamedTuple(title: String, tags: Array(String)), sanitize: :text
end

class SanitizedNilableNamedTuple < ActiveModel::Model
  attribute fields : NamedTuple(name: String, body: String)?, sanitize: :inline
end

class SanitizedStaticArrayText < ActiveModel::Model
  attribute slots : StaticArray(String, 3), sanitize: :text
end

class SanitizedNilableStaticArrayCommon < ActiveModel::Model
  attribute slots : StaticArray(String, 2)?, sanitize: :common
end

class SanitizedSliceText < ActiveModel::Model
  attribute buffer : Slice(String), sanitize: :text
end

class SanitizedRangeStrings < ActiveModel::Model
  attribute span : Range(String, String), sanitize: :text
end

class SanitizedRangeOpenBegin < ActiveModel::Model
  attribute span : Range(Nil, String), sanitize: :common
end

class SanitizedRangeOpenEnd < ActiveModel::Model
  attribute span : Range(String, Nil), sanitize: :inline
end

class SanitizedNilableRangeOpenBegin < ActiveModel::Model
  attribute span : Range(Nil, String)?, sanitize: :common
end

class SanitizedUnionStringInt < ActiveModel::Model
  attribute value : String | Int32, sanitize: :text
end

class SanitizedUnionStringArray < ActiveModel::Model
  attribute value : String | Array(String), sanitize: :common
end

class SanitizedArrayOfUnion < ActiveModel::Model
  attribute items : Array(String | Int32), sanitize: :text
end

class SanitizedNilableUnion < ActiveModel::Model
  attribute value : (String | Int32)?, sanitize: :basic
end

class SanitizableAddress
  include ActiveModel::Sanitizable
  property street : String
  property city : String

  def initialize(@street : String, @city : String)
  end

  def sanitize(policy : Symbol) : self
    @street = ActiveModel::Sanitizer.sanitize(@street, policy)
    @city = ActiveModel::Sanitizer.sanitize(@city, policy)
    self
  end

  def ==(other : SanitizableAddress)
    street == other.street && city == other.city
  end
end

class SanitizedCustomType < ActiveModel::Model
  attribute address : SanitizableAddress, sanitize: :text
end

class SanitizedArrayOfCustom < ActiveModel::Model
  attribute addresses : Array(SanitizableAddress), sanitize: :text
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

  describe "Hash with non-String keys" do
    it "sanitizes Hash(Symbol, String) values" do
      model = SanitizedHashSymbolKey.new(fields: {:a => "<p>hi</p><script>x</script>", :b => "<p>ok</p>"})
      model.fields.should eq({:a => "<p>hi</p>", :b => "<p>ok</p>"})
    end

    it "sanitizes Hash(Int32, String) values" do
      model = SanitizedHashIntKey.new(fields: {1 => "<b>one</b>", 2 => "<i>two</i>"})
      model.fields.should eq({1 => "one", 2 => "two"})
    end

    it "sanitizes nested Hash(Symbol, Array(String))" do
      model = SanitizedHashSymbolNested.new(fields: {:tags => ["<b>x</b>", "<script>bad</script>y"]})
      model.fields[:tags].should eq ["<b>x</b>", "y"]
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedHashSymbolKey.new(fields: {:a => "<p>clean</p>"})
      model.fields = {:a => "<p>x</p><script>y</script>"}
      model.fields.should eq({:a => "<p>x</p>"})
    end
  end

  describe "Deque(String) fields" do
    it "sanitizes each element on initialization" do
      model = SanitizedDequeText.new(history: Deque{"<b>a</b>", "<i>b</i>"})
      model.history.should eq Deque{"a", "b"}
    end

    it "preserves order and length" do
      model = SanitizedDequeText.new(history: Deque{"hi", "<script>x</script>there"})
      model.history.should eq Deque{"hi", "there"}
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedDequeText.new(history: Deque{"clean"})
      model.history = Deque{"<em>dirty</em>", "ok"}
      model.history.should eq Deque{"dirty", "ok"}
    end

    it "handles empty deque without error" do
      model = SanitizedDequeText.new(history: Deque(String).new)
      model.history.empty?.should be_true
    end

    it "sanitizes nilable Deque(String)? on initialization" do
      model = SanitizedNilableDequeCommon.new(history: Deque{"<p>block</p>", "<script>x</script>"})
      model.history.should eq Deque{"<p>block</p>", ""}
    end

    it "handles nilable Deque(String)? with nil value" do
      model = SanitizedNilableDequeCommon.new
      model.history.should be_nil
    end

    it "sanitizes Array(Deque(String))" do
      model = SanitizedArrayOfDeques.new(groups: [Deque{"<b>x</b>"}, Deque{"<i>y</i>"}])
      model.groups.should eq [Deque{"x"}, Deque{"y"}]
    end
  end

  describe "Tuple fields" do
    it "sanitizes each positional element" do
      model = SanitizedTuplePair.new(pair: {"<b>a</b>", "<i>b</i>"})
      model.pair.should eq({"a", "b"})
    end

    it "sanitizes nested Tuple(String, Array(String))" do
      model = SanitizedTupleNested.new(payload: {"<p>t</p><script>x</script>", ["<p>one</p>", "<p>two</p>"]})
      model.payload.should eq({"<p>t</p>", ["<p>one</p>", "<p>two</p>"]})
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedTuplePair.new(pair: {"clean", "ok"})
      model.pair = {"<b>x</b>", "<i>y</i>"}
      model.pair.should eq({"x", "y"})
    end

    it "handles nilable Tuple with nil" do
      model = SanitizedNilableTuple.new
      model.pair.should be_nil
    end

    it "sanitizes nilable Tuple when present" do
      model = SanitizedNilableTuple.new(pair: {"<b>x</b>", "<i>y</i>"})
      model.pair.should eq({"<b>x</b>", "<i>y</i>"})
    end
  end

  describe "NamedTuple fields" do
    it "sanitizes each value, preserves keys" do
      model = SanitizedNamedTupleSimple.new(fields: {a: "<p>hi</p><script>x</script>", b: "<p>ok</p>"})
      model.fields.should eq({a: "<p>hi</p>", b: "<p>ok</p>"})
    end

    it "sanitizes nested NamedTuple values" do
      model = SanitizedNamedTupleNested.new(fields: {title: "<b>T</b>", tags: ["<i>x</i>", "y"]})
      model.fields.should eq({title: "T", tags: ["x", "y"]})
    end

    it "handles nilable NamedTuple with nil" do
      model = SanitizedNilableNamedTuple.new
      model.fields.should be_nil
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedNamedTupleSimple.new(fields: {a: "clean", b: "ok"})
      model.fields = {a: "<p>x</p><script>y</script>", b: "<p>z</p>"}
      model.fields.should eq({a: "<p>x</p>", b: "<p>z</p>"})
    end

    it "preserves the original NamedTuple type" do
      model = SanitizedNamedTupleSimple.new(fields: {a: "<b>hi</b>", b: "ok"})
      model.fields.is_a?(NamedTuple(a: String, b: String)).should be_true
    end
  end

  describe "change tracking with new shapes" do
    it "does not mark Tuple changed when sanitized value matches" do
      model = SanitizedTuplePair.new(pair: {"x", "y"})
      model.clear_changes_information
      model.pair = {"<b>x</b>", "y"}
      model.pair_changed?.should be_false
    end

    it "does not mark NamedTuple changed when sanitized value matches" do
      model = SanitizedNamedTupleSimple.new(fields: {a: "<p>hi</p>", b: "<p>ok</p>"})
      model.clear_changes_information
      model.fields = {a: "<p>hi</p>", b: "<p>ok</p>"}
      model.fields_changed?.should be_false
    end
  end

  describe "StaticArray fields" do
    it "sanitizes each element on initialization" do
      slots = StaticArray(String, 3).new { |i| ["<b>a</b>", "<b>b</b>", "<b>c</b>"][i] }
      model = SanitizedStaticArrayText.new(slots: slots)
      model.slots[0].should eq "a"
      model.slots[1].should eq "b"
      model.slots[2].should eq "c"
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedStaticArrayText.new(slots: StaticArray(String, 3).new { |i| "x" })
      model.clear_changes_information
      model.slots = StaticArray(String, 3).new { |i| "<b>y#{i}</b>" }
      model.slots[0].should eq "y0"
      model.slots[1].should eq "y1"
      model.slots[2].should eq "y2"
    end

    it "preserves the fixed size" do
      slots = StaticArray(String, 3).new { |i| "<b>v</b>" }
      model = SanitizedStaticArrayText.new(slots: slots)
      model.slots.size.should eq 3
    end

    it "handles nilable StaticArray with nil" do
      model = SanitizedNilableStaticArrayCommon.new
      model.slots.should be_nil
    end

    it "sanitizes nilable StaticArray when set" do
      slots = StaticArray(String, 2).new { |i| "<p>x</p><script>bad</script>" }
      model = SanitizedNilableStaticArrayCommon.new(slots: slots)
      model.slots.not_nil!.size.should eq 2
      model.slots.not_nil![0].should eq "<p>x</p>"
      model.slots.not_nil![1].should eq "<p>x</p>"
    end
  end

  describe "Slice(String) fields" do
    it "sanitizes each element on initialization" do
      buffer = Slice(String).new(3) { |i| ["<b>a</b>", "<b>b</b>", "<b>c</b>"][i] }
      model = SanitizedSliceText.new(buffer: buffer)
      model.buffer[0].should eq "a"
      model.buffer[1].should eq "b"
      model.buffer[2].should eq "c"
    end

    it "preserves the slice size" do
      buffer = Slice(String).new(4) { |i| "<b>x</b>" }
      model = SanitizedSliceText.new(buffer: buffer)
      model.buffer.size.should eq 4
    end

    it "sanitizes on direct setter assignment" do
      model = SanitizedSliceText.new(buffer: Slice(String).new(2) { |i| "ok" })
      model.clear_changes_information
      model.buffer = Slice(String).new(2) { |i| "<em>z</em>" }
      model.buffer[0].should eq "z"
      model.buffer[1].should eq "z"
    end

    it "does not mutate the caller's buffer" do
      # Slice wraps a Pointer, so an in-place sanitize would also mutate the
      # caller's storage. Sanitizer.sanitize(Slice) must allocate a fresh slice.
      buffer = Slice(String).new(2) { |i| "<b>x</b>" }
      SanitizedSliceText.new(buffer: buffer)
      buffer[0].should eq "<b>x</b>"
      buffer[1].should eq "<b>x</b>"
    end
  end

  describe "Range fields" do
    it "sanitizes both bounds when present" do
      model = SanitizedRangeStrings.new(span: Range.new("<b>a</b>", "<b>z</b>"))
      model.span.begin.should eq "a"
      model.span.end.should eq "z"
    end

    it "preserves the exclusive? flag" do
      excl = SanitizedRangeStrings.new(span: Range.new("<b>a</b>", "<b>z</b>", true))
      excl.span.exclusive?.should be_true

      incl = SanitizedRangeStrings.new(span: Range.new("<b>a</b>", "<b>z</b>", false))
      incl.span.exclusive?.should be_false
    end

    it "passes through nil begin for open-ended Range(Nil, String)" do
      model = SanitizedRangeOpenBegin.new(span: Range.new(nil, "<p>top</p><script>x</script>", false))
      model.span.begin.should be_nil
      model.span.end.should eq "<p>top</p>"
    end

    it "passes through nil end for open-ended Range(String, Nil)" do
      model = SanitizedRangeOpenEnd.new(span: Range.new("<p>start</p><script>x</script>", nil, false))
      model.span.begin.should eq "start"
      model.span.end.should be_nil
    end

    it "does not call Range#empty? on a nilable beginless Range via assign_attributes" do
      # Regression: the empty-string-removal logic in `assign_attributes` calls
      # value.empty? when the field is nilable, and Range#empty? raises on
      # beginless/endless ranges. The guard must skip Range values.
      model = SanitizedNilableRangeOpenBegin.new
      model.assign_attributes(span: Range.new(nil, "<p>x</p><script>bad</script>", false))
      model.span.not_nil!.begin.should be_nil
      model.span.not_nil!.end.should eq "<p>x</p>"
    end
  end

  describe "Union types with at least one sanitizable arm" do
    it "sanitizes when the value is the String arm" do
      model = SanitizedUnionStringInt.new(value: "<b>hello</b>")
      model.value.should eq "hello"
    end

    it "passes through the Int32 arm unchanged" do
      model = SanitizedUnionStringInt.new(value: 42)
      model.value.should eq 42
    end

    it "sanitizes when the value is the Array(String) arm" do
      model = SanitizedUnionStringArray.new(value: ["<p>a</p>", "<p>b</p><script>bad</script>"])
      result = model.value.as(Array(String))
      result[0].should eq "<p>a</p>"
      result[1].should eq "<p>b</p>"
    end

    it "sanitizes when the value is the String arm of a String|Array union" do
      model = SanitizedUnionStringArray.new(value: "<p>solo</p>")
      model.value.should eq "<p>solo</p>"
    end

    it "sanitizes only String elements inside Array(String | Int32)" do
      model = SanitizedArrayOfUnion.new(items: ["<b>x</b>", 1, "<i>y</i>", 2])
      model.items[0].should eq "x"
      model.items[1].should eq 1
      model.items[2].should eq "y"
      model.items[3].should eq 2
    end

    it "handles nilable union with nil" do
      model = SanitizedNilableUnion.new
      model.value.should be_nil
    end

    it "sanitizes the String arm of a nilable union" do
      model = SanitizedNilableUnion.new(value: "<b>x</b>")
      model.value.should eq "<b>x</b>"
    end

    it "passes through the Int32 arm of a nilable union" do
      model = SanitizedNilableUnion.new(value: 7)
      model.value.should eq 7
    end
  end

  describe "User-defined Sanitizable types" do
    it "calls user-defined sanitize on initialization" do
      address = SanitizableAddress.new("<b>123 Main</b>", "<b>Springfield</b>")
      model = SanitizedCustomType.new(address: address)
      model.address.street.should eq "123 Main"
      model.address.city.should eq "Springfield"
    end

    it "calls user-defined sanitize on setter assignment" do
      address = SanitizableAddress.new("ok", "ok")
      model = SanitizedCustomType.new(address: address)
      model.clear_changes_information
      model.address = SanitizableAddress.new("<i>new</i>", "<i>place</i>")
      model.address.street.should eq "new"
      model.address.city.should eq "place"
    end

    it "delegates inside Array(Sanitizable)" do
      addresses = [
        SanitizableAddress.new("<b>1</b>", "<b>a</b>"),
        SanitizableAddress.new("<b>2</b>", "<b>b</b>"),
      ]
      model = SanitizedArrayOfCustom.new(addresses: addresses)
      model.addresses[0].street.should eq "1"
      model.addresses[0].city.should eq "a"
      model.addresses[1].street.should eq "2"
      model.addresses[1].city.should eq "b"
    end
  end
end
