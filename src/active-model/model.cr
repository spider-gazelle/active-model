require "json"
require "yaml"

require "http/params"
require "http-params-serializable/ext"
require "./http-params"

abstract class ActiveModel::Model
  include JSON::Serializable
  include YAML::Serializable

  # :nodoc:
  FIELD_MAPPINGS = {} of Nil => Nil

  module Missing
    extend self
  end

  # Stub methods to prevent compiler errors
  def apply_defaults; end

  def changed?; end

  def clear_changes_information; end

  def changed_attributes; end

  protected def validation_error; end

  macro inherited
    # Macro level constants

    # :nodoc:
    LOCAL_FIELDS = {} of Symbol => Nil
    # :nodoc:
    DEFAULTS = {} of Nil => Nil
    # :nodoc:
    HAS_KEYS = [false]
    # :nodoc:
    FIELDS = {} of Symbol => Nil
    # :nodoc:
    PERSIST = {} of Nil => Nil
    # :nodoc:
    SETTERS = {} of Nil => Nil

    # Process attributes must be called while constants are in scope

    macro finished
      __process_attributes__
      __customize_orm__
      {% unless @type.abstract? %}
      __track_changes__
      __create_initializer__
      __getters__
      __nilability_validation__
      __map_json__
      {% end %}
    end
  end

  # :nodoc:
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

    # # Methods that return attributes

    # Returns a Hash of all the attribute values
    def attributes
      {
        {% for name, index in FIELDS.keys %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if !HAS_KEYS[0] %} of Nil => Nil {% end %}
    end

    # Returns a NamedTuple of all attribute values
    def attributes_tuple
      {
        {% for name, index in FIELDS.keys %}
          {{name}}: @{{name}},
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

    # Returns a hash of all attributes that may be persisted
    def persistent_attributes
      {
        {% for name, opts in PERSIST %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if PERSIST.empty? %} of Nil => Nil {% end %}
    end

    # Deserialize from JSON if value is available in the payload
    def assign_attributes(
      {% for name, opts in FIELDS %}
        {{name.id}} : {{opts[:klass]}} | Missing = Missing,
      {% end %}
    )
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] == true %}
          self.{{name.id}} = {{name.id}} unless {{name.id}}.is_a?(Missing)
        {% end %}
      {% end %}
    end

    # Accept HTTP params
    def assign_attributes(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)

      self
    end
  end

  # :nodoc:
  macro __from_object_params__(params)
    {% for name, opts in FIELDS %}
      {% if opts[:mass_assign] %}
        value = {{ params.id }}[{{name.stringify}}]?

        if value
          self.{{name}} = {{ opts[:klass] }}.from_http_param(value)
        end
      {% end %}
    {% end %}
  end

  # For overriding in parent classes
  macro __customize_orm__
  end

  # :nodoc:
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

    def changed_json
      all = JSON.parse(self.to_json).as_h
      {% for name, index in FIELDS.keys %}
        all.delete({{name.stringify}}) unless @{{name}}_changed
      {% end %}
      all.to_json
    end

    def changed_yaml
      all = JSON.parse(self.to_json).as_h
      {% for name, index in FIELDS.keys %}
        all.delete({{name.stringify}}) unless @{{name}}_changed
      {% end %}
      all.to_yaml
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

  # :nodoc:
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
      __from_object_params__(params)
      apply_defaults
    end

    # Setters
    {% for name, opts in FIELDS %}
      # {{name}} setter
      def {{name}}=(value : {{opts[:klass]}})
        if !@{{name}}_changed && @{{name}} != value
          @[JSON::Field(ignore: true)]
          @{{name}}_changed = true

          @{{name}}_was = @{{name}}
        end
        {% if SETTERS[name] %}
          @{{name}} = ->({{ SETTERS[name].args.first }} : {{opts[:klass]}}){
            {{ SETTERS[name].body }}
          }.call value
        {% else %}
          @{{name}} = value
        {% end %}
      end
    {% end %}
  end

  # :nodoc:
  # Adds the from_json method
  macro __map_json__
    def after_initialize(trusted : Bool)
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

    def self.from_json(string_or_io : String | IO, trusted : Bool = false) : self
      super(string_or_io).tap &.after_initialize(trusted: trusted)
    end

    # Serialize from a trusted JSON source
    def self.from_trusted_json(string_or_io : String | IO) : self
      self.from_json(string_or_io, trusted: true)
    end

    def self.from_yaml(string_or_io : String | IO, trusted : Bool = false) : self
      super(string_or_io).tap &.after_initialize(trusted: trusted)
    end

    # Serialize from a trusted YAML source
    def self.from_trusted_yaml(string_or_io : String | IO) : self
      self.from_yaml(string_or_io, trusted: true)
    end

    def assign_attributes_from_json(json)
      json = json.read_string(json.read_remaining) if json.responds_to? :read_remaining && json.responds_to? :read_string
      model = self.class.from_json(json)
      data = JSON.parse(json).as_h
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          self.{{name}} = model.{{name}} if data.has_key?({{name.stringify}}) && self.{{name}} != model.{{name}}
        {% end %}
      {% end %}

      self
    end

    # Assign each field from JSON if field exists in JSON and has changed in model
    def assign_attributes_from_trusted_json(json)
      json = json.read_string(json.read_remaining) if json.responds_to? :read_remaining && json.responds_to? :read_string
      model = self.class.from_trusted_json(json)
      data = JSON.parse(json).as_h
      {% for name, opts in FIELDS %}
        self.{{name}} = model.{{name}} if data.has_key?({{name.stringify}}) && self.{{name}} != model.{{name}}
      {% end %}

      self
    end

    # Uses the YAML parser as JSON is valid YAML
    def assign_attributes_from_yaml(yaml)
      yaml = yaml.read_string(yaml.read_remaining) if yaml.responds_to? :read_remaining && yaml.responds_to? :read_string
      model = self.class.from_yaml(yaml)
      data = YAML.parse(yaml).as_h
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          self.{{name}} = model.{{name}} if data.has_key?({{name.stringify}}) && self.{{name}} != model.{{name}}
        {% end %}
      {% end %}

      self
    end

    def assign_attributes_from_trusted_yaml(yaml)
      yaml = yaml.read_string(yaml.read_remaining) if yaml.responds_to? :read_remaining && yaml.responds_to? :read_string
      model = self.class.from_trusted_yaml(yaml)
      data = YAML.parse(yaml).as_h
      {% for name, opts in FIELDS %}
        self.{{name}} = model.{{name}} if data.has_key?({{name.stringify}}) && self.{{name}} != model.{{name}}
      {% end %}

      self
    end
  end

  macro __nilability_validation__
    def validate_nilability
      {% if HAS_KEYS[0] && !PERSIST.empty? %}
        {% for name, opts in PERSIST %}
          {% if !opts[:klass].nilable? %}
            validation_error({{name.symbolize}}, "should not be nil" ) if @{{name.id}}.nil?
          {% end %}
        {% end %}
      {% end %}
    end
  end

  macro __getters__
    {% if HAS_KEYS[0] && !PERSIST.empty? %}
      {% for name, opts in PERSIST %}
        # {{name}} getter
        def {{name}}
          {% if opts[:klass].nilable? %}
            @{{name.id}}
          {% else %}
            %value = @{{name.id}}
            raise NilAssertionError.new("Nil for {{@type}}{{'#'.id}}{{name.id}} : {{opts[:klass].id}}") if %value.nil?
            %value
          {% end %}
        end
      {% end %}
    {% end %}
  end

  # Allow enum attributes. Persisted as either String | Int
  macro enum_attribute(name, column_type = Int32, mass_assignment = true, persistence = true, **tags)
    {% column_type_str = column_type.stringify %}
    {{ raise("enum_attribute: column_type must be (Int32 | String).class, given #{column_type_str}") unless column_type_str == "Int32" || column_type_str == "String" }}

    {% if column_type_str == "Int32" %}
      {% serialise = :to_i.id %}
      {% json_type = :number.id %}
    {% else %}
      {% serialise = :to_s.id %}
      {% json_type = :string.id %}
    {% end %}

    {% enum_type = name.type.resolve %}
    {% converter = (enum_type.stringify + "Converter").id %}

    class {{ converter }}
      def self.from_json(value : JSON::PullParser) : {{enum_type}}
        {{enum_type}}.new(value)
      end

      def self.to_json(value : {{enum_type}}, json : JSON::Builder)
        json.{{json_type}}(value.{{serialise}})
      end

      def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : {{enum_type}}
        {{enum_type}}.new(ctx, node)
      end

      def self.to_yaml(value : {{enum_type}}, yaml : YAML::Nodes::Builder)
        yaml.scalar(value.{{serialise}})
      end
    end

    # Set an attribute with the converter
    {% if name.value || name.value == false %}
        attribute {{ name.var }} : {{ enum_type }} = {{ name.value }}, mass_assignment: {{mass_assignment}}, persistence: {{persistence}}, converter: {{ converter }} {% if !tags.empty? %}, tags: {{tags}} {% end %}
    {% else %}
        attribute {{ name.var }} : {{ enum_type }}, mass_assignment: {{mass_assignment}}, persistence: {{persistence}}, converter: {{ converter }} {% if !tags.empty? %}, tags: {{tags}} {% end %}
    {% end %}
  end

  # Declare attributes in real model
  macro attribute(name, converter = nil, mass_assignment = true, persistence = true, **tags, &block)
    # Declaring correct type of attribute
    {% resolved_type = name.type.resolve %}
    {% if resolved_type.nilable? %}
      {% type_signature = resolved_type %}
    {% else %}
      {% type_signature = "#{resolved_type} | Nil".id %}
    {% end %}

    # Assign instance variable to correct type

    @[JSON::Field(
      presence: true,
      {% if !persistence %}
        ignore: true,
      {% end %}
      {% if !converter.nil? %}
        converter: {{converter}}
      {% end %}
    )]
    @{{name.var}} : {{type_signature.id}}

    @[JSON::Field(ignore: true)]
    getter? {{name.var}}_present : Bool = false

    # Attribute default value
    def {{name.var.id}}_default : {{ name.type }}
      # Check if name.value is not nil
      {% if name.value || name.value == false %}
        {{ name.value }}
      # Type is not nilable
      {% elsif !resolved_type.nilable? %}
        raise NilAssertionError.new("No default for {{@type}}{{'#'.id}}{{name.var.id}}" )
      # Type is nilable
      {% else %}
        nil
      {% end %}
    end

    {% if tags.empty? == true %}
      {% tags = nil %}
    {% end %}

    {% SETTERS[name.var.id] = block || nil %}

    {%
      LOCAL_FIELDS[name.var.id] = {
        klass:          resolved_type,
        converter:      converter,
        mass_assign:    mass_assignment,
        should_persist: persistence,
        tags:           tags,
        type_signature: type_signature,
      }
    %}

    {%
      FIELDS[name.var.id] = {
        klass:          resolved_type,
        converter:      converter,
        mass_assign:    mass_assignment,
        should_persist: persistence,
        tags:           tags,
        type_signature: type_signature,
      }
    %}

    {% HAS_KEYS[0] = true %}

    # Declare default values if name.value is not nil
    {% if name.value || name.value == false %}
      {% DEFAULTS[name.var.id] = name.value %}
    {% end %}
  end
end
