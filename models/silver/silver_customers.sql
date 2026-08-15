{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        customer_id,
        last_modified_date,
        raw_customer_data,
        dbt_scd_id,
        dbt_updated_at,
        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snp_customers') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        --IDENTITY

        NULLIF(
            TRIM(customer_id),
            ''
        )::VARCHAR AS customer_id,

        INITCAP(
            REGEXP_REPLACE(
                TRIM(raw_customer_data:first_name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS first_name,

        INITCAP(
            REGEXP_REPLACE(
                TRIM(raw_customer_data:last_name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS last_name,

        --EMAIL

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_customer_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN LOWER(TRIM(raw_customer_data:email::VARCHAR))
            ELSE NULL
        END::VARCHAR AS email,

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_customer_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_email_flag,

        --PHONE

        CASE
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(
                    TRIM(raw_customer_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                '^[0-9]{10}$'
            )
            THEN REGEXP_REPLACE(
                TRIM(raw_customer_data:phone::VARCHAR),
                '[^0-9]',
                ''
            )
            ELSE NULL
        END::VARCHAR AS phone,

        CASE
            WHEN REGEXP_LIKE(
                REGEXP_REPLACE(
                    TRIM(raw_customer_data:phone::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                '^[0-9]{10}$'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_phone_flag,

        --ADDRESS

        INITCAP(
            TRIM(raw_customer_data:address:street::VARCHAR)
        )::VARCHAR AS street,

        INITCAP(
            TRIM(raw_customer_data:address:city::VARCHAR)
        )::VARCHAR AS city,

        UPPER(
            TRIM(raw_customer_data:address:state::VARCHAR)
        )::VARCHAR AS state,

        UPPER(
            TRIM(raw_customer_data:address:country::VARCHAR)
        )::VARCHAR AS country,

        TRIM(
            raw_customer_data:address:zip_code::VARCHAR
        )::VARCHAR AS zip_code,

        CONCAT_WS(
            ', ',

            NULLIF(
                INITCAP(TRIM(
                    raw_customer_data:address:street::VARCHAR
                )),
                ''
            ),

            NULLIF(
                INITCAP(TRIM(
                    raw_customer_data:address:city::VARCHAR
                )),
                ''
            ),

            NULLIF(
                UPPER(TRIM(
                    raw_customer_data:address:state::VARCHAR
                )),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_customer_data:address:zip_code::VARCHAR
                ),
                ''
            ),

            NULLIF(
                UPPER(TRIM(
                    raw_customer_data:address:country::VARCHAR
                )),
                ''
            )

        )::VARCHAR AS standardized_address,

        --CUSTOMER ATTRIBUTES

        UPPER(
            TRIM(raw_customer_data:income_bracket::VARCHAR)
        )::VARCHAR AS income_bracket,

        INITCAP(
            TRIM(raw_customer_data:occupation::VARCHAR)
        )::VARCHAR AS occupation,

        UPPER(
            TRIM(raw_customer_data:loyalty_tier::VARCHAR)
        )::VARCHAR AS loyalty_tier,

        INITCAP(
            TRIM(raw_customer_data:preferred_communication::VARCHAR)
        )::VARCHAR AS preferred_communication,

        INITCAP(
            TRIM(raw_customer_data:preferred_payment_method::VARCHAR)
        )::VARCHAR AS preferred_payment_method,

        COALESCE(
            raw_customer_data:marketing_opt_in::BOOLEAN,
            FALSE
        )::BOOLEAN AS marketing_opt_in,

        --DATES

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_customer_data:birth_date::VARCHAR),
                ''
            )
        )::DATE AS birth_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_customer_data:registration_date::VARCHAR),
                ''
            )
        )::DATE AS registration_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_customer_data:last_purchase_date::VARCHAR),
                ''
            )
        )::DATE AS last_purchase_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_customer_data:last_modified_date::VARCHAR),
                ''
            )
        )::DATE AS last_modified_date,

        --NUMERIC / CURRENCY

        COALESCE(
            TRY_TO_NUMBER(
                TRIM(raw_customer_data:total_purchases::VARCHAR)
            ),
            0
        )::NUMBER(18,0) AS total_purchases,

        COALESCE(
            TRY_TO_DECIMAL(
                REGEXP_REPLACE(
                    TRIM(raw_customer_data:total_spend::VARCHAR),
                    '[$,]',
                    ''
                ),
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS total_spend,

        --SNAPSHOT METADATA

        dbt_scd_id::VARCHAR AS dbt_scd_id,
        dbt_updated_at::TIMESTAMP_NTZ AS dbt_updated_at,
        dbt_valid_from::TIMESTAMP_NTZ AS dbt_valid_from,
        dbt_valid_to::TIMESTAMP_NTZ AS dbt_valid_to

    FROM source_data

),

derived AS (

    SELECT
        c.*,

        -- Full name 
        TRIM(
            CONCAT_WS(
                ' ',
                NULLIF(c.first_name, ''),
                NULLIF(c.last_name, '')
            )
        )::VARCHAR AS full_name,

        --Customer age 
        CASE
            WHEN c.birth_date IS NOT NULL
            THEN DATEDIFF(
                YEAR,
                c.birth_date,
                CURRENT_DATE()
            )
            ELSE NULL
        END::NUMBER(3,0) AS customer_age

    FROM cleaned c

),

segmented AS (

    SELECT
        d.*,

        CASE
            WHEN customer_age BETWEEN 18 AND 35
                THEN 'Young'

            WHEN customer_age BETWEEN 36 AND 55
                THEN 'Middle-aged'

            WHEN customer_age >= 56
                THEN 'Senior'

            ELSE NULL
        END::VARCHAR AS customer_segment

    FROM derived d

),

deduplicated AS (

    SELECT *

    FROM segmented

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY
            last_modified_date DESC NULLS LAST,
            dbt_valid_from DESC NULLS LAST,
            dbt_updated_at DESC NULLS LAST,
            dbt_scd_id DESC
    ) = 1

)

SELECT
    customer_id,
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
    country,
    zip_code,
    standardized_address,

    income_bracket,
    occupation,
    loyalty_tier,
    marketing_opt_in,
    preferred_communication,
    preferred_payment_method,

    birth_date,
    registration_date,
    last_purchase_date,
    last_modified_date,

    total_purchases,
    total_spend,

    customer_age,
    customer_segment,

    dbt_scd_id,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to

FROM deduplicated