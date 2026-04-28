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
end
