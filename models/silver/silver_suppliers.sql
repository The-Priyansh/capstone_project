{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        supplier_id,
        last_modified_date,
        raw_supplier_data,
        dbt_scd_id,
        dbt_updated_at,
        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snp_suppliers') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        -- SUPPLIER ID

        NULLIF(
            TRIM(supplier_id),
            ''
        )::VARCHAR AS supplier_id,


        -- SUPPLIER NAME

        TRIM(
            REGEXP_REPLACE(
                raw_supplier_data:supplier_name::VARCHAR,
                '[^A-Za-z0-9 ,&''.-]',
                ''
            )
        )::VARCHAR AS supplier_name,


        INITCAP(
            TRIM(
                raw_supplier_data:supplier_type::VARCHAR
            )
        )::VARCHAR AS supplier_type,


        --CONTACT INFORMATION

        INITCAP(
            TRIM(
                raw_supplier_data:contact_information:contact_person::VARCHAR
            )
        )::VARCHAR AS contact_person,

        INITCAP(
            TRIM(
                raw_supplier_data:contact_information:address::VARCHAR
            )
        )::VARCHAR AS contact_address,


        -- EMAIL

        CASE
            WHEN REGEXP_LIKE(
                LOWER(
                    TRIM(
                        raw_supplier_data:
                        contact_information:email::VARCHAR
                    )
                ),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN LOWER(
                TRIM(
                    raw_supplier_data:
                    contact_information:email::VARCHAR
                )
            )
            ELSE NULL
        END::VARCHAR AS contact_email,

        CASE
            WHEN REGEXP_LIKE(
                LOWER(
                    TRIM(
                        raw_supplier_data:
                        contact_information:email::VARCHAR
                    )
                ),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_email_flag,


        /* PHONE */

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN REGEXP_REPLACE(
                TRIM(
                    raw_supplier_data:
                    contact_information:phone::VARCHAR
                ),
                '[^0-9]',
                ''
            )

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                ),
                1
            ) = '1'

            THEN RIGHT(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
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
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN FALSE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(
                        raw_supplier_data:
                        contact_information:phone::VARCHAR
                    ),
                    '[^0-9]',
                    ''
                ),
                1
            ) = '1'

            THEN FALSE

            ELSE TRUE

        END::BOOLEAN AS invalid_phone_flag,


        --CONTRACT DETAILS

        NULLIF(
            TRIM(
                raw_supplier_data:
                contract_details:contract_id::VARCHAR
            ),
            ''
        )::VARCHAR AS contract_id,

        TRY_TO_DATE(
            NULLIF(
                TRIM(
                    raw_supplier_data:
                    contract_details:start_date::VARCHAR
                ),
                ''
            )
        )::DATE AS contract_start_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(
                    raw_supplier_data:
                    contract_details:end_date::VARCHAR
                ),
                ''
            )
        )::DATE AS contract_end_date,

        COALESCE(
            raw_supplier_data:
            contract_details:exclusivity::BOOLEAN,
            FALSE
        )::BOOLEAN AS exclusivity,

        COALESCE(
            raw_supplier_data:
            contract_details:renewal_option::BOOLEAN,
            FALSE
        )::BOOLEAN AS renewal_option,


        --SUPPLIER ATTRIBUTES

        UPPER(
            TRIM(
                raw_supplier_data:credit_rating::VARCHAR
            )
        )::VARCHAR AS credit_rating,

        COALESCE(
            raw_supplier_data:is_active::BOOLEAN,
            FALSE
        )::BOOLEAN AS is_active,

        INITCAP(
            TRIM(
                raw_supplier_data:payment_terms::VARCHAR
            )
        )::VARCHAR AS payment_terms,

        INITCAP(
            TRIM(
                raw_supplier_data:preferred_carrier::VARCHAR
            )
        )::VARCHAR AS preferred_carrier,

        NULLIF(
            TRIM(
                raw_supplier_data:website::VARCHAR
            ),
            ''
        )::VARCHAR AS website,

        NULLIF(
            TRIM(
                raw_supplier_data:tax_id::VARCHAR
            ),
            ''
        )::VARCHAR AS tax_id,


        /* =========================
           CATEGORIES SUPPLIED
           Preserve array to maintain
           one-row-per-supplier grain.
           ========================= */

        raw_supplier_data:categories_supplied
            AS categories_supplied,


        -- SUPPLIER DATES

        TRY_TO_DATE(
            NULLIF(
                TRIM(
                    raw_supplier_data:last_order_date::VARCHAR
                ),
                ''
            )
        )::DATE AS last_order_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(
                    raw_supplier_data:last_modified_date::VARCHAR
                ),
                ''
            )
        )::DATE AS last_modified_date,


        -- NUMERIC SUPPLIER METRICS

        TRY_TO_NUMBER(
            raw_supplier_data:
            lead_time_days::VARCHAR
        )::NUMBER(10,0) AS lead_time_days,

        TRY_TO_NUMBER(
            raw_supplier_data:
            minimum_order_quantity::VARCHAR
        )::NUMBER(18,0) AS minimum_order_quantity,

        TRY_TO_NUMBER(
            raw_supplier_data:
            year_established::VARCHAR
        )::NUMBER(4,0) AS year_established,


        --PERFORMANCE METRICS

        TRY_TO_DECIMAL(
            raw_supplier_data:
            performance_metrics:average_delay_days::VARCHAR,
            10,
            2
        )::NUMBER(10,2) AS average_delay_days,

        TRY_TO_DECIMAL(
            raw_supplier_data:
            performance_metrics:defect_rate::VARCHAR,
            10,
            4
        )::NUMBER(10,4) AS defect_rate,

        TRY_TO_DECIMAL(
            raw_supplier_data:
            performance_metrics:on_time_delivery_rate::VARCHAR,
            10,
            2
        )::NUMBER(10,2) AS on_time_delivery_rate,

        INITCAP(
            TRIM(
                raw_supplier_data:
                performance_metrics:quality_rating::VARCHAR
            )
        )::VARCHAR AS quality_rating,

        TRY_TO_DECIMAL(
            raw_supplier_data:
            performance_metrics:response_time_hours::VARCHAR,
            10,
            2
        )::NUMBER(10,2) AS response_time_hours,

        TRY_TO_DECIMAL(
            raw_supplier_data:
            performance_metrics:returns_percentage::VARCHAR,
            10,
            2
        )::NUMBER(10,2) AS returns_percentage,


        --SNAPSHOT METADATA

        dbt_scd_id::VARCHAR AS dbt_scd_id,

        dbt_updated_at::TIMESTAMP_NTZ
            AS dbt_updated_at,

        dbt_valid_from::TIMESTAMP_NTZ
            AS dbt_valid_from,

        dbt_valid_to::TIMESTAMP_NTZ
            AS dbt_valid_to

    FROM source_data

),

