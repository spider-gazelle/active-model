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
    ENUM_FIELDS = {} of Nil => Nil
    PERSIST = {} of Nil => Nil

    # Process attributes must be called while constants are in scope
    macro finished
      __process_attributes__
      __customize_orm__
      {% unless @type.abstract? %}
      __track_changes__
      __map_json__
      __create_initializer__
      {% end %}
    end
  end

  # Stub methods to prevent compiler errors
  def apply_defaults; end

  def self.from_trusted_json(json : IO); end

  def self.from_trusted_json(json : String); end

  def changed?; end

  def clear_changes_information; end

  def changed_attributes; end

  macro __process_attributes__
    {% klasses = @type.ancestors %}
    {% FIELD_MAPPINGS[@type] = {} of Nil => Nil %}

    # Create a mapping of all field names and types
    {% for name, index in klasses %}
      {% fields = FIELD_MAPPINGS[name] %}
      {% if fields && !fields.empty? %}
        {% for name, opts in fields %}
          {% FIELDS[name] = opts %}
          {% FIELD_MAPPINGS[@type][name] = opts %}
          {% HAS_KEYS[0] = true %}
        {% end %}
      {% end %}
    {% end %}

    # Apply local fields on top of ancestors
    {% for name, opts in LOCAL_FIELDS %}
      {% FIELD_MAPPINGS[@type][name] = opts %}
    {% end %}

    # Persisted fields
    {% for name, opts in FIELDS %}
      {% if opts[:should_persist] %}
        {% PERSIST[name] = opts %}
      {% end %}
    {% end %}

    # Accessors for attributes without JSON mapping
    {% for name, opts in FIELDS %}
      {% unless opts[:should_persist] %}
        property {{ name }}
      {% end %}
    {% end %}

    # Generate code to apply default values
    def apply_defaults
      super
      {% for name, data in DEFAULTS %}
        {% if data.is_a?(ProcLiteral) %}
          self.{{name}} = ( {{data}} ).call if @{{name}}.nil?
        {% else %}
          self.{{name}} = {{data}} if @{{name}}.nil?
        {% end %}
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
        {% for name, index in ENUM_FIELDS.keys %}
          :{{name.id}},
        {% end %}
      ] {% if !HAS_KEYS[0] %} of Nil {% end %}
    end

    # Returns a hash of all attributes that may be persisted
    def persistent_attributes
      {
        {% for name, opts in PERSIST %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if PERSIST.empty? %} of Nil => Nil {% end %}
    end

    {% for name, index in ENUM_FIELDS.keys %}
        {% enum_type = ENUM_FIELDS[name][:enum_type].id %}
        {% column_type = ENUM_FIELDS[name][:column_type].id %}
        {% column_name = ENUM_FIELDS[name][:column_name].id %}

        def {{ name }}_changed
          @{{ column_name }}_changed
        end


        {% if column_type.stringify == "String" %}
          def {{name}} : {{enum_type}}
            @{{name}} ||= {{enum_type}}.parse(@{{column_name}}.to_s)
          end

          def {{ name }}_was
            @{{ name }}_was ||= {{enum_type}}.parse?(@{{column_name}}_was.to_s)
          end

          def {{name}}=(val : {{enum_type}})
            @{{name}} = val
            @{{column_name}} = val.to_s
          end

        {% elsif column_type.stringify == "Int32" %}
          def {{name}} : {{enum_type}}
            @{{name}} ||= {{enum_type}}.new(@{{column_name}}.not_nil!.to_i32)
          end

          def {{ name }}_was
            @{{ name }}_was ||= {{enum_type}}.parse?(@{{column_name}}_was.try(&.to_i32))
          end

          def {{name}}=(val : {{enum_type}})
            @{{name}} = val
            @{{column_name}} = val.value
          end
        {% end %}
    {% end %}

    def assign_attributes(
      {% for name, opts in FIELDS %}
        {{name}} : {{opts[:klass]}} | Nil = nil,
      {% end %}
    )
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          self.{{name}} = {{name}} unless {{ name }}.nil?
        {% end %}
      {% end %}
    end

    # Accept HTTP params
    def assign_attributes(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)
    end
  end

  macro __from_object_params__(params)
    {% for name, opts in FIELDS %}
      {% if opts[:mass_assign] %}
        value = {{ params.id }}[{{name.stringify}}]?
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
      {% for name, opts in ENUM_FIELDS %}
        {{name}} : {{opts[:enum_type]}} | Nil = nil,
      {% end %}
    )
      {% for name, opts in FIELDS %}
        self.{{name}} = {{name}} unless {{name}}.nil?
      {% end %}
      {% for name, opts in ENUM_FIELDS %}
        self.{{name}} = {{name}} unless {{name}}.nil?
      {% end %}

      apply_defaults
    end

    # Accept HTTP params
    def initialize(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)
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
    {% if HAS_KEYS[0] && !PERSIST.empty? %}
      JSON.mapping(
        {% for name, opts in PERSIST %}
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
        clear_changes_information
      end

      def self.from_trusted_json(json)
        {{@type.name.id}}.new(::JSON::PullParser.new(json), true)
      end
    {% end %}
  end

  # Allow enum attributes. Persisted as either String | Int32
  macro enum_attribute(name, column_type = Int32, mass_assignment = true, persistence = true, **tags)
    {% enum_type = name.type %}
    {% normalized_enum_name = "_" + enum_type.stringify.gsub(/::/, "_").underscore.downcase %}

    # Define a column name for the serialized enum value
    {% if column_type.stringify == "String" %}
    {% column_name = (normalized_enum_name + "_str").id %}
    {% elsif column_type.stringify == "Int32" %}
    {% column_name = (normalized_enum_name + "_int").id %}
    {% end %}

    # Default enum value serialization
    {% if name.value %}
      {% if column_type.stringify == "String" %}
        attribute {{ column_name }} : String = {{ name.value }}.to_s, mass_assignment: {{mass_assignment}}, persistence: {{persistence}}{% if !tags.empty? %}, tags: {{tags}} {% end %}
      {% elsif column_type.stringify == "Int32" %}
        attribute {{ column_name }} : Int32 = {{ name.value }}.to_i, mass_assignment: {{mass_assignment}}, persistence: {{persistence}}{% if !tags.empty? %}, tags: {{tags}} {% end %}
      {% end %}
    {% else %}
        # No default
        attribute {{ column_name }} : {{ column_type.id }}, mass_assignment: {{mass_assignment}}, persistence: {{persistence}}{% if !tags.empty? %}, tags: {{tags}} {% end %}
    {% end %}

    {%
      ENUM_FIELDS[name.var.id] = {
        enum_type:   enum_type.id,
        column_type: column_type.id,
        column_name: column_name.id,
      }
    %}
  end

  macro attribute(name, converter = nil, mass_assignment = true, persistence = true, **tags)
    @{{name.var}} : {{name.type}} | Nil
    # Attribute default value
    def {{name.var}}_default : {{name.type}} | Nil
      {% if name.value %}
        {{ name.value }}
      {% else %}
        nil
      {% end %}
    end

    {% if tags.empty? == true %}
      {% tags = nil %}
    {% end %}
    {%
      LOCAL_FIELDS[name.var.id] = {
        klass:          name.type,
        converter:      converter,
        mass_assign:    mass_assignment,
        should_persist: persistence,
        tags:           tags,
      }
    %}
    {%
      FIELDS[name.var.id] = {
        klass:          name.type,
        converter:      converter,
        mass_assign:    mass_assignment,
        should_persist: persistence,
        tags:           tags,
      }
    %}
    {% HAS_KEYS[0] = true %}
    {% if name.value %}
      {% DEFAULTS[name.var.id] = name.value %}
    {% end %}
  end
end
