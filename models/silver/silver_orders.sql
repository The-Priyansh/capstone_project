{{ config(
    materialized='table'
) }}

WITH source_data AS (

    SELECT
        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,
        RAW_DATA

    FROM {{ ref('bronze_orders') }}

),

    -- 1. FLATTEN ORDERS


orders_flattened AS (

    SELECT

        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,

        order_data.value AS order_data

    FROM source_data,

    LATERAL FLATTEN(
        INPUT => RAW_DATA:orders_data
    ) order_data

),

    -- 2. EXTRACT ORDER-LEVEL DATA
    

orders AS (

    SELECT

        _SOURCE_FILE,
        _FILE_ROW_NUMBER,
        _LOADED_AT,
        _BATCH_ID,

        NULLIF(
            TRIM(order_data:order_id::VARCHAR),
            ''
        )::VARCHAR AS order_id,

        NULLIF(
            TRIM(order_data:customer_id::VARCHAR),
            ''
        )::VARCHAR AS customer_id,

        NULLIF(
            TRIM(order_data:employee_id::VARCHAR),
            ''
        )::VARCHAR AS employee_id,

        NULLIF(
            TRIM(order_data:campaign_id::VARCHAR),
            ''
        )::VARCHAR AS campaign_id,

        NULLIF(
            TRIM(order_data:store_id::VARCHAR),
            ''
        )::VARCHAR AS store_id,


        
        --TIMESTAMPS
    

        TRY_TO_TIMESTAMP_NTZ(
            order_data:created_at::VARCHAR
        ) AS created_at,

        TRY_TO_TIMESTAMP_NTZ(
            order_data:order_date::VARCHAR
        ) AS order_date,

        TRY_TO_TIMESTAMP_NTZ(
            order_data:shipping_date::VARCHAR
        ) AS shipping_date,

        TRY_TO_TIMESTAMP_NTZ(
            order_data:delivery_date::VARCHAR
        ) AS delivery_date,

        TRY_TO_TIMESTAMP_NTZ(
            order_data:estimated_delivery_date::VARCHAR
        ) AS estimated_delivery_date,


        
        --    ORDER ATTRIBUTES
        

        LOWER(
            TRIM(order_data:order_source::VARCHAR)
        )::VARCHAR AS order_source,

        INITCAP(
            TRIM(order_data:order_status::VARCHAR)
        )::VARCHAR AS order_status,

        INITCAP(
            TRIM(order_data:payment_method::VARCHAR)
        )::VARCHAR AS payment_method,

        INITCAP(
            TRIM(order_data:shipping_method::VARCHAR)
        )::VARCHAR AS shipping_method,


        /*
            ORDER-LEVEL DISCOUNT

            SOURCE IS PERCENTAGE, e.g. 6.63 = 6.63%

            Store both:
              original percentage
              normalized fraction
        */

        TRY_TO_DECIMAL(
            order_data:discount_amount::VARCHAR,
            10,
            4
        )::NUMBER(10,4) AS order_discount_percentage,

        (
            COALESCE(
                TRY_TO_DECIMAL(
                    order_data:discount_amount::VARCHAR,
                    10,
                    4
                ),
                0
            ) / 100
        )::NUMBER(12,8) AS order_discount_rate,



        --MONEY


        TRY_TO_DECIMAL(
            order_data:shipping_cost::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS shipping_cost,

        TRY_TO_DECIMAL(
            order_data:tax_amount::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS tax_amount,

        TRY_TO_DECIMAL(
            order_data:total_amount::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS source_total_amount,


        
        --ADDRESSES


        INITCAP(
            TRIM(order_data:billing_address:street::VARCHAR)
        )::VARCHAR AS billing_street,

        INITCAP(
            TRIM(order_data:billing_address:city::VARCHAR)
        )::VARCHAR AS billing_city,

        UPPER(
            TRIM(order_data:billing_address:state::VARCHAR)
        )::VARCHAR AS billing_state,

        TRIM(
            order_data:billing_address:zip_code::VARCHAR
        )::VARCHAR AS billing_zip_code,

        INITCAP(
            TRIM(order_data:shipping_address:street::VARCHAR)
        )::VARCHAR AS shipping_street,

        INITCAP(
            TRIM(order_data:shipping_address:city::VARCHAR)
        )::VARCHAR AS shipping_city,

        UPPER(
            TRIM(order_data:shipping_address:state::VARCHAR)
        )::VARCHAR AS shipping_state,

        TRIM(
            order_data:shipping_address:zip_code::VARCHAR
        )::VARCHAR AS shipping_zip_code,

        order_data:order_items AS order_items

    FROM orders_flattened

),

    -- 3. FLATTEN ORDER ITEMS

order_items_flattened AS (

    SELECT

        o.order_id,

        item.value:product_id::VARCHAR AS product_id,

        TRY_TO_NUMBER(
            item.value:quantity::VARCHAR
        )::NUMBER(18,0) AS quantity,

        TRY_TO_DECIMAL(
            item.value:unit_price::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS unit_price,

        TRY_TO_DECIMAL(
            item.value:cost_price::VARCHAR,
            18,
            2
        )::NUMBER(18,2) AS cost_price,


        /*
            ITEM DISCOUNT IS A PERCENTAGE
        */

        TRY_TO_DECIMAL(
            item.value:discount_amount::VARCHAR,
            10,
            4
        )::NUMBER(10,4) AS item_discount_percentage,

        (
            COALESCE(
                TRY_TO_DECIMAL(
                    item.value:discount_amount::VARCHAR,
                    10,
                    4
                ),
                0
            ) / 100
        )::NUMBER(12,8) AS item_discount_rate

    FROM orders o,

    LATERAL FLATTEN(
        INPUT => o.order_items
    ) item

),

    --4. AGGREGATE ITEM DATA TO ORDER GRAIN

item_aggregates AS (

    SELECT

        order_id,

        COUNT(product_id)::NUMBER(18,0)
            AS total_items,

        SUM(quantity)::NUMBER(18,0)
            AS total_quantity,


        /*
            PS:
            line_revenue =
            SUM(quantity * unit_price * (1 - discount))
        */

        SUM(
            quantity
            * unit_price
            * (1 - item_discount_rate)
        )::NUMBER(18,2)
            AS line_revenue,


        /*
            PS:
            line_cost =
            SUM(quantity * cost_price)
        */

        SUM(
            quantity * cost_price
        )::NUMBER(18,2)
            AS line_cost,


        /*
            Total discount represented by line-item discounts.
        */

        SUM(
            quantity * unit_price * item_discount_rate
        )::NUMBER(18,2)
            AS item_discount_amount,


        /*
            Useful audit metric:
            raw gross value before item discounts.
        */

        SUM(
            quantity * unit_price
        )::NUMBER(18,2)
            AS gross_item_amount

    FROM order_items_flattened

    GROUP BY order_id

),

    --5. JOIN ORDER + ITEM AGGREGATES

joined AS (

    SELECT

        o.*,

        COALESCE(
            a.total_items,
            0
        )::NUMBER(18,0) AS total_items,

        COALESCE(
            a.total_quantity,
            0
        )::NUMBER(18,0) AS total_quantity,

        COALESCE(
            a.line_revenue,
            0
        )::NUMBER(18,2) AS line_revenue,

        COALESCE(
            a.line_cost,
            0
        )::NUMBER(18,2) AS line_cost,

        COALESCE(
            a.item_discount_amount,
            0
        )::NUMBER(18,2) AS item_discount_amount,

        COALESCE(
            a.gross_item_amount,
            0
        )::NUMBER(18,2) AS gross_item_amount

    FROM orders o

    LEFT JOIN item_aggregates a
        ON o.order_id = a.order_id

),

    -- 6) ORDER PROFITABILITY

profitability AS (

    SELECT

        j.*,

        /*
            PS LOGIC:

            profit_amount =
                (line_revenue * (1 - order_discount_rate))
                - line_cost
                - shipping_cost
                - tax_amount
        */

        (
            line_revenue
            * (1 - order_discount_rate)
        )
        - line_cost
        - COALESCE(shipping_cost, 0)
        - COALESCE(tax_amount, 0)

        ::NUMBER(18,2) AS profit_amount,


        /*
            PS:
            profit_margin_percentage =
            profit_amount / line_revenue * 100
        */

        CASE

            WHEN line_revenue > 0

            THEN (

                (
                    (
                        line_revenue
                        * (1 - order_discount_rate)
                    )
                    - line_cost
                    - COALESCE(shipping_cost, 0)
                    - COALESCE(tax_amount, 0)
                )
                / line_revenue

            ) * 100

            ELSE NULL

        END::NUMBER(18,2)
            AS profit_margin_percentage

    FROM joined j

),

    --7. TIME DIMENSIONS
    

time_derived AS (

    SELECT

        p.*,

        CAST(
            order_date AS DATE
        )::DATE AS order_date_only,


        EXTRACT(
            HOUR FROM order_date
        )::NUMBER(2,0) AS order_hour,


        YEAR(
            order_date
        )::NUMBER(4,0) AS order_year,

        MONTH(
            order_date
        )::NUMBER(2,0) AS order_month,

        QUARTER(
            order_date
        )::NUMBER(1,0) AS order_quarter,

        WEEK(
            order_date
        )::NUMBER(2,0) AS order_week,


        /*
            PS:
            half-open ranges

            05:00-12:00 = Morning
            12:00-17:00 = Afternoon
            17:00-22:00 = Evening
            otherwise    = Night
        */

        CASE

            WHEN EXTRACT(HOUR FROM order_date) >= 5
             AND EXTRACT(HOUR FROM order_date) < 12
                THEN 'Morning'

            WHEN EXTRACT(HOUR FROM order_date) >= 12
             AND EXTRACT(HOUR FROM order_date) < 17
                THEN 'Afternoon'

            WHEN EXTRACT(HOUR FROM order_date) >= 17
             AND EXTRACT(HOUR FROM order_date) < 22
                THEN 'Evening'

            ELSE 'Night'

        END::VARCHAR AS order_time_of_day

    FROM profitability p

),

    --8. SHIPPING / DELIVERY METRICS
    
shipping_metrics AS (

    SELECT

        t.*,

        /*
            Processing:
            order → shipping
        */

        CASE

            WHEN order_date IS NOT NULL
             AND shipping_date IS NOT NULL
             AND shipping_date >= order_date

            THEN DATEDIFF(
                DAY,
                CAST(order_date AS DATE),
                CAST(shipping_date AS DATE)
            )

            ELSE NULL

        END::NUMBER(10,0) AS processing_days,


        /*
            Shipping:
            shipping → delivery
        */

        CASE

            WHEN shipping_date IS NOT NULL
             AND delivery_date IS NOT NULL
             AND delivery_date >= shipping_date

            THEN DATEDIFF(
                DAY,
                CAST(shipping_date AS DATE),
                CAST(delivery_date AS DATE)
            )

            ELSE NULL

        END::NUMBER(10,0) AS shipping_days,



        --Delivery status exactly following PS.

        CASE

            WHEN delivery_date IS NOT NULL
             AND estimated_delivery_date IS NOT NULL
             AND delivery_date <= estimated_delivery_date

                THEN 'On Time'

            WHEN delivery_date IS NOT NULL
             AND estimated_delivery_date IS NOT NULL
             AND delivery_date > estimated_delivery_date

                THEN 'Delayed'

            WHEN delivery_date IS NULL
             AND estimated_delivery_date IS NOT NULL
             AND CURRENT_DATE() > CAST(
                 estimated_delivery_date AS DATE
             )

                THEN 'Potentially Delayed'

            ELSE 'In Transit'

        END::VARCHAR AS delivery_status

    FROM time_derived t

),


    --9. STANDARDIZED ADDRESSES

addresses AS (

    SELECT

        s.*,

        CONCAT_WS(
            ', ',

            NULLIF(billing_street, ''),
            NULLIF(billing_city, ''),
            NULLIF(billing_state, ''),
            NULLIF(billing_zip_code, '')

        )::VARCHAR AS billing_address,


        CONCAT_WS(
            ', ',

            NULLIF(shipping_street, ''),
            NULLIF(shipping_city, ''),
            NULLIF(shipping_state, ''),
            NULLIF(shipping_zip_code, '')

        )::VARCHAR AS shipping_address

    FROM shipping_metrics s

),

    --10. ORDER-LEVEL DEDUPLICATION
   

deduplicated AS (

    SELECT *

    FROM addresses

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY order_id

        ORDER BY
            order_date DESC NULLS LAST,
            _LOADED_AT DESC,
            _SOURCE_FILE DESC,
            _FILE_ROW_NUMBER DESC

    ) = 1

)

    --FINAL SILVER ORDER TABLE

SELECT

    --Lineage 

    _SOURCE_FILE,
    _FILE_ROW_NUMBER,
    _LOADED_AT,
    _BATCH_ID,


    -- Keys 

    order_id,
    customer_id,
    employee_id,
    campaign_id,
    store_id,


    -- Dates 

    created_at,
    order_date,
    order_date_only,
    shipping_date,
    delivery_date,
    estimated_delivery_date,


    -- Order attributes

    order_source,
    order_status,
    payment_method,
    shipping_method,


    -- Discount 

    order_discount_percentage,
    order_discount_rate,


    -- Financials

    source_total_amount,
    gross_item_amount,
    item_discount_amount,
    line_revenue,
    line_cost,

    shipping_cost,
    tax_amount,

    profit_amount,
    profit_margin_percentage,


    -- Item aggregates 

    total_items,
    total_quantity,


    -- Time 

    order_hour,
    order_time_of_day,
    order_week,
    order_month,
    order_quarter,
    order_year,


    -- Shipping 

    processing_days,
    shipping_days,
    delivery_status,


    -- Addresses 

    billing_street,
    billing_city,
    billing_state,
    billing_zip_code,
    billing_address,

    shipping_street,
    shipping_city,
    shipping_state,
    shipping_zip_code,
    shipping_address

FROM deduplicated