# require "./spec_helper"

# class BaseOrm < ActiveModel::Model
#   include ActiveModel::Callbacks
# end

# class CallbackModel < BaseOrm
#   attribute name : String
#   attribute raises : Bool = false

#   property history = [] of String

#   {% for crud in {:create, :save, :update, :destroy} %}
#     def {{ crud.id }}
#       run_{{ crud.id }}_callbacks do
#         history << {{ crud.id.stringify }}
#       end
#     end
#   {% end %}

#   {% for callback in ActiveModel::Callbacks::CALLBACK_NAMES %}
#     {{ callback.id }} :__{{ callback.id }}
#     private def __{{ callback.id }}
#       history << {{ callback.id.stringify }}
#       raise "Launching missiles!" if @raises
#     end
#   {% end %}
# end

# class Hero < BaseOrm
#   attribute name : String
#   attribute id : Int32

#   before_create :__before_create__

#   private def __before_create__
#     @id = @name.try(&.size)
#   end

#   def create
#     run_create_callbacks do
#       true
#     end
#   end
# end

# class BlockHero < BaseOrm
#   attribute name : String
#   attribute id : Int32

#   before_create do
#     @id = @name.try(&.size)
#   end
# end

# class SuperHero < Hero
#   attribute super_power : String

#   before_create do
#     raise "nope nope nope" if @super_power == "none"
#   end
# end

# describe ActiveModel::Callbacks do
#   describe "#save (new record)" do
#     it "runs before_save, after_save" do
#       callback = CallbackModel.new(name: "foo")
#       callback.save
#       order = ["before_save", "save", "after_save"]
#       callback.history.should eq order
#     end
#   end

#   describe "#save" do
#     it "runs before_save, before_update, after_update, after_save" do
#       callback = CallbackModel.new(name: "foo")
#       callback.save
#       callback.update

#       order = ["before_save", "save", "after_save", "before_update", "update", "after_update"]
#       callback.history.should eq order
#     end
#   end

#   describe "#destroy" do
#     it "runs before_destroy, after_destroy" do
#       callback = CallbackModel.new(name: "foo")
#       callback.destroy

#       order = ["before_destroy", "destroy", "after_destroy"]
#       callback.history.should eq order
#     end
#   end

#   describe "subset of callbacks" do
#     it "executes registered callbacks" do
#       hero = Hero.new(name: "footbath")
#       result = hero.create

#       result.should be_true
#       hero.id.should be_a(Int32)
#       hero.id.should eq hero.name.try(&.size)
#     end

#     it "executes inherited callbacks" do
#       hero = SuperHero.new(name: "footbath", super_power: "speed")
#       result = hero.create

#       result.should be_true
#       hero.id.should be_a(Int32)
#       hero.id.should eq hero.name.try(&.size)
#       hero.super_power.should eq "speed"

#       hero.super_power = "none"
#       expect_raises(Exception, "nope nope nope") do
#         hero.create
#       end
#     end
#   end

#   describe "an exception thrown in a hook" do
#     it "should not get swallowed" do
#       callback = CallbackModel.new(name: "foo", raises: true)
#       expect_raises(Exception, "Launching missiles!") do
#         callback.save
#       end
#     end
#   end

#   describe "manually triggered" do
#     context "on a single model" do
#       it "should successfully trigger the callback block" do
#         hero = BlockHero.new(name: "Groucho")
#         hero.@id.should be_nil
#         hero.before_create

#         hero.id.should be_a(Int32)
#         hero.id.should eq hero.name.try(&.size)
#       end

#       it "should successfully trigger the callback" do
#         hero = Hero.new(name: "Groucho")
#         hero.@id.should be_nil
#         hero.before_create

#         hero.id.should be_a(Int32)
#         hero.id.should eq hero.name.try(&.size)
#       end
#     end

#     context "on an array of models" do
#       it "should successfully trigger the callback block" do
#         heroes = [] of BlockHero
#         heroes << BlockHero.new(name: "Mr. Fantastic")
#         heroes << BlockHero.new(name: "Invisible Woman")
#         heroes << BlockHero.new(name: "Thing")
#         heroes << BlockHero.new(name: "Human Torch")

#         heroes.all? { |hero| hero.@id.nil? }.should be_true
#         heroes.each(&.before_create)
#         heroes.all? { |hero| hero.id.is_a?(Int32) }.should be_true
#         heroes.all? { |hero| hero.id == hero.name.try(&.size) }.should be_true
#       end

#       it "should successfully trigger the callback" do
#         heroes = [] of Hero

#         heroes << Hero.new(name: "Mr. Fantastic")
#         heroes << Hero.new(name: "Invisible Woman")
#         heroes << Hero.new(name: "Thing")
#         heroes << Hero.new(name: "Human Torch")

#         heroes.all? { |hero| hero.@id.nil? }.should be_true

#         heroes.each &.before_create

#         heroes.all? { |hero| hero.id.is_a?(Int32) }.should be_true
#         heroes.all? { |hero| hero.id == hero.name.try(&.size) }.should be_true
#       end
#     end
#   end
# end
