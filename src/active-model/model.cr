require "http/params"
require "json"
require "json_mapping"
require "yaml"
require "yaml_mapping"
require "http-params-serializable/ext"

require "./http-params"

abstract class ActiveModel::Model
  # :nodoc:
  FIELD_MAPPINGS = {} of Nil => Nil

  module Missing
    extend self
  end

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
      __map_json__
      __create_initializer__
      __getters__
      __nilability_validation__
      {% end %}
    end
  end

  # Stub methods to prevent compiler errors
  def apply_defaults; end

  def changed?; end

  def clear_changes_information; end

  def changed_attributes; end

  protected def validation_error; end

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

    # Returns a `Hash` of all attribute values
    def attributes
      {
        {% for name, index in FIELDS.keys %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if !HAS_KEYS[0] %} of Nil => Nil {% end %}
    end

    # Returns a `NamedTuple` of all attribute values.
    def attributes_tuple
      {
        {% for name, index in FIELDS.keys %}
          {{name}}: @{{name}},
        {% end %}
      } {% if !HAS_KEYS[0] %} of Nil => Nil {% end %}
    end

    # Returns all attribute keys.
    def self.attributes : Array(Symbol)
      [
        {% for name, index in FIELDS.keys %}
          :{{name.id}},
        {% end %}
      ] {% if !HAS_KEYS[0] %} of Symbol {% end %}
    end

    # Returns a `Hash` of all attributes that can be persisted.
    def persistent_attributes
      {
        {% for name, opts in PERSIST %}
          :{{name}} => @{{name}},
        {% end %}
      } {% if PERSIST.empty? %} of Nil => Nil {% end %}
    end

    # Assign to multiple attributes.
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

    # Assign to mulitple attributes via `HTTP::Params`.
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

    # Returns a `Hash` with all changed attributes.
    def changed_attributes
      all = attributes
      {% for name, index in FIELDS.keys %}
        all.delete(:{{name}}) unless @{{name}}_changed
      {% end %}
      all
    end

    # Serialize the set of changed attributes to JSON.
    def changed_json : String
      String.build do |string|
        changed_json string
      end
    end

    # :ditto:
    def changed_json(io : IO) : Nil
      all = JSON.parse(self.to_json).as_h
      {% for name, index in FIELDS.keys %}
        all.delete({{name.stringify}}) unless @{{name}}_changed
      {% end %}
      all.to_json(io)
    end

    # Serialize the set of changed attributes to YAML.
    def changed_yaml : String
      String.build do |string|
        changed_yaml string
      end
    end

    # :ditto:
    def changed_yaml(io : IO) : Nil
      all = JSON.parse(self.to_json).as_h
      {% for name, index in FIELDS.keys %}
        all.delete({{name.stringify}}) unless @{{name}}_changed
      {% end %}
      all.to_yaml(io)
    end

    # Check if any attributes have changed.
    def changed?
      modified = false
      {% for name, index in FIELDS.keys %}
        modified = true if @{{name}}_changed
      {% end %}
      modified
    end

    {% for name, index in FIELDS.keys %}
      # Check if `{{ name }}` is in the set of changed attributes.
      def {{name}}_changed?
        !!@{{name}}_changed
      end

      # Include `{{ name }}` in the set of changed attributes, whether it has changed or not.
      def {{name}}_will_change!
        @{{name}}_changed = true
        @{{name}}_was = @{{name}}.dup
      end

      # Returns the previous value of `{{ name }}`.
      def {{name}}_was
        @{{name}}_was
      end

      # Returns `{ {{name}}_was, {{name}} }` if `{{name}}` has changed.
      def {{name}}_change
        if @{{name}}_changed
          {@{{name}}_was, @{{name}}}
        else
          nil
        end
      end
    {% end %}

    # Reset each attribute to their previous values and clears all changes.
    def restore_attributes
      {% for name, index in FIELDS.keys %}
        @{{name}} = @{{name}}_was if @{{name}}_changed
      {% end %}
      clear_changes_information
    end

    # Reset changes for all attributes.
    def clear_changes_information
      {% if HAS_KEYS[0] %}
        {% for name, index in FIELDS.keys %}
          @{{name}}_changed = false
          @{{name}}_was = nil
        {% end %}
      {% end %}
      nil
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

    # Initialize {{ @type }} from `HTTP::Params`.
    def initialize(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)
      apply_defaults
    end

    # Override the map json
    {% for name, opts in FIELDS %}
      # `{{name}}` setter
      def {{name}}=(value : {{opts[:klass]}})
        if !@{{name}}_changed && @{{name}} != value
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
    {% if HAS_KEYS[0] && !PERSIST.empty? %}
      JSON.mapping(
        {% for name, opts in PERSIST %}
          {% if opts[:converter] %}
            {{name}}: { type: {{opts[:type_signature]}}, setter: false, converter: {{opts[:converter]}} },
          {% else %}
            {{name}}: { type: {{opts[:type_signature]}}, setter: false },
          {% end %}
        {% end %}
      )

      # :nodoc:
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

      # Serialize from a trusted JSON source
      def self.from_trusted_json(string_or_io : String | IO) : self
        {{@type.name.id}}.new(::JSON::PullParser.new(string_or_io), true)
      end

      YAML.mapping(
        {% for name, opts in PERSIST %}
          {% if opts[:converter] %}
            {{name}}: { type: {{opts[:type_signature]}}, setter: false, converter: {{opts[:converter]}} },
          {% else %}
            {{name}}: { type: {{opts[:type_signature]}}, setter: false },
          {% end %}
        {% end %}
      )

      # :nodoc:
      def initialize(%yaml : YAML::ParseContext, %node : ::YAML::Nodes::Node, _dummy : Nil, trusted = false)
        previous_def(%yaml, %node, nil)
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

      # Serialize from a trusted YAML source
      def self.from_trusted_yaml(string_or_io : String | IO) : self
        ctx = YAML::ParseContext.new
        node = begin
          document = YAML::Nodes.parse(string_or_io)

          # If the document is empty we simulate an empty scalar with
          # plain style, that parses to Nil
          document.nodes.first? || begin
            scalar = YAML::Nodes::Scalar.new("")
            scalar.style = YAML::ScalarStyle::PLAIN
            scalar
          end
        end
        {{@type.name.id}}.new(ctx, node, nil, true)
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

    {% end %}
  end

  macro __nilability_validation__
    # Validate that all non-nillable fields have values.
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
        # `{{name}}` getter
        def {{name}} : {{opts[:klass]}}
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

  macro attribute(name, converter = nil, mass_assignment = true, persistence = true, **tags, &block)
    {% resolved_type = name.type.resolve %}
    {% if resolved_type.nilable? %}
      {% type_signature = resolved_type %}
    {% else %}
      {% type_signature = "#{resolved_type} | Nil".id %}
    {% end %}

    @{{name.var}} : {{type_signature.id}}

    # `{{ name.var.id }}`'s default value
    def {{name.var.id}}_default : {{ name.type }}
      {% if name.value || name.value == false %}
        {{ name.value }}
      {% elsif !resolved_type.nilable? %}
        raise NilAssertionError.new("No default for {{@type}}{{'#'.id}}{{name.var.id}}" )
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
    {% if name.value || name.value == false %}
      {% DEFAULTS[name.var.id] = name.value %}
    {% end %}
  end
end
