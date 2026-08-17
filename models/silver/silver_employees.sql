{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        employee_id,
        last_modified_date,
        raw_employee_data,
        dbt_scd_id,
        dbt_updated_at,
        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snp_employees') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        --IDENTITY

        NULLIF(
            TRIM(employee_id),
            ''
        )::VARCHAR AS employee_id,


        
        --FIRST / LAST NAME
        

        INITCAP(
            REGEXP_REPLACE(
                TRIM(raw_employee_data:first_name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS first_name,

        INITCAP(
            REGEXP_REPLACE(
                TRIM(raw_employee_data:last_name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS last_name,


        
        --EMAIL
        

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_employee_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN LOWER(TRIM(raw_employee_data:email::VARCHAR))
            ELSE NULL
        END::VARCHAR AS email,

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_employee_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_email_flag,


        /*
           PHONE

           Accept:
             10 digits
             11 digits beginning with country code 1

           Store canonical 10-digit representation.
        */

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN REGEXP_REPLACE(
                TRIM(raw_employee_data:phone::VARCHAR),
                '[^0-9]',
                ''
            )

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                1
            ) = '1'

            THEN RIGHT(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                10
            )

            ELSE NULL

        END::VARCHAR AS phone,

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN FALSE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(raw_employee_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                1
            ) = '1'

            THEN FALSE

            ELSE TRUE

        END::BOOLEAN AS invalid_phone_flag,

        --ADDRESS

        INITCAP(
            TRIM(raw_employee_data:address:street::VARCHAR)
        )::VARCHAR AS street,

        INITCAP(
            TRIM(raw_employee_data:address:city::VARCHAR)
        )::VARCHAR AS city,

        UPPER(
            TRIM(raw_employee_data:address:state::VARCHAR)
        )::VARCHAR AS state,

        TRIM(
            raw_employee_data:address:zip_code::VARCHAR
        )::VARCHAR AS zip_code,


        CONCAT_WS(
            ', ',

            NULLIF(
                INITCAP(
                    TRIM(
                        raw_employee_data:address:street::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                INITCAP(
                    TRIM(
                        raw_employee_data:address:city::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                UPPER(
                    TRIM(
                        raw_employee_data:address:state::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_employee_data:address:zip_code::VARCHAR
                ),
                ''
            )

        )::VARCHAR AS standardized_address,

        --EMPLOYEE ATTRIBUTES

        INITCAP(
            TRIM(raw_employee_data:department::VARCHAR)
        )::VARCHAR AS department,

        INITCAP(
            TRIM(raw_employee_data:education::VARCHAR)
        )::VARCHAR AS education,

        INITCAP(
            TRIM(raw_employee_data:role::VARCHAR)
        )::VARCHAR AS role,

        INITCAP(
            TRIM(raw_employee_data:employment_status::VARCHAR)
        )::VARCHAR AS employment_status,

        NULLIF(
            TRIM(raw_employee_data:manager_id::VARCHAR),
            ''
        )::VARCHAR AS manager_id,

        NULLIF(
            TRIM(raw_employee_data:work_location::VARCHAR),
            ''
        )::VARCHAR AS work_location,


        /*
           Certifications is naturally an ARRAY.
           Keep it as an ARRAY in Silver instead of
           destroying its structure.
        */

        raw_employee_data:certifications AS certifications,


        --DATES

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_employee_data:date_of_birth::VARCHAR),
                ''
            )
        )::DATE AS date_of_birth,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_employee_data:hire_date::VARCHAR),
                ''
            )
        )::DATE AS hire_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_employee_data:last_modified_date::VARCHAR),
                ''
            )
        )::DATE AS last_modified_date,

        --NUMERIC VALUES

        COALESCE(
            TRY_TO_DECIMAL(
                raw_employee_data:current_sales::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS current_sales,

        COALESCE(
            TRY_TO_DECIMAL(
                raw_employee_data:salary::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS salary,

        COALESCE(
            TRY_TO_DECIMAL(
                raw_employee_data:sales_target::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS sales_target,

        TRY_TO_DECIMAL(
            raw_employee_data:performance_rating::VARCHAR,
            5,
            2
        )::NUMBER(5,2) AS performance_rating,

        --SNAPSHOT METADATA

        dbt_scd_id::VARCHAR AS dbt_scd_id,

        dbt_updated_at::TIMESTAMP_NTZ AS dbt_updated_at,

        dbt_valid_from::TIMESTAMP_NTZ AS dbt_valid_from,

        dbt_valid_to::TIMESTAMP_NTZ AS dbt_valid_to

    FROM source_data

),

derived AS (

    SELECT

        e.*,

        /*
           FULL NAME
        */

        TRIM(
            CONCAT_WS(
                ' ',
                NULLIF(e.first_name, ''),
                NULLIF(e.last_name, '')
            )
        )::VARCHAR AS full_name

    FROM cleaned e

),

deduplicated AS (

    SELECT *

    FROM derived

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY employee_id

        ORDER BY
            last_modified_date DESC NULLS LAST,
            dbt_valid_from DESC NULLS LAST,
            dbt_updated_at DESC NULLS LAST,
            dbt_scd_id DESC

    ) = 1

)

SELECT

    employee_id,

    first_name,
    last_name,
    full_name,

    email,
    invalid_email_flag,

    phone,
    invalid_phone_flag,

    street,
    city,
    state,
    zip_code,
    standardized_address,

    department,
    education,
    role,
    employment_status,

    manager_id,
    work_location,

    certifications,

    date_of_birth,
    hire_date,
    last_modified_date,

    current_sales,
    salary,
    sales_target,
    performance_rating,

    dbt_scd_id,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to

FROM deduplicated