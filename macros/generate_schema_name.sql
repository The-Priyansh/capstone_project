{% macro generate_schema_name(custom_schema_name, node) %}

    {% if target.schema == 'DBT_PROD' %}

        {{ custom_schema_name | trim if custom_schema_name else target.schema }}

    {% else %}

        {% if custom_schema_name %}
            {{ target.schema }}_{{ custom_schema_name | trim }}
        {% else %}
            {{ target.schema }}
        {% endif %}

    {% endif %}

{% endmacro %}