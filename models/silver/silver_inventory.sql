{{ config(
    materialized='table'
) }}

/*
    SILVER INVENTORY

    Grain:
        One row per product per observed inventory snapshot date.

    Source:
        silver_product_history
            -> historical product stock snapshots

        silver_orders
        silver_order_items
            -> completed sales by product and date

    Important:
        The source product snapshots do not contain store_id.
        Therefore inventory is intentionally maintained at
        product + date grain rather than inventing a store assignment.

    Business logic:
        beginning_stock  = previous observed snapshot stock
        ending_stock     = current snapshot stock

        purchased_quantity =
            ending_stock - beginning_stock + sold_quantity

        This is inferred because receiving events are not provided
        by the source system.
*/


/* ================================================================
   1. PRODUCT SNAPSHOT HISTORY
   ================================================================ */

WITH product_snapshots AS (

    SELECT
        product_id,
        source_snapshot_date AS inventory_date,
        stock_quantity,
        reorder_level,
        cost_price,
        supplier_id
    FROM {{ ref('silver_product_history') }}

    WHERE product_id IS NOT NULL
      AND source_snapshot_date IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY
            product_id,
            source_snapshot_date

        ORDER BY
            source_snapshot_date DESC,
            product_id
    ) = 1

),


/* ================================================================
   2. PREVIOUS SNAPSHOT
   ================================================================ */

product_snapshot_sequence AS (

    SELECT

        product_id,
        inventory_date,
        stock_quantity,
        reorder_level,
        cost_price,
        supplier_id,

        LAG(inventory_date) OVER (
            PARTITION BY product_id
            ORDER BY inventory_date
        ) AS previous_snapshot_date,

        LAG(stock_quantity) OVER (
            PARTITION BY product_id
            ORDER BY inventory_date
        ) AS beginning_stock

    FROM product_snapshots

),


/* ================================================================
   3. SNAPSHOT GAP DETECTION
   ================================================================ */

snapshot_quality AS (

    SELECT

        *,

        CASE
            WHEN previous_snapshot_date IS NULL
                THEN NULL

            ELSE DATEDIFF(
                DAY,
                previous_snapshot_date,
                inventory_date
            )
        END AS snapshot_gap_days,

        CASE
            WHEN previous_snapshot_date IS NOT NULL
             AND DATEDIFF(
                    DAY,
                    previous_snapshot_date,
                    inventory_date
                 ) > 1
                THEN TRUE

            ELSE FALSE
        END AS snapshot_gap_flag

    FROM product_snapshot_sequence

),


/* ================================================================
   4. COMPLETED ORDER SALES
   ================================================================ */

completed_order_items AS (

    SELECT

        oi.order_id,
        oi.product_id,
        oi.quantity,
        CAST(o.order_date AS DATE) AS order_date

    FROM {{ ref('silver_order_items') }} AS oi

    INNER JOIN {{ ref('silver_orders') }} AS o
        ON oi.order_id = o.order_id

    WHERE UPPER(TRIM(o.order_status)) = 'COMPLETED'
      AND oi.product_id IS NOT NULL
      AND oi.quantity IS NOT NULL
      AND oi.quantity >= 0
      AND o.order_date IS NOT NULL

),


/* ================================================================
   5. DAILY SOLD QUANTITY
   ================================================================ */

daily_sales AS (

    SELECT

        product_id,
        order_date AS inventory_date,

        SUM(quantity)::NUMBER(18,0)
            AS sold_quantity

    FROM completed_order_items

    GROUP BY
        product_id,
        order_date

),


/* ================================================================
   6. OPERATIONAL HORIZON
   ================================================================

   Instead of hard-coding 2024-09-27, derive the operational
   horizon from the latest available order date.

   This makes the model continue working when new data arrives.
*/

operational_horizon AS (

    SELECT

        MAX(CAST(order_date AS DATE))
            AS analysis_end_date

    FROM {{ ref('silver_orders') }}

),


/* ================================================================
   7. JOIN INVENTORY SNAPSHOTS WITH SALES
   ================================================================ */

inventory_base AS (

    SELECT

        p.product_id,
        p.inventory_date,

        p.beginning_stock,

        COALESCE(
            s.sold_quantity,
            0
        )::NUMBER(18,0) AS sold_quantity,

        p.stock_quantity AS ending_stock,

        p.reorder_level,
        p.cost_price,
        p.supplier_id,

        p.previous_snapshot_date,
        p.snapshot_gap_days,
        p.snapshot_gap_flag,

        h.analysis_end_date

    FROM snapshot_quality AS p

    CROSS JOIN operational_horizon AS h

    LEFT JOIN daily_sales AS s

        ON p.product_id = s.product_id

       AND p.inventory_date = s.inventory_date

),


