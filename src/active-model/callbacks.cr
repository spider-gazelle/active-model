module ActiveModel::Callbacks
  # :nodoc:
  CALLBACK_NAMES = %w(before_save after_save before_create after_create before_update after_update before_destroy after_destroy)

  # Declares a type's callback registry and the methods that run it.
  #
  # Emitted on the including type *and* on every subclass: `__before_save` and
  # friends expand a type's own callbacks together with its ancestors', so the
  # expansion has to happen once per type.
  #
  # :nodoc:
  macro define_callback_methods
    CALLBACKS = {
      {% for name in CALLBACK_NAMES %}
        {{name.id}}: [] of Nil,
      {% end %}
    }
    {% for name in CALLBACK_NAMES %}
      def {{name.id}}
        __{{name.id}}
      end
    {% end %}
  end

  macro included
    ActiveModel::Callbacks.define_callback_methods

    # Wrap a block with callbacks for the appropriate crud operation.
    #
    # Defined once here rather than once per subclass, and reached through the
    # `before_*`/`after_*` methods rather than by expanding `__before_*` inline.
    #
    # These methods yield, and Crystal cannot dispatch a yielding method through
    # a pointer -- it inlines the body at each call site. Defining them per
    # subclass therefore meant that a `run_*_callbacks` call on an abstract
    # receiver emitted one inlined copy per concrete subclass, each containing a
    # type-id dispatch chain for every `self` call in the block. Nesting two of
    # them (`run_update_callbacks { run_save_callbacks { ... } }`) made that
    # quadratic in the number of models.
    #
    # With a single definition there is one inlined copy, and `before_*` /
    # `after_*` are ordinary non-yielding overrides that share one dispatch
    # wrapper.
    {% for crud in {:create, :save, :update, :destroy} %}
      def run_{{crud.id}}_callbacks(&block)
        self.before_{{crud.id}}
        result = yield
        self.after_{{crud.id}}
        result
      end
    {% end %}

    macro inherited
      ActiveModel::Callbacks.define_callback_methods
    end
  end

  {% for name in CALLBACK_NAMES %}
    macro {{name.id}}(*callbacks, &block)
      \{% for callback in callbacks %}
        \{% CALLBACKS[{{name}}] << callback %}
      \{% end %}
      \{% if block.is_a? Block %}
        \{% CALLBACKS[{{name}}] << block %}
      \{% end %}
    end

    # :nodoc:
    macro __{{name.id}}
      \{% for callbacks in ([@type] + @type.ancestors.select { |c| c.has_constant?("CALLBACKS") }).map { |c| c.constant("CALLBACKS") } %}
        \{% for callback in callbacks[{{name}}] %}
          \{% if callback.is_a? Block %}
            begin
              \{{callback.body}}
            end
          \{% else %}
            \{{callback.id}}
          \{% end %}
        \{% end %}
      \{% end %}
    end
  {% end %}
end
