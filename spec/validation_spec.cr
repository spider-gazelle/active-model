require "./spec_helper"

class ORM < ActiveModel::Model
  include ActiveModel::Validation
end

class Model < ORM
  attribute email : String
  validates :email, confirmation: true, presence: true
  validates :email_confirmation, presence: true
end

class Person < ORM
  attribute name : String
  attribute age : Int32 = 32
  attribute rating : Int32
  attribute gender : String
  attribute adult : Bool = true
  attribute email : String

  validates :name, presence: true, length: {minimum: 3, too_short: "must be 3 characters long"}
  validates :age, numericality: {:greater_than => 5}
  validates :rating, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 100, allow_nil: true}

  validates :gender, confirmation: true
  validates :email, confirmation: {case_sensitive: false}

  validates :email, format: {
    :with    => /@/,
    :without => /.edu/,
  }

  validate("too old", ->(this : Person) {
    this.gender == "female"
  }, if: :age_test)

  def age_test
    age = self.age
    age && age > 80
  end

  validate("too childish", ->(this : Person) {
    this.gender == "female"
  }, unless: :adult)

  validate("not middle aged", ->(this : Person) {
    this.gender == "male"
  }, unless: :adult, if: ->(this : Person) {
    age = this.age
    age && age > 50
  })
end

class CustomError < ORM
  attribute temperature : Int32 = 100, custom_tag: "whawhat"

  validate ->(this : CustomError) {
    temp = this.temperature
    this.validation_error(:temperature, "is important, it must be divisible by 3") unless temp && temp % 3 == 0
  }
end

describe ActiveModel::Validation do
  describe "presence" do
    it "validates presence of name" do
      person = Person.new(name: "John Doe")
      person.valid?.should eq true
    end

    it "returns false if name is not present" do
      person = Person.new
      person.valid?.should eq false
      person.errors[0].to_s.should eq "name is required"

      person = Person.new(name: "")
      person.valid?.should eq false
      person.errors[0].to_s.should eq "name is required"
    end

    it "returns false if age is not present" do
      person = Person.new name: "bob"
      person.age = nil
      person.valid?.should eq false
      person.errors[0].to_s.should eq "age must be greater than 5"
    end
  end

  describe "numericality" do
    it "returns false if age is not greater than 5" do
      person = Person.new name: "bob", age: 5
      person.valid?.should eq false
      person.errors[0].to_s.should eq "age must be greater than 5"
    end

    it "returns false if rating is not set correctly" do
      person = Person.new name: "bob", age: 6, rating: -1
      person.valid?.should eq false
      person.errors[0].to_s.should eq "rating must be greater than or equal to 0"

      person = Person.new name: "bob", age: 6, rating: 101
      person.valid?.should eq false
      person.errors[0].to_s.should eq "rating must be less than or equal to 100"

      person = Person.new name: "bob", age: 6, rating: 50
      person.valid?.should eq true
    end
  end

  describe "confirmation" do
    it "should create and compare confirmation field" do
      person = Person.new name: "bob", gender: "female", gender_confirmation: "male"
      person.valid?.should eq false
      person.errors[0].to_s.should eq "gender doesn't match confirmation"

      # A nil version of the confirmation is ignored
      person = Person.new name: "bob", gender: "female"
      person.valid?.should eq true
    end

    it "should be case insensitive when requested" do
      person = Person.new name: "bob", email: "steve@acaprojects.com", email_confirmation: "Steve@ACAprojects.com"
      person.valid?.should eq true
    end

    it "should work with inherited objects" do
      person = Model.new email: "steve@acaprojects.com", email_confirmation: "nothing"
      person.valid?.should eq false
      person.errors[0].to_s.should eq "email doesn't match confirmation"

      person.email_confirmation = "steve@acaprojects.com"
      person.valid?.should eq true
    end
  end

  describe "if/unless check" do
    it "should support if condition" do
      person = Person.new name: "bob", gender: "female", age: 81
      person.valid?.should eq true

      person.age = 70
      person.gender = "male"
      person.valid?.should eq true

      person.age = 81
      person.valid?.should eq false
      person.errors[0].to_s.should eq "Person too old"
    end

    it "should support unless check" do
      person = Person.new name: "bob", gender: "female", adult: true
      person.valid?.should eq true

      person.gender = "male"
      person.valid?.should eq true

      person.adult = false
      person.valid?.should eq false
      person.errors[0].to_s.should eq "Person too childish"
    end

    it "should support if and unless check combined" do
      person = Person.new name: "bob", gender: "female", adult: true, age: 40
      person.valid?.should eq true

      person.adult = false
      person.valid?.should eq true

      person.age = 52
      person.valid?.should eq false
      person.errors[0].to_s.should eq "Person not middle aged"
    end
  end

  describe "format" do
    it "should support with and without options" do
      person = Person.new name: "bob", email: "bob@gmail.com"
      person.valid?.should eq true

      person.email = "bobgmail.com"
      person.valid?.should eq false
      person.errors[0].to_s.should eq "email is invalid"

      person.email = "bob@uni.edu"
      person.valid?.should eq false
    end
  end

  describe "validate length" do
    it "returns valid if name is greater than 2 characters" do
      person = Person.new(name: "John Doe")
      person.valid?.should eq true
    end

    it "returns invalid if name is less than 2 characters" do
      person = Person.new(name: "JD")
      person.valid?.should eq false
      person.errors[0].to_s.should eq "name must be 3 characters long"
    end
  end

  describe "custom errors" do
    it "allows definition of custom validation error" do
      model = CustomError.new
      model.valid?.should be_false
      model.errors[0].to_s.should eq "temperature is important, it must be divisible by 3"
      model.errors.size.should eq 1
    end
  end
end
