require "./spec_helper"

class RemovalTest < ActiveModel::Model
  attribute name : String?
  attribute email : String?
  attribute age : Int32?
end

describe "Field Removal" do
  describe "{field}_removed?" do
    it "tracks when a field is set to nil" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.clear_changes_information

      model.name_removed?.should be_false
      model.name = nil
      model.name_removed?.should be_true
    end

    it "tracks when a string field is set to empty string" do
      model = RemovalTest.new(name: "John")
      model.clear_changes_information

      model.name_removed?.should be_false
      model.name = ""
      model.name_removed?.should be_true
    end

    it "does not mark as removed when set to non-empty value" do
      model = RemovalTest.new(name: "John")
      model.clear_changes_information

      model.name = "Jane"
      model.name_removed?.should be_false
    end

    it "clears removed flag on clear_changes_information" do
      model = RemovalTest.new(name: "John")
      model.name = nil
      model.name_removed?.should be_true

      model.clear_changes_information
      model.name_removed?.should be_false
    end
  end

  describe "assign_attributes with empty strings" do
    it "converts empty strings to nil for nilable fields" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.assign_attributes(name: "", email: "jane@example.com")

      model.name.should be_nil
      model.name_removed?.should be_true
      model.email.should eq "jane@example.com"
    end

    it "tracks removal when assigning empty string" do
      model = RemovalTest.new(name: "John")
      model.clear_changes_information

      model.assign_attributes(name: "")
      model.name_removed?.should be_true
      model.name_changed?.should be_true
    end
  end

  describe "assign_attributes_from_json with empty strings" do
    it "converts empty strings to nil for nilable fields" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.clear_changes_information

      model.assign_attributes_from_json(%({"name": "", "email": "jane@example.com"}))

      model.name.should be_nil
      model.name_removed?.should be_true
      model.email.should eq "jane@example.com"
    end

    it "handles nil values in JSON" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.clear_changes_information

      model.assign_attributes_from_json(%({"name": null}))

      model.name.should be_nil
      model.name_removed?.should be_true
    end
  end

  describe "assign_attributes from model with empty strings" do
    it "converts empty strings to nil when assigning from another model" do
      source = RemovalTest.new(name: "", email: "test@example.com")
      target = RemovalTest.new(name: "John", email: "john@example.com")
      target.clear_changes_information

      target.assign_attributes(source)

      target.name.should be_nil
      target.name_removed?.should be_true
      target.email.should eq "test@example.com"
    end
  end

  describe "assign_attributes_from_trusted_json with empty strings" do
    it "converts empty strings to nil for nilable fields" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.clear_changes_information

      model.assign_attributes_from_trusted_json(%({"name": "", "email": "jane@example.com"}))

      model.name.should be_nil
      model.name_removed?.should be_true
      model.email.should eq "jane@example.com"
    end

    it "handles nil values in trusted JSON" do
      model = RemovalTest.new(name: "John", email: "john@example.com")
      model.clear_changes_information

      model.assign_attributes_from_trusted_json(%({"name": null}))

      model.name.should be_nil
      model.name_removed?.should be_true
    end
  end

  describe "PATCH scenario with from_json" do
    it "handles empty string in JSON as field removal" do
      # Simulate existing model from database
      existing = RemovalTest.new(name: "John", email: "john@example.com", age: 30)
      existing.clear_changes_information

      # Simulate PATCH request with empty name (field removal)
      patch_json = %({"name": "", "age": 31})
      existing.assign_attributes_from_json(patch_json)

      existing.name.should be_nil
      existing.name_removed?.should be_true
      existing.email.should eq "john@example.com"
      existing.age.should eq 31
    end

    it "handles model created from JSON with empty strings" do
      # Simulate PATCH payload
      patch_model = RemovalTest.from_json(%({"name": "", "email": "new@example.com"}))

      # Simulate existing model
      existing = RemovalTest.new(name: "John", email: "john@example.com", age: 30)
      existing.clear_changes_information

      # Apply patch
      existing.assign_attributes(patch_model)

      existing.name.should be_nil
      existing.name_removed?.should be_true
      existing.email.should eq "new@example.com"
      existing.age.should eq 30
    end

    it "handles model created from trusted JSON with empty strings" do
      # Simulate PATCH payload from trusted source
      patch_model = RemovalTest.from_trusted_json(%({"name": "", "email": "admin@example.com"}))

      # Simulate existing model
      existing = RemovalTest.new(name: "John", email: "john@example.com", age: 30)
      existing.clear_changes_information

      # Apply patch
      existing.assign_attributes(patch_model)

      existing.name.should be_nil
      existing.name_removed?.should be_true
      existing.email.should eq "admin@example.com"
      existing.age.should eq 30
    end

    it "tracks multiple field removals in PATCH" do
      existing = RemovalTest.new(name: "John", email: "john@example.com", age: 30)
      existing.clear_changes_information

      patch_json = %({"name": "", "email": ""})
      existing.assign_attributes_from_json(patch_json)

      existing.name.should be_nil
      existing.name_removed?.should be_true
      existing.email.should be_nil
      existing.email_removed?.should be_true
      existing.age.should eq 30
      existing.age_removed?.should be_false
    end

    it "distinguishes between nil and empty string in JSON" do
      existing = RemovalTest.new(name: "John", email: "john@example.com")
      existing.clear_changes_information

      # Both nil and empty string should result in field removal
      existing.assign_attributes_from_json(%({"name": null}))
      existing.name.should be_nil
      existing.name_removed?.should be_true

      existing.clear_changes_information
      existing.name = "John"
      existing.clear_changes_information

      existing.assign_attributes_from_json(%({"name": ""}))
      existing.name.should be_nil
      existing.name_removed?.should be_true
    end
  end

  describe "PUT scenario with from_json" do
    it "handles complete replacement with empty fields" do
      existing = RemovalTest.new(name: "John", email: "john@example.com", age: 30)
      existing.clear_changes_information

      # PUT replaces entire resource
      put_json = %({"name": "", "email": "new@example.com", "age": null})
      existing.assign_attributes_from_trusted_json(put_json)

      existing.name.should be_nil
      existing.name_removed?.should be_true
      existing.email.should eq "new@example.com"
      existing.age.should be_nil
      existing.age_removed?.should be_true
    end
  end
end
