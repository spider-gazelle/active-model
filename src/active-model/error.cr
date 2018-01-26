class ActiveModel::Error
  property model, field, message

  def initialize(@model : ActiveModel::Model, @field : Symbol, @message : String)
  end

  def to_s
    if @field == :__base__
      "#{@model.class.to_s} #{message}"
    else
      "#{@field.to_s.gsub('_', ' ').capitalize} #{message}"
    end
  end
end
