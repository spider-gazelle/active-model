class ActiveModel::Error
  property model, field, message

  def initialize(@model : ActiveModel::Model, @field : Symbol, @message : String)
  end

  def to_s
    if @field == :__base__
      "#{@model.class} #{message}"
    else
      "#{@field} #{message}"
    end
  end
end
