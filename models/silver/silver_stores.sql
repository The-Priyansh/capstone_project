{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        store_id,
        last_modified_date,
        raw_store_data,
        dbt_scd_id,
        dbt_updated_at,
        dbt_valid_from,
        dbt_valid_to

    FROM {{ ref('snp_stores') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        --STORE ID
        

        NULLIF(
            TRIM(store_id),
            ''
        )::VARCHAR AS store_id,


        /* STORE NAME
           Pascal / Title Case
        */

        INITCAP(
            REGEXP_REPLACE(
                TRIM(raw_store_data:store_name::VARCHAR),
                '[^A-Za-z0-9 ''-]',
                ''
            )
        )::VARCHAR AS store_name,


        --STORE ATTRIBUTES

        INITCAP(
            TRIM(raw_store_data:store_type::VARCHAR)
        )::VARCHAR AS store_type,

        INITCAP(
            TRIM(raw_store_data:region::VARCHAR)
        )::VARCHAR AS region,


        --EMAIL

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_store_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN LOWER(TRIM(raw_store_data:email::VARCHAR))
            ELSE NULL
        END::VARCHAR AS email,

        CASE
            WHEN REGEXP_LIKE(
                LOWER(TRIM(raw_store_data:email::VARCHAR)),
                '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$',
                'i'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_email_flag,


        /* PHONE
           Normalize US 10 / +1 11 digit
           numbers to 10 digits. */

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN REGEXP_REPLACE(
                TRIM(raw_store_data:phone_number::VARCHAR),
                '[^0-9]',
                ''
            )

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                1
            ) = '1'

            THEN RIGHT(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                ),
                10
            )

            ELSE NULL

        END::VARCHAR AS phone_number,

        CASE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 10

            THEN FALSE

            WHEN LENGTH(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
                    '[^0-9]',
                    ''
                )
            ) = 11

            AND LEFT(
                REGEXP_REPLACE(
                    TRIM(raw_store_data:phone_number::VARCHAR),
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
            TRIM(raw_store_data:address:street::VARCHAR)
        )::VARCHAR AS street,

        INITCAP(
            TRIM(raw_store_data:address:city::VARCHAR)
        )::VARCHAR AS city,

        UPPER(
            TRIM(raw_store_data:address:state::VARCHAR)
        )::VARCHAR AS state,

        UPPER(
            TRIM(raw_store_data:address:country::VARCHAR)
        )::VARCHAR AS country,

        TRIM(
            raw_store_data:address:zip_code::VARCHAR
        )::VARCHAR AS zip_code,


        /* POSTAL CODE VALIDATION

           US ZIP:
             12345
             12345-6789
        */

        CASE
            WHEN REGEXP_LIKE(
                TRIM(
                    raw_store_data:address:zip_code::VARCHAR
                ),
                '^[0-9]{5}(-[0-9]{4})?$'
            )
            THEN FALSE
            ELSE TRUE
        END::BOOLEAN AS invalid_postal_code_flag,


        CONCAT_WS(
            ', ',

            NULLIF(
                INITCAP(
                    TRIM(
                        raw_store_data:address:street::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                INITCAP(
                    TRIM(
                        raw_store_data:address:city::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                UPPER(
                    TRIM(
                        raw_store_data:address:state::VARCHAR
                    )
                ),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_store_data:address:zip_code::VARCHAR
                ),
                ''
            ),

            NULLIF(
                UPPER(
                    TRIM(
                        raw_store_data:address:country::VARCHAR
                    )
                ),
                ''
            )

        )::VARCHAR AS standardized_address,


        --NUMERIC ATTRIBUTES

        COALESCE(
            TRY_TO_DECIMAL(
                raw_store_data:current_sales::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS current_sales,

        COALESCE(
            TRY_TO_DECIMAL(
                raw_store_data:sales_target::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS sales_target,

        COALESCE(
            TRY_TO_DECIMAL(
                raw_store_data:monthly_rent::VARCHAR,
                18,
                2
            ),
            0.00
        )::NUMBER(18,2) AS monthly_rent,

        COALESCE(
            TRY_TO_NUMBER(
                raw_store_data:employee_count::VARCHAR
            ),
            0
        )::NUMBER(18,0) AS employee_count,

        COALESCE(
            TRY_TO_NUMBER(
                raw_store_data:size_sq_ft::VARCHAR
            ),
            0
        )::NUMBER(18,0) AS size_sq_ft,


        --STATUS / REFERENCES

        COALESCE(
            raw_store_data:is_active::BOOLEAN,
            FALSE
        )::BOOLEAN AS is_active,

        NULLIF(
            TRIM(raw_store_data:manager_id::VARCHAR),
            ''
        )::VARCHAR AS manager_id,


        --DATE

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_store_data:opening_date::VARCHAR),
                ''
            )
        )::DATE AS opening_date,

        TRY_TO_DATE(
            NULLIF(
                TRIM(raw_store_data:last_modified_date::VARCHAR),
                ''
            )
        )::DATE AS last_modified_date,


        /* NESTED / ARRAY ATTRIBUTES

           Preserve structure because
           PS does not require exploding
           these into separate rows.
         */

        raw_store_data:operating_hours
            AS operating_hours,

        raw_store_data:services
            AS services,


        --SNAPSHOT METADATA
        

        dbt_scd_id::VARCHAR
            AS dbt_scd_id,

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


        /* STORE SIZE CATEGORY

           PS:
           < 5000      = Small
           5000-10000  = Medium
           > 10000     = Large
         */

        CASE

            WHEN size_sq_ft < 5000
                THEN 'Small'

            WHEN size_sq_ft BETWEEN 5000 AND 10000
                THEN 'Medium'

            WHEN size_sq_ft > 10000
                THEN 'Large'

            ELSE NULL

        END::VARCHAR AS size_category,


        --STORE AGE

        CASE
            WHEN opening_date IS NOT NULL
            THEN DATEDIFF(
                YEAR,
                opening_date,
                CURRENT_DATE()
            )
            ELSE NULL
        END::NUMBER(4,0) AS store_age_years,


        /* =========================
           SALES TARGET ACHIEVEMENT
           ========================= */

        CASE

            WHEN sales_target > 0

            THEN (
                current_sales / sales_target
            ) * 100

            ELSE NULL

        END::NUMBER(18,2)
            AS sales_target_achievement_percentage,


        --REVENUE PER SQ FT 

        CASE

            WHEN size_sq_ft > 0

            THEN current_sales / size_sq_ft

            ELSE NULL

        END::NUMBER(18,2)
            AS revenue_per_sq_ft,


        /* =========================
           EMPLOYEE EFFICIENCY
           ========================= */

        CASE

            WHEN employee_count > 0

            THEN current_sales / employee_count

            ELSE NULL

        END::NUMBER(18,2)
            AS employee_efficiency

    FROM cleaned s

),

finalized AS (

    SELECT
        d.*,

        /* PERFORMANCE ISSUE FLAG

           PS:
           achievement < 90%
        */

        CASE

            WHEN sales_target_achievement_percentage < 90
                THEN TRUE

            WHEN sales_target_achievement_percentage IS NULL
                THEN NULL

            ELSE FALSE

        END::BOOLEAN AS performance_issue_flag

    FROM derived d

),

deduplicated AS (

    SELECT *

    FROM finalized

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY store_id

        ORDER BY
            last_modified_date DESC NULLS LAST,
            dbt_valid_from DESC NULLS LAST,
            dbt_updated_at DESC NULLS LAST,
            dbt_scd_id DESC

    ) = 1

)

SELECT

    store_id,
    store_name,

    store_type,
    region,

    email,
    invalid_email_flag,

    phone_number,
    invalid_phone_flag,

    street,
    city,
    state,
    country,
    zip_code,
    invalid_postal_code_flag,
    standardized_address,

    current_sales,
    sales_target,
    monthly_rent,
    employee_count,
    size_sq_ft,

    size_category,
    store_age_years,

    sales_target_achievement_percentage,
    revenue_per_sq_ft,
    employee_efficiency,
    performance_issue_flag,

    manager_id,
    is_active,
    opening_date,
    last_modified_date,

    operating_hours,
    services,

    dbt_scd_id,
    dbt_updated_at,
    dbt_valid_from,
    dbt_valid_to

FROM deduplicated