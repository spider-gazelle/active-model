# Spider-Gazelle ActiveModel

[![Build Status](https://travis-ci.org/spider-gazelle/active-model.svg?branch=master)](https://travis-ci.org/spider-gazelle/active-model)

Active Model provides a known set of interfaces for usage in model classes. Active Model also helps with building custom ORMs.

## Usage

Please also checkout the [detailed guide](https://spider-gazelle.net/#/models/basics).

### Active Model

ActiveModel::Model should be used as the base class for your ORM

```crystal
require "active-model"

class Person < ActiveModel::Model
  attribute name : String = "default value"
  attribute age : Int32
end

p = Person.from_json("\"name\": \"Bob Jane\"")
p.name # => "Bob Jane"
p.to_json # => "\"name\":\"Bob Jane\""
p.attributes # => {:name => "Bob Jane", :age => nil}

p.age = 32
p.attributes # => {:name => "Bob Jane", :age => 32}
```

The `attribute` macro takes two parameters. The field name with type and an optional default value.

You can also define enum attributes!<br>
The default serialisation for enums is to a downcased string. Use [`Enum::ValueConverter(T)`](https://crystal-lang.org/api/latest/Enum/ValueConverter.html) if you want to serialise to the value backing members of the enum.

```ruby
require "active-model"

class Order < ActiveModel::Model
  enum Product
   Fries
   Burger
  end

  attribute product : Product = Product::Fries
end
```

#### Validations

ActiveModel::Validators is a mix-in that you include in your class. Similar to those supported by Rails: <http://guides.rubyonrails.org/active_record_validations.html>

```crystal
require "active-model"

class Person < ActiveModel::Model
  include ActiveModel::Validation

  attribute name : String
  attribute age : Int32

  validates :name, presence: true, length: { minimum: 3 }
  validates :age, presence: true, numericality: {greater_than: 5}
end
```

The `validate` macro takes three parameters. The symbol of the field and the message that will display when the validation fails. The third is a `Proc` that is provided an instance of `self` and returns either true or false.

To check to see if your instance is valid, call `valid?`. Each Proc will be called and if any of them fails, an `errors` Array with the messages is returned.

If no Symbol is provided as a first parameter, the errors will be added to the `:base` field.

```crystal
person = Person.new(name: "JD")
person.valid?.should eq false
person.errors[0].to_s.should eq "Name is too short"
```

#### Dirty Checking

Changes to attributes are tracked throughout the lifetime of the model. Similar to Rails: <http://api.rubyonrails.org/classes/ActiveModel/Dirty.html>

```crystal
person = Person.new(name: "JD")
person.changed? # => true
person.changed_attributes # => {:name => "JD"}
person.name_changed? # => true
person.name_change # => {nil, "JD"}
person.name_was # => nil

person.clear_changes_information
person.changed? # => false
```

#### Callbacks

Register before/after callbacks for `create`, `update`, `delete`, `save` methods. You must define the method you wish to register callbacks for.<br>
Registered callbacks are invoked through wrapping crud logic with the `run_create_callbacks`, `run_update_callbacks`, etc. functions

```crystal
require "active-model"

class Person < ActiveModel::Model
  include ActiveModel::Callbacks

  attribute name : String
  attribute age : Int32

  before_save :capitalize

  def capitalize
    @name = @name.capitalize
  end

  def save
    run_save_callbacks do
      # save to database
      @foo.save(attributes)
    end
  end
end
```
