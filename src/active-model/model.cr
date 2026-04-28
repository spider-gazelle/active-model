require "json"
require "yaml"
require "db"

require "http/params"
require "http-params-serializable/ext"
require "./http-params"

abstract class ActiveModel::Model
  include JSON::Serializable
  include YAML::Serializable
  include DB::Serializable

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
    # :nodoc:
    GROUP_METHODS = {} of Symbol => Nil

    # Process attributes must be called while constants are in scope

    macro finished
      __process_attributes__
      __customize_orm__
      __track_local_fields__
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

  protected def sanitize_attributes; end

  def changed?; end

  def clear_changes_information; end

  def changed_attributes; end

  protected def validation_error; end

  macro define_to_json(group, except = [] of Symbol, only = [] of Symbol, methods = [] of Symbol)
    {% only = only.resolve if only.is_a?(Path) %}
    {% except = except.resolve if except.is_a?(Path) %}
    {% methods = methods.resolve if methods.is_a?(Path) %}
    {% only = [only] if only.is_a?(SymbolLiteral) %}
    {% except = [except] if except.is_a?(SymbolLiteral) %}
    {% methods = [methods] if methods.is_a?(SymbolLiteral) %}

    {% raise "expected `except` to be an Array(Symbol) | Symbol, got #{except.class_name}" unless except.is_a? ArrayLiteral && except.all? &.is_a?(SymbolLiteral) %}
    {% raise "expected `only` to be an Array(Symbol) | Symbol, got #{only.class_name}" unless only.is_a? ArrayLiteral && only.all? &.is_a?(SymbolLiteral) %}
    {% raise "expected `methods` to be an Array(Symbol) | Symbol, got #{methods.class_name}" unless methods.is_a? ArrayLiteral && methods.all? &.is_a?(SymbolLiteral) %}

    {% group_members = LOCAL_FIELDS.keys.map(&.symbolize) %}
    {% group_members = group_members.select { |m| only.includes? m } unless only.empty? %}
    {% group_members = group_members.reject { |m| except.includes? m } unless except.empty? %}
    {% for member in group_members.map(&.id) %}
      {% if LOCAL_FIELDS[member] && FIELDS[member] %}
        {% LOCAL_FIELDS[member][:serialization_group] << group unless LOCAL_FIELDS[member][:serialization_group].includes? group %}
        {% FIELDS[member][:serialization_group] << group unless FIELDS[member][:serialization_group].includes? group %}
      {% end %}
    {% end %}
    {% GROUP_METHODS[group] = methods %}
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

    # Generate serializers for each mentioned serialization group
    {%
      serialization_group = FIELDS.values.reduce([] of String) do |groups, opts|
        opts[:serialization_group] && opts[:serialization_group].each do |g|
          groups << g
        end
        groups
      end.uniq
    %}

    {% for serialization_group in serialization_group %}
      # attributes
      {%
        in_group = FIELDS.to_a.select do |(_n, o)|
          o[:serialization_group] && o[:serialization_group].includes?(serialization_group)
        end
      %}

      struct {{ serialization_group.id.stringify.camelcase.id }}Response
        include JSON::Serializable
        include JSON::Serializable::Unmapped
        include YAML::Serializable

        {% for kv in in_group %}
          {% name = kv[0] %}
          {% opts = kv[1] %}

          @[JSON::Field( {{opts.double_splat}} )]
          @[YAML::Field( {{opts.double_splat}} )]
          getter {{name}} : {{opts[:type_signature]}}
        {% end %}

        {% if GROUP_METHODS[serialization_group] %}
          {% for method in GROUP_METHODS[serialization_group] %}
            {% ancestors = [@type] + @type.ancestors %}
            {% found = false %}
            {% for klass in ancestors %}
              {% if !found %}
                {% method_def = klass.methods.find { |meth| meth.name.symbolize == method.id.symbolize } %}
                {% if method_def %}
                  {% found = true %}
                {% end %}
                {% if method_def && !method_def.return_type.nil? %}
                  getter {{method_def.name}} : {{method_def.return_type}}
                {% end %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}

        {% nop_methods = 0 %}
        def initialize(
          {% for kv in in_group %}
            {% name = kv[0] %}
            {% opts = kv[1] %}
            @{{name}} : {{opts[:type_signature]}},
          {% end %}

          {% if GROUP_METHODS[serialization_group] %}
            {% for method in GROUP_METHODS[serialization_group] %}
              {% ancestors = [@type] + @type.ancestors %}
              {% found = false %}
              {% for klass in ancestors %}
                {% if !found %}
                  {% method_def = klass.methods.find { |meth| meth.name.symbolize == method.id.symbolize } %}
                  {% if method_def %}
                    {% found = true %}
                    {% if !method_def.return_type.nil? %}
                      @{{method_def.name}} : {{method_def.return_type}},
                    {% else %}
                      {% nop_methods = nop_methods + 1 %}
                    {% end %}
                  {% end %}
                {% end %}
              {% end %}
            {% end %}
          {% end %}

          **_unknown_types
        )
          # Temporary hack as we migrate to AC5 / always define types for performance
          json_unmapped = Hash(String, JSON::Any).new({{nop_methods}}) { |key| raise KeyError.new "Missing hash key: #{key.inspect}" }
          {% if GROUP_METHODS[serialization_group] %}
            {% for method in GROUP_METHODS[serialization_group] %}
              {% method_def = @type.methods.find { |meth| meth.name.symbolize == method.id.symbolize } %}
              {% if method_def && method_def.return_type.nil? %}
                json_unmapped[{{method_def.name.stringify}}] = JSON.parse(_unknown_types[{{method_def.name.symbolize}}].to_json)
              {% end %}
            {% end %}
          {% end %}
          @json_unmapped = json_unmapped
        end
      end

      def to_{{ serialization_group.id }}_struct
        {{ serialization_group.id.stringify.camelcase.id }}Response.new(
          {% for kv in in_group %}
            {% name = kv[0] %}
            {% opts = kv[1] %}
            {{name}}: @{{name}}.as({{opts[:type_signature]}}),
          {% end %}

          {% if GROUP_METHODS[serialization_group] %}
            {% for method in GROUP_METHODS[serialization_group] %}
              {{method.id}}: {{method.id}},
            {% end %}
          {% end %}
        )
      end

      # Serialize attributes with `{{ serialization_group }}` in its `serialization_group` option
      def to_{{ serialization_group.id }}_json(json : ::JSON::Builder)
        json.object do
          # Serialize attributes
          {% for kv in in_group %}
            {% name = kv[0] %}
            {% opts = kv[1] %}
            %value = @{{name}}
            json.field({{ (opts[:tags] && opts[:tags][:json_key]) || name.stringify }}) do
              {% if opts[:converter] %}
                if !%value.nil?
                  {{ opts[:converter] }}.to_json(%value, json)
                else
                  nil.to_json(json)
                end
              {% else %}
                %value.to_json(json)
              {% end %}
            end
          {% end %}
          # Serialize method calls
          {% if GROUP_METHODS[serialization_group] %}
            {% for method in GROUP_METHODS[serialization_group] %}
              %method_result = self.{{ method.id }}
              json.field({{ method.id.stringify }}) do
                %method_result.to_json(json)
              end
            {% end %}
          {% end %}
        end
      end

      # :ditto:
      def to_{{ serialization_group.id }}_json : String
        String.build do |string|
          to_{{ serialization_group.id }}_json string
        end
      end

      # :ditto:
      def to_{{ serialization_group.id }}_json(io : IO) : Nil
        JSON.build(io) do |json|
          to_{{ serialization_group.id }}_json json
        end
      end
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

    # :nodoc:
    # Sanitize attribute values using configured policies.
    # NOTE: This is an internal method called by `after_initialize` and MUST be
    # followed by `clear_changes_information` because it routes through the
    # setter which marks attributes as assigned/changed as a side-effect.
    protected def sanitize_attributes
      super
      {% for name, opts in FIELDS %}
        {% if opts[:sanitize] %}
          %val = @{{ name }}
          unless %val.nil?
            self.{{ name }} = %val
          end
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
          unless {{name.id}}.is_a?(Missing)
            %value = {{name.id}}
            # Convert empty strings to nil for field removal
            {% if opts[:klass].nilable? %}
              if %value.responds_to?(:empty?) && %value.empty?
                self.{{name.id}} = nil
              else
                self.{{name.id}} = %value
              end
            {% else %}
              self.{{name.id}} = %value
            {% end %}
          end
        {% end %}
      {% end %}
    end

    # Assign to multiple attributes via `HTTP::Params`.
    def assign_attributes(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)

      self
    end

    # Assign to multiple attributes from a model object
    def assign_attributes(model : {{@type.name}})
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] == true %}
          if model.{{name.id}}_assigned? || model.{{name.id}}_present?
            %value = model.{{name.id}}
            # Convert empty strings to nil for field removal
            {% if opts[:klass].nilable? %}
              if %value.responds_to?(:empty?) && %value.empty?
                self.{{name.id}} = nil
              else
                self.{{name.id}} = %value
              end
            {% else %}
              self.{{name.id}} = %value
            {% end %}
          end
        {% end %}
      {% end %}
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
  macro __track_local_fields__
    {% for name, opts in LOCAL_FIELDS %}
      @[JSON::Field(ignore: true)]
      @[YAML::Field(ignore: true)]
      getter? {{name}}_changed  = false

      @[JSON::Field(ignore: true)]
      @[YAML::Field(ignore: true)]
      getter? {{name}}_assigned = false

      @[JSON::Field(ignore: true)]
      @[YAML::Field(ignore: true)]
      getter? {{name}}_removed = false

      # Include `{{ name }}` in the set of changed attributes, whether it has changed or not.
      def {{name}}_will_change! : Nil
        @{{name}}_changed = true
        @{{name}}_assigned = true
        @{{name}}_was = @{{name}}.dup
      end

      @[JSON::Field(ignore: true)]
      @[YAML::Field(ignore: true)]
      getter {{name}}_was : {{ opts[:klass] }} | Nil = nil

      # Returns a Tuple of the previous and the current
      # value of an instance variable if it has changed
      def {{name}}_change : Tuple({{opts[:klass]}}?, {{opts[:klass]}}?)?
        {@{{name}}_was, @{{name}}} if {{name}}_changed?
      end
    {% end %}
  end

  # :nodoc:
  macro __track_changes__
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
          @{{name}}_assigned = false
          @{{name}}_removed = false
          @{{name}}_was = nil
        {% end %}
      {% end %}
      nil
    end
  end

  # :nodoc:
  struct None
  end

  # :nodoc:
  macro __create_initializer__
    def initialize(
      {% for name, opts in FIELDS %}
        {{name}} : {{opts[:klass]}} | ::ActiveModel::Model::None = ::ActiveModel::Model::None.new,
      {% end %}
    )
      {% for name, opts in FIELDS %}
        self.{{name}} = {{name}} unless {{name}}.is_a? ::ActiveModel::Model::None
      {% end %}

      apply_defaults
    end

    # Initialize {{ @type }} from `HTTP::Params`.
    def initialize(params : HTTP::Params | Hash(String, String) | Tuple(String, String))
      __from_object_params__(params)
      apply_defaults
    end

    # Setters
    {% for name, opts in FIELDS %}
      # `{{name}}` setter
      def {{name}}=(value : {{opts[:klass]}})
        @{{name}}_assigned = true

        # Apply sanitization policy before change tracking.
        # NOTE: sanitization is idempotent, so values that were already sanitized
        # (e.g. from a deserialized source model) are safe to sanitize again.
        {% if opts[:sanitize] %}
          {% if opts[:klass].nilable? %}
            if %_sanitize_val = value
              value = ActiveModel::Sanitizer.{{ opts[:sanitize].id }}.process(%_sanitize_val)
            end
          {% else %}
            value = ActiveModel::Sanitizer.{{ opts[:sanitize].id }}.process(value)
          {% end %}
        {% end %}

        if !@{{name}}_changed && @{{name}} != value
          @{{name}}_changed = true

          @{{name}}_was = @{{name}}
        end

        # Track if the value is being removed (set to nil or empty string)
        if value.nil?
          @{{name}}_removed = true
        elsif value.responds_to?(:empty?) && value.empty?
          @{{name}}_removed = true
        else
          @{{name}}_removed = false
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
          {% if !opts[:mass_assign] && !opts[:show] %}
            @{{name}} = nil
          {% end %}
        {% end %}
      end

      apply_defaults
      sanitize_attributes
      clear_changes_information
    end

    def self.from_json(string_or_io : String | IO, trusted : Bool = false) : self
      super(string_or_io).tap &.after_initialize(trusted: trusted)
    end

    # Deserializes the given JSON in *string_or_io* into
    # an instance of `self`, assuming the JSON consists
    # of an JSON object with key *root*, and whose value is
    # the value to deserialize. Will not deserialise from
    # fields with mass_assign: false
    #
    # ```
    # class User < ActiveModel::Model
    #   attribute name : String
    #   attribute google_id : UUID, mass_assign: false
    # end
    #
    # User.from_json(%({"main": {"name": "Jason", "google_id": "f6f70bfb-c882-446d-8758-7ce47db39620"}}), root: "main") # => #<User:0x103131b20 @name="Jason">
    # ```
    def self.from_json(string_or_io : String | IO, root : String, trusted : Bool = false) : self
      super(string_or_io, root).tap &.after_initialize(trusted: trusted)
    end

    # Serialize from a trusted JSON source
    def self.from_trusted_json(string_or_io : String | IO) : self
      self.from_json(string_or_io, trusted: true)
    end

    def self.from_trusted_json(string_or_io : String | IO, root : String) : self
      self.from_json(string_or_io, root, true)
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
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          if model.{{name.id}}_present?
            %value = model.{{name}}
            # Convert empty strings to nil for field removal
            {% if opts[:klass].nilable? %}
              if %value.responds_to?(:empty?) && %value.empty?
                self.{{name}} = nil
              else
                self.{{name}} = %value
              end
            {% else %}
              self.{{name}} = %value
            {% end %}
          end
        {% end %}
      {% end %}

      self
    end

    def assign_attributes_from_json(json, root : String)
      json = json.read_string(json.read_remaining) if json.responds_to? :read_remaining && json.responds_to? :read_string
      model = self.class.from_json(json, root: root)
      {% for name, opts in FIELDS %}
        {% if opts[:mass_assign] %}
          if model.{{name.id}}_present?
            %value = model.{{name}}
            # Convert empty strings to nil for field removal
            {% if opts[:klass].nilable? %}
              if %value.responds_to?(:empty?) && %value.empty?
                self.{{name}} = nil
              else
                self.{{name}} = %value
              end
            {% else %}
              self.{{name}} = %value
            {% end %}
          end
        {% end %}
      {% end %}

      self
    end

    # Assign each field from JSON if field exists in JSON and has changed in model
    def assign_attributes_from_trusted_json(json)
      json = json.read_string(json.read_remaining) if json.responds_to? :read_remaining && json.responds_to? :read_string
      model = self.class.from_trusted_json(json)
      {% for name, opts in FIELDS %}
        if model.{{name.id}}_present?
          %value = model.{{name}}
          # Treat empty strings as nil to support field removal (only for nilable fields)
          {% if opts[:klass].nilable? %}
            if %value.responds_to?(:empty?) && %value.empty?
              self.{{name}} = nil
            else
              self.{{name}} = %value
            end
          {% else %}
            self.{{name}} = %value
          {% end %}
        end
      {% end %}

      self
    end

    def assign_attributes_from_trusted_json(json, root : String)
      json = json.read_string(json.read_remaining) if json.responds_to? :read_remaining && json.responds_to? :read_string
      model = self.class.from_trusted_json(json, root)
      {% for name, opts in FIELDS %}
        if model.{{name.id}}_present?
          %value = model.{{name}}
          # Treat empty strings as nil to support field removal (only for nilable fields)
          {% if opts[:klass].nilable? %}
            if %value.responds_to?(:empty?) && %value.empty?
              self.{{name}} = nil
            else
              self.{{name}} = %value
            end
          {% else %}
            self.{{name}} = %value
          {% end %}
        end
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
          if model.{{name.id}}_present?
            %value = model.{{name}}
            # Treat empty strings as nil to support field removal (only for nilable fields)
            {% if opts[:klass].nilable? %}
              if %value.responds_to?(:empty?) && %value.empty?
                self.{{name}} = nil
              else
                self.{{name}} = %value
              end
            {% else %}
              self.{{name}} = %value
            {% end %}
          end
        {% end %}
      {% end %}

      self
    end

    def assign_attributes_from_trusted_yaml(yaml)
      yaml = yaml.read_string(yaml.read_remaining) if yaml.responds_to? :read_remaining && yaml.responds_to? :read_string
      model = self.class.from_trusted_yaml(yaml)
      data = YAML.parse(yaml).as_h
      {% for name, opts in FIELDS %}
        if model.{{name.id}}_present?
          %value = model.{{name}}
          # Treat empty strings as nil to support field removal (only for nilable fields)
          {% if opts[:klass].nilable? %}
            if %value.responds_to?(:empty?) && %value.empty?
              self.{{name}} = nil
            else
              self.{{name}} = %value
            end
          {% else %}
            self.{{name}} = %value
          {% end %}
        end
      {% end %}

      self
    end
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

  # Declare an `ActiveModel::Model` attribute
  #
  # # General Arguments
  #
  # - `persistence`: Will not emit the key when serializing if `false`.
  # - `converter`: A module defining alternative serialisation behaviour for the attribute's value.
  #
  # # Serialisation Target Arguments
  #
  # Additionally, `attribute` accepts the following optional arguments for different serialisation targets.
  #
  # ## JSON
  # - `json_key`: Override the emitted JSON key.
  # - `json_emit_null`: Emit `null` if value is `nil`, key is omitted if `json_emit_null` is `false`.
  # - `json_root`: Assume value is inside a JSON object under the provided key.
  # ## YAML
  # - `yaml_key`: Override the emitted YAML key.
  # - `yaml_emit_null`: Emit `null` if value is `nil`, key is omitted if `yaml_emit_null` is `false`.
  # - `yaml_root`: Assume value is inside a YAMLk object under the provided key.
  #
  macro attribute(
    name,
    mass_assignment = true,
    persistence = true,
    show = false,
    serialization_group = [] of Symbol,
    sanitize = nil,
    **tags,
    &block
  )
    # Declaring correct type of attribute
    {% resolved_type = name.type.resolve %}
    {% type_signature = resolved_type %}

    {% serialization_group = [serialization_group] if serialization_group.is_a?(SymbolLiteral) %}
    {% unless serialization_group.is_a? ArrayLiteral && serialization_group.all? &.is_a?(SymbolLiteral) %}
      {% raise "`serialization_group` expected to be an Array(Symbol) | Symbol, got #{serialization_group.class_name}" %}
    {% end %}

    # Validate sanitize option
    {% if sanitize %}
      {% valid_sanitize = [:basic, :common, :inline, :text] %}
      {% unless valid_sanitize.includes?(sanitize) %}
        {% raise "`sanitize` expected to be one of :basic, :common, :inline, :text — got :#{sanitize.id}" %}
      {% end %}
      {% non_nil = resolved_type.nilable? ? resolved_type.union_types.reject(&.nilable?).first : resolved_type %}
      {% unless non_nil == String %}
        {% raise "`sanitize` option is only valid for String fields, got `#{resolved_type}` for `#{name.var}`" %}
      {% end %}
    {% end %}

    # Assign instance variable to correct type
    @[JSON::Field(
      presence: true,
      ignore: {{ !show && !persistence }},
      key: {{tags[:json_key]}},
      emit_null: {{tags[:json_emit_null]}},
      root: {{tags[:json_root]}},
      {{tags.double_splat}}
    )]
    @[YAML::Field(
      presence: true,
      ignore: {{ !show && !persistence }},
      key: {{tags[:yaml_key]}},
      emit_null: {{tags[:yaml_emit_null]}},
      {{tags.double_splat}}
    )]
    @[DB::Field(
      ignore: {{ !persistence }},
      {{tags.double_splat}}
    )]
    {% if resolved_type.nilable? %}
      property {{name.var}} : {{type_signature.id}}
    {% else %}
      property! {{name.var}} : {{type_signature.id}}
    {% end %}

    @[JSON::Field(ignore: true)]
    @[YAML::Field(ignore: true)]
    @[DB::Field(ignore: true)]
    getter? {{name.var}}_present : Bool = false

    # `{{ name.var.id }}`'s default value
    def {{name.var.id}}_default : {{ name.type }}
      # Check if name.value is not nil
      {% if name.value || name.value == false %}
        {{ name.value }}
      # Type is nilable
      {% else %}
        nil
      {% end %}
    end


    {% SETTERS[name.var.id] = block || nil %}

    {%
      LOCAL_FIELDS[name.var.id] = {
        klass:               resolved_type,
        converter:           tags[:converter],
        mass_assign:         mass_assignment,
        show:                show,
        should_persist:      persistence,
        serialization_group: serialization_group,
        tags:                tags.empty? == true ? nil : tags,
        type_signature:      type_signature,
        sanitize:            sanitize,
      }
    %}

    {%
      FIELDS[name.var.id] = {
        klass:               resolved_type,
        converter:           tags[:converter],
        mass_assign:         mass_assignment,
        show:                show,
        should_persist:      persistence,
        serialization_group: serialization_group,
        tags:                tags.empty? == true ? nil : tags,
        type_signature:      type_signature,
        sanitize:            sanitize,
      }
    %}

    {% HAS_KEYS[0] = true %}

    # Declare default values if name.value is not nil
    {% if name.value || name.value == false %}
      {% DEFAULTS[name.var.id] = name.value %}
    {% end %}
  end
end