/* ================================================================
   8. DERIVED INVENTORY METRICS
   ================================================================ */

derived_metrics AS (

    SELECT

        *,

        /*
            Inferred purchase quantity.

            ending = beginning + purchased - sold

            Therefore:

            purchased =
                ending - beginning + sold
        */

        CASE

            WHEN beginning_stock IS NOT NULL
             AND ending_stock IS NOT NULL

            THEN (
                ending_stock
                - beginning_stock
                + sold_quantity
            )::NUMBER(18,0)

            ELSE NULL

        END AS purchased_quantity,


        /*
            Average inventory.
        */

        CASE

            WHEN beginning_stock IS NOT NULL
             AND ending_stock IS NOT NULL

            THEN (
                beginning_stock
                + ending_stock
            ) / 2.0

            ELSE NULL

        END AS average_inventory,


        /*
            Inventory value uses cost price, not selling price.
        */

        CASE

            WHEN ending_stock IS NOT NULL
             AND cost_price IS NOT NULL

            THEN ROUND(
                ending_stock * cost_price,
                2
            )::NUMBER(18,2)

            ELSE NULL

        END AS inventory_value,


        /*
            Only the latest observed snapshot can be stale.

            Example:
                latest product snapshot = 2024-09-15
                operational horizon      = 2024-09-27
                stale days               = 12
        */

        CASE

            WHEN inventory_date = MAX(inventory_date)
                 OVER (
                     PARTITION BY product_id
                 )

             AND analysis_end_date IS NOT NULL

             AND analysis_end_date > inventory_date

            THEN TRUE

            ELSE FALSE

        END AS stale_product_snapshot_flag,


        CASE

            WHEN inventory_date = MAX(inventory_date)
                 OVER (
                     PARTITION BY product_id
                 )

             AND analysis_end_date IS NOT NULL

             AND analysis_end_date > inventory_date

            THEN DATEDIFF(
                DAY,
                inventory_date,
                analysis_end_date
            )

            ELSE 0

        END AS stale_days,


        /*
            Low stock.
        */

        CASE

            WHEN ending_stock IS NULL
              OR reorder_level IS NULL

                THEN NULL

            WHEN ending_stock < reorder_level

                THEN TRUE

            ELSE FALSE

        END AS low_stock_flag

    FROM inventory_base

),


/* ================================================================
   9. VALIDATION FLAGS
   ================================================================ */

validated AS (

    SELECT

        *,

        /*
            Negative observed stock.
        */

        CASE

            WHEN COALESCE(beginning_stock, 0) < 0
              OR COALESCE(ending_stock, 0) < 0

                THEN TRUE

            ELSE FALSE

        END AS negative_stock_flag,


        /*
            Negative inferred purchasing.
        */

        CASE

            WHEN purchased_quantity < 0

                THEN TRUE

            ELSE FALSE

        END AS negative_inferred_purchase_flag,


        /*
            Stock turnover ratio:

                sold quantity
                ----------------
                average inventory
        */

        CASE

            WHEN average_inventory > 0

            THEN ROUND(
                sold_quantity / average_inventory,
                4
            )

            ELSE NULL

        END AS stock_turnover_ratio,


        /*
            Since receiving events are not observed,
            the inferred purchase quantity can only be
            attributed to the supplier associated with
            that product snapshot.

            Therefore the contribution is 100% when
            positive inferred purchasing exists.
        */

        CASE

            WHEN purchased_quantity > 0
             AND supplier_id IS NOT NULL

            THEN 100.00

            ELSE NULL

        END AS supplier_contribution_percentage

    FROM derived_metrics

)


/* ================================================================
   10. FINAL SILVER INVENTORY TABLE
   ================================================================ */

SELECT

    /*
        Surrogate inventory key.

        Grain:
            product_id + inventory_date
    */

    MD5(
        CONCAT(
            COALESCE(product_id, ''),
            '|',
            COALESCE(inventory_date::VARCHAR, '')
        )
    )::VARCHAR AS inventory_key,

    product_id,
    inventory_date,

    supplier_id,

    beginning_stock,
    purchased_quantity,
    sold_quantity,
    ending_stock,

    cost_price,
    inventory_value,

    average_inventory,
    stock_turnover_ratio,
    supplier_contribution_percentage,

    reorder_level,
    low_stock_flag,

    negative_stock_flag,
    negative_inferred_purchase_flag,

    previous_snapshot_date,
    snapshot_gap_days,
    snapshot_gap_flag,

    analysis_end_date,
    stale_product_snapshot_flag,
    stale_days

FROM validated