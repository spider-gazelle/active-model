module ActiveModel::Callbacks
  # :nodoc:
  CALLBACK_NAMES = %w(before_save after_save before_create after_create before_update after_update before_destroy after_destroy)

  macro included
    macro inherited
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

      # Wrap a block with callbacks for the appropriate crud operation
      {% for crud in {:create, :save, :update, :destroy} %}
        def run_{{crud.id}}_callbacks(&block)
          __before_{{crud.id}}
          result = yield
          __after_{{crud.id}}
          result
        end
      {% end %}
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
