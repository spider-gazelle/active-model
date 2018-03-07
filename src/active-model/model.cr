require "json"
require "http/params"

abstract class ActiveModel::Model
  FIELD_MAPPINGS = {} of Nil => Nil

  macro inherited
    # Macro level constants
    LOCAL_FIELDS = {} of Nil => Nil
    DEFAULTS = {} of Nil => Nil
    HAS_KEYS = [false]
    FIELDS = {} of Nil => Nil


    # Process attributes must be called while constants are in scope
    macro finished
      __process_attributes__
      __customize_orm__
      __track_changes__
      __map_json__
      __create_initializer__
    end
  end

  # Prevent compiler errors
  def apply_defaults; end

  macro __process_attributes__
    {% FIELD_MAPPINGS[@type.name.id] = LOCAL_FIELDS %}
    {% klasses = @type.ancestors %}

    # Create a mapping of all field names and types
    {% for name, index in klasses %}
      {% fields = FIELD_MAPPINGS[name.id] %}

      {% if fields && !fields.empty? %}
        {% for name, opts in fields %}
          {% FIELDS[name] = opts %}
          {% HAS_KEYS[0] = true %}
        {% end %}
      {% end %}
    {% end %}

    # Generate code to apply default values
    def apply_defaults
      super
      {% for name, data in DEFAULTS %}
        self.{{name}} = {{data}} if @{{name}}.nil?
      {% end %}
    end

    # Returns a hash of all the attribute values
    def attributes
      {
        {% for name, index in FIELDS.keys %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if !HAS_KEYS[0] %} of Nil => Nil {% end %}
    end

    # You may want a list of available attributes
    def self.attributes
      [
        {% for name, index in FIELDS.keys %}
          :{{name.id}},
        {% end %}
      ] {% if !HAS_KEYS[0] %} of Nil {% end %}
    end
  end

  # For overriding in parent classes
  macro __customize_orm__
  end

  macro __track_changes__
    # Define instance variable types
    {% if HAS_KEYS[0] %}
      {% for name, opts in FIELDS %}
        @{{name}}_was : {{opts[:klass]}} | Nil
      {% end %}
    {% end %}

    def changed_attributes
      all = attributes
      {% for name, index in FIELDS.keys %}
        all.delete(:{{name}}) unless @{{name}}_changed
      {% end %}
      all
    end

    def clear_changes_information
      {% if HAS_KEYS[0] %}
        {% for name, index in FIELDS.keys %}
          @{{name}}_changed = false
          @{{name}}_was = nil
        {% end %}
      {% end %}
      nil
    end

    def changed?
      modified = false
      {% for name, index in FIELDS.keys %}
        modified = true if @{{name}}_changed
      {% end %}
      modified
    end

    {% for name, index in FIELDS.keys %}
      def {{name}}_changed?
        !!@{{name}}_changed
      end

      def {{name}}_will_change!
        @{{name}}_changed = true
        @{{name}}_was = @{{name}}.dup
      end

      def {{name}}_was
        @{{name}}_was
      end

      def {{name}}_change
        if @{{name}}_changed
          {@{{name}}_was, @{{name}}}
        else
          nil
        end
      end
    {% end %}

    def restore_attributes
      {% for name, index in FIELDS.keys %}
        @{{name}} = @{{name}}_was if @{{name}}_changed
      {% end %}
      clear_changes_information
    end
  end

  macro __create_initializer__
    def initialize(
      {% for name, opts in FIELDS %}
        {{name}} : {{opts[:klass]}} | Nil = nil,
      {% end %}
    )
      {% for name, opts in FIELDS %}
        self.{{name}} = {{name}} unless {{name}}.nil?
      {% end %}
      apply_defaults
    end

    # Accept HTTP params
    def initialize(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          value = params[{{name.stringify}}]?
          if value
            {% coerce = opts[:klass].stringify %}
            {% if coerce == "String" %}
              self.{{name}} = value
            {% elsif coerce == "Int8" %}
              self.{{name}} = value.to_i8
            {% elsif coerce == "Int16" %}
              self.{{name}} = value.to_i16
            {% elsif coerce == "Int32" %}
              self.{{name}} = value.to_i32
            {% elsif coerce == "Int64" %}
              self.{{name}} = value.to_i64
            {% elsif coerce == "UInt8" %}
              self.{{name}} = value.to_u8
            {% elsif coerce == "UInt16" %}
              self.{{name}} = value.to_u16
            {% elsif coerce == "UInt32" %}
              self.{{name}} = value.to_u32
            {% elsif coerce == "UInt64" %}
              self.{{name}} = value.to_u64
            {% elsif coerce == "BigDecimal" %}
              self.{{name}} = value.to_big_d
            {% elsif coerce == "BigInt" %}
              self.{{name}} = value.to_big_i
            {% elsif coerce == "Float32" %}
              self.{{name}} = value.to_f32
            {% elsif coerce == "Float64" %}
              self.{{name}} = value.to_f64
            {% elsif coerce == "Bool" %}
              self.{{name}} = value[0].downcase == 't'
            {% end %}
          end
        {% end %}
      {% end %}

      apply_defaults
    end

    # Override the map json
    {% for name, opts in FIELDS %}
      def {{name}}=(value : {{opts[:klass]}} | Nil)
        if !@{{name}}_changed && @{{name}} != value
          @{{name}}_changed = true
          @{{name}}_was = @{{name}}
        end
        @{{name}} = value
      end
    {% end %}
  end

  # Adds the from_json method
  macro __map_json__
    {% if HAS_KEYS[0] %}
      JSON.mapping(
        {% for name, opts in FIELDS %}
          {% if opts[:converter] %}
            {{name}}: { type: {{opts[:klass]}} | Nil, converter: {{opts[:converter]}} },
          {% else %}
            {{name}}: {{opts[:klass]}} | Nil,
          {% end %}
        {% end %}
      )

      def initialize(%pull : ::JSON::PullParser, trusted = false)
        previous_def(%pull)
        if !trusted
          {% for name, opts in FIELDS %}
            {% if !opts[:mass_assign] %}
              @{{name}} = nil
            {% end %}
          {% end %}
        end
        apply_defaults
      end

      def self.from_trusted_json(json)
        {{@type.name.id}}.new(::JSON::PullParser.new(json), true)
      end
    {% end %}
  end

  macro attribute(name, converter = nil, mass_assignment = true)
    # Attribute default value
    def {{name.var}}_default : {{name.type}} | Nil
      {% if name.value %}
        {{ name.value }}
      {% else %}
        nil
      {% end %}
    end

    # Save field details for finished macro
    {%
      LOCAL_FIELDS[name.var] = {
        klass:       name.type,
        converter:   converter,
        mass_assign: mass_assignment,
      }
    %}
    {%
      FIELDS[name.var] = {
        klass:       name.type,
        converter:   converter,
        mass_assign: mass_assignment,
      }
    %}
    {% HAS_KEYS[0] = true %}
    {% if name.value %}
      {% DEFAULTS[name.var] = name.value %}
    {% end %}
  end
end
