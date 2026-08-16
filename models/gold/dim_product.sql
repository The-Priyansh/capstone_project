{{ config(
    materialized='table'
) }}

WITH history AS (

    SELECT

        product_id,

        product_name,
        category,
        subcategory,
        brand,
        color,
        size,

        unit_price,
        cost_price,

        supplier_id,

        source_snapshot_date,

        /*
            Hash only attributes that belong
            to the Product dimension.

            If any of these changes, we need
            a new SCD2 version.
        */

        MD5(
            CONCAT_WS(
                '|',

                COALESCE(product_name, ''),
                COALESCE(category, ''),
                COALESCE(subcategory, ''),
                COALESCE(brand, ''),
                COALESCE(color, ''),
                COALESCE(size, ''),
                COALESCE(unit_price::VARCHAR, ''),
                COALESCE(cost_price::VARCHAR, ''),
                COALESCE(supplier_id, '')
            )
        ) AS attribute_hash

    FROM {{ ref('silver_product_history') }}

),

/*
    Compare each product observation with
    the previous observation.

    Only actual attribute changes create
    a new SCD2 version.
*/

change_detection AS (

    SELECT

        h.*,

        LAG(attribute_hash) OVER (
            PARTITION BY product_id
            ORDER BY source_snapshot_date
        ) AS previous_attribute_hash

    FROM history h

),

change_points AS (

    SELECT

        *,

        CASE

            WHEN previous_attribute_hash IS NULL
                THEN 1

            WHEN attribute_hash <> previous_attribute_hash
                THEN 1

            ELSE 0

        END AS is_change

    FROM change_detection

),

versioned AS (

    SELECT

        *,

        SUM(is_change) OVER (

            PARTITION BY product_id

            ORDER BY source_snapshot_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS version_number

    FROM change_points

),

scd_versions AS (

    SELECT

        product_id,

        version_number,

        MIN(source_snapshot_date)
            AS effective_from,

        MAX(product_name)
            AS product_name,

        MAX(category)
            AS category,

        MAX(subcategory)
            AS subcategory,

        MAX(brand)
            AS brand,

        MAX(color)
            AS color,

        MAX(size)
            AS size,

        MAX(unit_price)
            AS unit_price,

        MAX(cost_price)
            AS cost_price,

        MAX(supplier_id)
            AS supplier_id

    FROM versioned

    GROUP BY
        product_id,
        version_number

),

with_end_dates AS (

    SELECT

        *,

        LEAD(effective_from) OVER (

            PARTITION BY product_id
            ORDER BY effective_from

        ) AS next_effective_from

    FROM scd_versions

)

SELECT

    /*
        Surrogate Product Key

        Different versions of the same
        natural ProductID receive different
        surrogate keys.
    */

    MD5(
        CONCAT(
            product_id,
            '|',
            effective_from
        )
    ) AS product_key,


    product_id,

    product_name,
    category,
    subcategory,
    brand,
    color,
    size,

    unit_price,
    cost_price,

    supplier_id,


    
    --SCD TYPE 2 DATES
    

    effective_from,

    CASE

        WHEN next_effective_from IS NOT NULL

        THEN DATEADD(
            DAY,
            -1,
            next_effective_from
        )

        ELSE NULL

    END AS effective_to,


    CASE

        WHEN next_effective_from IS NULL
            THEN TRUE

        ELSE FALSE

    END AS is_current

FROM with_end_dates