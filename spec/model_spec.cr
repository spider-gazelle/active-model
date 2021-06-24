require "./spec_helper"

abstract class Abstract < ActiveModel::Model
end

# This should not cause compilation errors
class NoAttributes < Abstract
end

# Inheritance should be supported
class BaseKlass < Abstract
  attribute string : String = ->{ "hello" }
  attribute integer : Int32 = 45
  attribute no_default : String
end

class AttributeOptions < ActiveModel::Model
  attribute time : Time, converter: Time::EpochConverter
  attribute bob : String = "Bobby", mass_assignment: false

  attribute feeling : String, persistence: false
  attribute weird : String | Int32
end

class SetterBlock < BaseKlass
  attribute that_is : String = "cool"
  attribute tricky : String do |t|
    self.that_is = "not ok"
    t.try &.downcase
  end
end

class SerializationGroups < BaseKlass
  attribute everywhere : String = "hi", serialization_group: [:admin, :user, :public]
  attribute joined : Int64 = 0, serialization_group: [:admin, :user]
  attribute mates : Int64 = 0, serialization_group: :user
  attribute another : String = "ok"

  define_to_json :some, only: [:joined, :another]
  define_to_json :most, except: :everywhere
  define_to_json :with_method, only: :joined, methods: :foo

  getter foo = "foo"
end

class Inheritance < BaseKlass
  attribute boolean : Bool = true

  macro __customize_orm__
    {% for name, type in FIELDS %}
      def {{name}}_custom
        @{{name}}
      end
    {% end %}
  end
end

class EnumAttributes < ActiveModel::Model
  enum Size
    Small
    Medium
    Large
  end

  enum Product
    Nuggets
    Burger
    Fries
  end

  attribute size : Size, converter: Enum::ValueConverter(Size), custom_tag: "what what"
  attribute product : Product = Product::Fries
end

class Changes < BaseKlass
  attribute arr : Array(Int32) = [1, 2, 3]
end

class Defaults < BaseKlass
  attribute false_default : Bool = false
end

