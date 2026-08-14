{% macro create_external_tables() %}

    {% set external_schema = var('external_schema') %}
    {% set external_stage = var('external_stage') %}
    {% set external_file_format = var('external_file_format') %}
    {% set external_tables = var('external_tables') %}

    {% if not execute %}
        {{ return('') }}
    {% endif %}

    {% for table in external_tables %}

        {% set table_name = table['name'] %}
        {% set stage_path = table['path'] %}

        {% set create_sql %}

            CREATE EXTERNAL TABLE IF NOT EXISTS
                {{ target.database }}.{{ external_schema }}.{{ table_name }}

            (
                RAW_DATA VARIANT AS (VALUE),

                SOURCE_FILE VARCHAR
                    AS (METADATA$FILENAME),

                FILE_ROW_NUMBER NUMBER
                    AS (METADATA$FILE_ROW_NUMBER)
            )

            LOCATION = @{{ target.database }}.{{ external_schema }}.{{ external_stage }}/{{ stage_path }}

            FILE_FORMAT = (
                FORMAT_NAME =
                    '{{ target.database }}.{{ external_schema }}.{{ external_file_format }}'
            )

            REFRESH_ON_CREATE = TRUE

        {% endset %}

        {% do log(
            'Creating external table: '
            ~ target.database
            ~ '.'
            ~ external_schema
            ~ '.'
            ~ table_name,
            info=True
        ) %}

        {% do run_query(create_sql) %}

    {% endfor %}

{% endmacro %}