derived AS (

    SELECT
        s.*,

        --CONTRACT DURATION

        CASE
            WHEN contract_start_date IS NOT NULL
             AND contract_end_date IS NOT NULL
             AND contract_end_date >= contract_start_date

            THEN DATEDIFF(
                DAY,
                contract_start_date,
                contract_end_date
            )

            ELSE NULL
        END::NUMBER(10,0) AS contract_duration_days,


        --CONTRACT STATUS 

        CASE
            WHEN contract_start_date IS NULL
              OR contract_end_date IS NULL
                THEN 'Unknown'

            WHEN CURRENT_DATE() < contract_start_date
                THEN 'Not Started'

            WHEN CURRENT_DATE() > contract_end_date
                THEN 'Expired'

            ELSE 'Active'

        END::VARCHAR AS contract_status

    FROM cleaned s

),

deduplicated AS (

    SELECT *

    FROM derived

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY supplier_id

        ORDER BY
            last_modified_date DESC NULLS LAST,
            dbt_valid_from DESC NULLS LAST,
            dbt_updated_at DESC NULLS LAST,
            dbt_scd_id DESC

    ) = 1

)

SELECT

    supplier_id,
    supplier_name,
    supplier_type,

    contact_person,
    contact_address,
    contact_email,
    invalid_email_flag,

    phone,
    invalid_phone_flag,

    contract_id,
    contract_start_date,
    contract_end_date,
    contract_duration_days,
    contract_status,
    exclusivity,
    renewal_option,

    credit_rating,
    is_active,
    payment_terms,
    preferred_carrier,
    website,
    tax_id,

    categories_supplied,

    last_order_date,
    last_modified_date,

    lead_time_days,
    minimum_order_quantity,
    year_established,

    average_delay_days,
    defect_rate,
    on_time_delivery_rate,
    quality_rating,
    response_time_hours,
    returns_percentage,

    dbt_scd_id,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to

FROM deduplicated