describe ActiveModel::Model do
  describe "class definitions" do
    it "should provide the list of attributes" do
      NoAttributes.attributes.should eq [] of Nil
      BaseKlass.attributes.should eq [:string, :integer, :no_default]
      Inheritance.attributes.should eq [:boolean, :string, :integer, :no_default]
    end
  end

  describe "initialization" do
    it "creates a new model with defaults" do
      bk = Defaults.new
      bk.attributes.should eq({
        :string        => "hello",
        :integer       => 45,
        :false_default => false,
        :no_default    => nil,
      })
    end

    it "creates a new inherited model with defaults" do
      i = Inheritance.new
      i.attributes.should eq({
        :boolean    => true,
        :string     => "hello",
        :integer    => 45,
        :no_default => nil,
      })
    end

    it "creates a new model from JSON" do
      bk = BaseKlass.from_json("{\"boolean\": false, \"integer\": 67}")
      bk.attributes.should eq({
        :string     => "hello",
        :integer    => 67,
        :no_default => nil,
      })

      i = Inheritance.from_json("{\"boolean\": false, \"integer\": 67}")
      i.attributes.should eq({
        :boolean    => false,
        :string     => "hello",
        :integer    => 67,
        :no_default => nil,
      })
    end

    it "uses named params for initialization" do
      bk = BaseKlass.new string: "bob", no_default: "jane"
      bk.attributes.should eq({
        :string     => "bob",
        :integer    => 45,
        :no_default => "jane",
      })

      i = Inheritance.new string: "bob", boolean: false, integer: 2
      i.attributes.should eq({
        :boolean    => false,
        :string     => "bob",
        :integer    => 2,
        :no_default => nil,
      })
    end

    it "uses HTTP Params for initialization" do
      params = HTTP::Params.new({"string" => ["bob"], "no_default" => ["jane"]})
      bk = BaseKlass.new params

      bk.attributes.should eq({
        :string     => "bob",
        :integer    => 45,
        :no_default => "jane",
      })

      i = Inheritance.new({"string" => "bob", "no_default" => "jane", "boolean" => "true"})
      i.attributes.should eq({
        :boolean    => true,
        :string     => "bob",
        :integer    => 45,
        :no_default => "jane",
      })

      i = Inheritance.new({"string" => "bob", "integer" => "123", "boolean" => "false"})
      i.attributes.should eq({
        :boolean    => false,
        :string     => "bob",
        :integer    => 123,
        :no_default => nil,
      })
    end
  end

  describe "attribute accessors" do
    it "should return attribute values" do
      bk = BaseKlass.new
      bk.string.should eq "hello"
      bk.integer.should eq 45

      expect_raises(NilAssertionError) do
        bk.no_default
      end

      expect_raises(NilAssertionError) do
        bk.no_default_default
      end

      i = Inheritance.new
      i.boolean.should eq true
      i.string.should eq "hello"
      i.integer.should eq 45

      expect_raises(NilAssertionError) do
        i.no_default
      end
    end

    it "should allow attribute assignment" do
      bk = BaseKlass.new
      bk.string.should eq "hello"
      bk.string = "what"
      bk.string.should eq "what"

      bk.attributes.should eq({
        :string     => "what",
        :integer    => 45,
        :no_default => nil,
      })

      i = Inheritance.new
      i.boolean.should eq true
      i.boolean = false
      i.boolean.should eq false

      i.attributes.should eq({
        :boolean    => false,
        :string     => "hello",
        :integer    => 45,
        :no_default => nil,
      })
    end

    it "should allow overriding of assignment" do
      m = SetterBlock.new
      m.that_is.should eq "cool"

      m.tricky = "BUSINESS"
      m.tricky.should eq "business"
      m.that_is.should eq "not ok"
    end
  end

  describe "enum attributes" do
    it "should allow enums as attributes" do
      model = EnumAttributes.new(size: EnumAttributes::Size::Medium)
      model.size.should eq EnumAttributes::Size::Medium
      model.product.should eq EnumAttributes::Product::Fries
    end

    it "should serialize/deserialize enum attributes" do
      model = EnumAttributes.new(size: EnumAttributes::Size::Medium)
      model_json = model.to_json
      parsed_model = EnumAttributes.from_trusted_json(model_json)
      parsed_model.product.should eq model.product
      parsed_model.size.should eq model.size
      parsed_model.attributes.should eq model.attributes
    end

    it "should serialize enum attributes to a concrete value" do
      model = EnumAttributes.new(size: EnumAttributes::Size::Medium)

      json = JSON.parse(model.to_json)
      yaml = YAML.parse(model.to_yaml)

      yaml["size"].should eq EnumAttributes::Size::Medium.to_i
      json["product"].should eq EnumAttributes::Product::Fries.to_s.downcase
    end

    it "tracks changes to enum attributes" do
      model = EnumAttributes.new(size: EnumAttributes::Size::Medium)
      model.clear_changes_information

      model.size_changed?.should be_false
      model.size = EnumAttributes::Size::Small
      model.size_changed?.should be_true
      model.size_was.should eq EnumAttributes::Size::Medium

      model.clear_changes_information
      model.size_will_change!
      model.size_changed?.should be_true
    end
  end

  describe "#assign_attributes_from_json" do
    it "updates from IO" do
      base = BaseKlass.new
      updated_attributes = {integer: 100}

      update_json = updated_attributes.to_json

      body = IO::Sized.new(IO::Memory.new(update_json), read_size: update_json.bytesize)

      base.assign_attributes_from_json(body)
      base.integer.should eq 100
    end

    it "updates from String" do
      base = BaseKlass.new
      updated_attributes = {integer: 100}
      base.assign_attributes_from_json(updated_attributes.to_json)
      base.integer.should eq 100
    end
  end

  describe "#assign_attributes_from_yaml" do
    it "updates from IO" do
      base = BaseKlass.new
      updated_attributes = {integer: 100}

      update_yaml = updated_attributes.to_yaml.to_s
      body = IO::Sized.new(IO::Memory.new(update_yaml), read_size: update_yaml.bytesize)

      base.assign_attributes_from_yaml(body)
      base.integer.should eq 100
    end

    it "updates from String" do
      base = BaseKlass.new
      updated_attributes = {integer: 100}
      base.assign_attributes_from_yaml(updated_attributes.to_yaml.to_s)
      base.integer.should eq 100
    end
  end

  describe "assign_attributes" do
    it "affects changes metadata" do
      bk = BaseKlass.new
      bk.clear_changes_information

      bk.assign_attributes(string: "what")
      bk.changed_attributes.should eq({
        :string => "what",
      })
    end

    it "uses HTTP Params for initialization" do
      bk = BaseKlass.new
      params = HTTP::Params.new({"string" => ["bob"], "no_default" => ["jane"]})
      bk.assign_attributes(params)

      bk.attributes.should eq({
        :string     => "bob",
        :integer    => 45,
        :no_default => "jane",
      })
    end

    it "respects mass assignment preference option" do
      options = AttributeOptions.new

      options.assign_attributes(weird: "weird", bob: "bilbo")
      options.weird.should eq "weird"
      options.bob.should eq "Bobby"
    end
  end

  describe "serialization" do
    it "#to_json" do
      i = Inheritance.new
      i.to_json.should eq "{\"boolean\":true,\"string\":\"hello\",\"integer\":45}"

      i.no_default = "test"
      i.to_json.should eq "{\"boolean\":true,\"string\":\"hello\",\"integer\":45,\"no_default\":\"test\"}"
    end

    m = SerializationGroups.new

    it "`serialization_group` optio ngenerates serializers" do
      m.to_admin_json.should eq ({everywhere: m.everywhere, joined: m.joined}).to_json
      m.to_user_json.should eq ({everywhere: m.everywhere, joined: m.joined, mates: m.mates}).to_json
      m.to_public_json.should eq ({everywhere: m.everywhere}).to_json
    end

    describe "define_to_json" do
      it "selects for attributes in `only`" do
        m.to_some_json.should eq ({joined: m.joined, another: m.another}).to_json
      end

      it "rejects attributes in `except`" do
        m.to_most_json.should eq ({joined: m.joined, mates: m.mates, another: m.another}).to_json
      end

      it "includes methods via `methods`" do
        m.to_with_method_json.should eq ({joined: m.joined, foo: m.foo}).to_json
      end
    end
  end

  describe "change tracking" do
    it "should track changes" do
      BaseKlass.new.changed_attributes.should eq({:string => "hello", :integer => 45})
      klass = Inheritance.new
      klass.changed_attributes.should eq({:boolean => true, :string => "hello", :integer => 45})
      klass.string_change.should eq ({nil, "hello"})
    end

    it "should allow changes information to be cleared" do
      klass = Inheritance.new
      klass.changed_attributes.should eq({:boolean => true, :string => "hello", :integer => 45})
      klass.clear_changes_information
      klass.changed_attributes.should eq({} of Nil => Nil)
      klass.changed?.should eq false
      klass.no_default_changed?.should eq false
      klass.no_default = "bob"
      klass.no_default_changed?.should eq true
      klass.no_default_change.should eq ({nil, "bob"})
      klass.changed?.should eq true
      klass.changed_attributes.should eq({:no_default => "bob"})

      klass.string_change.should eq nil
      klass.string = "else"
      klass.string_change.should eq ({"hello", "else"})
    end

    it "should be able to mark attributes as changed" do
      klass = Changes.new
      klass.clear_changes_information
      klass.arr.should eq [1, 2, 3]
      arr = klass.arr
      raise "no array" unless arr
      arr << 123
      klass.arr.should eq [1, 2, 3, 123]
      klass.arr_changed?.should eq false
      klass.changed_attributes.should eq({} of Nil => Nil)
      klass.arr_will_change!
      klass.arr_changed?.should eq true
      klass.changed_attributes.should eq({:arr => [1, 2, 3, 123]})

      arr << 456
      klass.changed_attributes.should eq({:arr => [1, 2, 3, 123, 456]})
      klass.arr_change.should eq({[1, 2, 3, 123], [1, 2, 3, 123, 456]})
    end

    it "should restore changes" do
      klass = Inheritance.new
      klass.clear_changes_information
      klass.changed_attributes.should eq({} of Nil => Nil)

      klass.string = "bob"
      klass.string_changed?.should eq true
      klass.string_change.should eq({"hello", "bob"})

      klass.restore_attributes
      klass.string_changed?.should eq false
      klass.string.should eq "hello"
    end

    it "should serialise changes to json" do
      model = AttributeOptions.new(bob: "lob law")
      model.clear_changes_information
      new_time = Time.unix(100000)
      model.time = new_time

      changes = JSON.parse(model.changed_json).as_h
      changes.keys.size.should eq 1
      changes["time"].should eq new_time.to_unix
    end

    it "should serialise changes to yaml" do
      model = AttributeOptions.new(bob: "lob law")
      model.clear_changes_information
      new_time = Time.unix(100000)
      model.time = new_time

      changes = YAML.parse(model.changed_yaml).as_h
      changes.keys.size.should eq 1
      changes["time"].should eq new_time.to_unix
    end
  end

  describe "attribute options" do
    it "should convert values using json converters" do
      AttributeOptions.attributes.should eq [:time, :bob, :feeling, :weird]
      opts = AttributeOptions.from_json(%({"time": 1459859781, "bob": "Angus", "weird": 34}))
      opts.time.should eq Time.unix(1459859781)
      opts.to_json.should eq %({"time":1459859781,"bob":"Bobby","weird":34})
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should not assign attributes protected from json mass assignment" do
      opts = AttributeOptions.from_json(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Bobby"
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should assign attributes protected from json mass assignment where data source is trusted" do
      opts = AttributeOptions.from_trusted_json(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Steve"
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should not assign updated attributes protected from json mass assignment" do
      opts = AttributeOptions.from_json(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Bobby"

      opts.assign_attributes_from_json(%({"time": 1459859782, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859782)
      opts.bob.should eq "Bobby"

      opts.changed_attributes.should eq({:time => Time.unix(1459859782)})
    end

    it "should assign updated attributes protected from json mass assignment where data source is trusted" do
      opts = AttributeOptions.from_trusted_json(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Steve"

      opts.assign_attributes_from_trusted_json(%({"time": 1459859782, "bob": "James"}))
      opts.time.should eq Time.unix(1459859782)
      opts.bob.should eq "James"

      opts.changed_attributes.should eq({:time => Time.unix(1459859782), :bob => "James"})
    end

    it "should convert values using yaml converters" do
      AttributeOptions.attributes.should eq [:time, :bob, :feeling, :weird]
      opts = AttributeOptions.from_yaml(%({"time": 1459859781, "bob": "Angus", "weird": 34}))
      opts.time.should eq Time.unix(1459859781)
      opts.to_json.should eq %({"time":1459859781,"bob":"Bobby","weird":34})
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should not assign attributes protected from yaml mass assignment" do
      opts = AttributeOptions.from_yaml(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Bobby"
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should assign attributes protected from yaml mass assignment where data source is trusted" do
      opts = AttributeOptions.from_trusted_yaml(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Steve"
      opts.changed_attributes.should eq({} of Nil => Nil)
    end

    it "should not assign updated attributes protected from yaml mass assignment" do
      opts = AttributeOptions.from_yaml(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Bobby"

      opts.assign_attributes_from_yaml(%({"time": 1459859782, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859782)
      opts.bob.should eq "Bobby"

      opts.changed_attributes.should eq({:time => Time.unix(1459859782)})
    end

    it "should assign updated attributes protected from yaml mass assignment where data source is trusted" do
      opts = AttributeOptions.from_trusted_yaml(%({"time": 1459859781, "bob": "Steve"}))
      opts.time.should eq Time.unix(1459859781)
      opts.bob.should eq "Steve"

      opts.assign_attributes_from_trusted_yaml(%({"time": 1459859782, "bob": "James"}))
      opts.time.should eq Time.unix(1459859782)
      opts.bob.should eq "James"

      opts.changed_attributes.should eq({:time => Time.unix(1459859782), :bob => "James"})
    end

    it "#attributes_tuple creates a NamedTuple of attributes" do
      klass = BaseKlass.new
      klass.attributes_tuple.should be_a(NamedTuple(string: String?, integer: Int32?, no_default: String?))
      klass.attributes_tuple.should eq({string: "hello", integer: 45, no_default: nil})
    end

    describe "persistence" do
      it "should allow non-persisted attributes" do
        time = Time.utc
        bob = "sick"
        feeling = "ill"
        weird = "object"

        model = AttributeOptions.new(time: time, bob: bob, feeling: feeling, weird: weird)
        model.persistent_attributes.should eq ({
          :time  => time,
          :bob   => bob,
          :weird => weird,
        })
        model.attributes.should eq ({
          :time    => time,
          :bob     => bob,
          :weird   => weird,
          :feeling => feeling,
        })
      end

      it "should prevent json serialisation of non-persisted attributes" do
        time = Time.utc
        bob = "lob"
        feeling = "free"
        weird = "sauce"

        model = AttributeOptions.new(time: time, bob: bob, feeling: feeling, weird: weird)
        json = model.to_json

        # Should not serialize the non-persisted field
        JSON.parse(json)["feeling"]?.should be_nil

        # From json ignores the field
        deserialised_model = AttributeOptions.from_trusted_json(json)
        deserialised_model.feeling.should be_nil
      end
    end
  end
end
