-- Revenue & Sales Dashboard - Data Extraction Queries
-- Description: SQL queries for extracting sales data from multiple sources
-- Author: Your Name
-- Created: 2025

-- =============================================
-- Main Sales Data Extraction Query
-- =============================================

SELECT 
    s.transaction_id,
    s.transaction_date,
    s.product_id,
    p.product_name,
    p.category_name,
    s.customer_id,
    c.customer_name,
    c.region_name,
    s.quantity_sold,
    s.unit_price,
    s.total_amount,
    s.sales_rep_id,
    sr.rep_name,
    (s.quantity_sold * s.unit_price) as revenue,
    (s.total_amount - (s.quantity_sold * p.cost_price)) as profit_margin,
    YEAR(s.transaction_date) as sales_year,
    MONTH(s.transaction_date) as sales_month,
    QUARTER(s.transaction_date) as sales_quarter,
    DAYOFWEEK(s.transaction_date) as day_of_week,
    WEEK(s.transaction_date) as week_of_year
FROM 
    sales_transactions s
    INNER JOIN products p ON s.product_id = p.product_id
    INNER JOIN customers c ON s.customer_id = c.customer_id
    LEFT JOIN sales_reps sr ON s.sales_rep_id = sr.rep_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
    AND s.total_amount > 0
    AND s.quantity_sold > 0
ORDER BY 
    s.transaction_date DESC;

-- =============================================
-- Monthly Revenue Aggregation
-- =============================================

SELECT 
    YEAR(transaction_date) as year,
    MONTH(transaction_date) as month,
    MONTHNAME(transaction_date) as month_name,
    region_name,
    COUNT(transaction_id) as transaction_count,
    SUM(quantity_sold) as total_units_sold,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value,
    SUM(total_amount - (quantity_sold * cost_price)) as total_profit
FROM 
    sales_transactions s
    INNER JOIN products p ON s.product_id = p.product_id
    INNER JOIN customers c ON s.customer_id = c.customer_id
WHERE 
    transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
GROUP BY 
    YEAR(transaction_date),
    MONTH(transaction_date),
    region_name
ORDER BY 
    year DESC, month DESC, total_revenue DESC;

-- =============================================
-- Product Performance Analysis
-- =============================================

SELECT 
    p.category_name,
    p.product_name,
    p.brand,
    COUNT(s.transaction_id) as total_transactions,
    SUM(s.quantity_sold) as total_units_sold,
    SUM(s.total_amount) as total_revenue,
    AVG(s.total_amount) as avg_sale_amount,
    SUM(s.total_amount - (s.quantity_sold * p.cost_price)) as total_profit,
    (SUM(s.total_amount - (s.quantity_sold * p.cost_price)) / SUM(s.total_amount)) * 100 as profit_margin_percent,
    RANK() OVER (ORDER BY SUM(s.total_amount) DESC) as revenue_rank
FROM 
    sales_transactions s
    INNER JOIN products p ON s.product_id = p.product_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
GROUP BY 
    p.category_name, p.product_name, p.brand
HAVING 
    total_revenue > 1000
ORDER BY 
    total_revenue DESC;

-- =============================================
-- Customer Segmentation Query
-- =============================================

SELECT 
    c.customer_id,
    c.customer_name,
    c.region_name,
    c.customer_type,
    COUNT(s.transaction_id) as transaction_frequency,
    SUM(s.total_amount) as total_lifetime_value,
    AVG(s.total_amount) as avg_order_value,
    MIN(s.transaction_date) as first_purchase_date,
    MAX(s.transaction_date) as last_purchase_date,
    DATEDIFF(MAX(s.transaction_date), MIN(s.transaction_date)) as customer_lifetime_days,
    CASE 
        WHEN SUM(s.total_amount) >= 10000 AND COUNT(s.transaction_id) >= 10 THEN 'VIP'
        WHEN SUM(s.total_amount) >= 5000 OR COUNT(s.transaction_id) >= 5 THEN 'High Value'
        WHEN SUM(s.total_amount) >= 1000 THEN 'Regular'
        ELSE 'Low Value'
    END as customer_segment
FROM 
    customers c
    INNER JOIN sales_transactions s ON c.customer_id = s.customer_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
GROUP BY 
    c.customer_id, c.customer_name, c.region_name, c.customer_type
ORDER BY 
    total_lifetime_value DESC;

-- =============================================
-- Regional Performance Comparison
-- =============================================

SELECT 
    r.region_name,
    COUNT(DISTINCT c.customer_id) as total_customers,
    COUNT(s.transaction_id) as total_transactions,
    SUM(s.total_amount) as total_revenue,
    AVG(s.total_amount) as avg_transaction_value,
    SUM(s.quantity_sold) as total_units_sold,
    (SUM(s.total_amount) / (SELECT SUM(total_amount) FROM sales_transactions WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR))) * 100 as revenue_contribution_percent
FROM 
    regions r
    INNER JOIN customers c ON r.region_id = c.region_id
    INNER JOIN sales_transactions s ON c.customer_id = s.customer_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
GROUP BY 
    r.region_name
ORDER BY 
    total_revenue DESC;

-- =============================================
-- Seasonal Trends Analysis
-- =============================================

SELECT 
    sales_year,
    sales_quarter,
    CASE sales_quarter
        WHEN 1 THEN 'Q1 (Jan-Mar)'
        WHEN 2 THEN 'Q2 (Apr-Jun)'
        WHEN 3 THEN 'Q3 (Jul-Sep)'
        WHEN 4 THEN 'Q4 (Oct-Dec)'
    END as quarter_label,
    COUNT(transaction_id) as total_transactions,
    SUM(total_amount) as quarterly_revenue,
    AVG(total_amount) as avg_transaction_value,
    (SUM(total_amount) - LAG(SUM(total_amount)) OVER (ORDER BY sales_year, sales_quarter)) / LAG(SUM(total_amount)) OVER (ORDER BY sales_year, sales_quarter) * 100 as quarter_over_quarter_growth
FROM (
    SELECT 
        YEAR(transaction_date) as sales_year,
        QUARTER(transaction_date) as sales_quarter,
        transaction_id,
        total_amount
    FROM sales_transactions
    WHERE transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
) as seasonal_data
GROUP BY 
    sales_year, sales_quarter
ORDER BY 
    sales_year DESC, sales_quarter DESC;

-- =============================================
-- Sales Representatives Performance
-- =============================================

SELECT 
    sr.rep_name,
    sr.region_name,
    COUNT(s.transaction_id) as total_sales,
    SUM(s.total_amount) as total_revenue,
    AVG(s.total_amount) as avg_sale_amount,
    COUNT(DISTINCT s.customer_id) as unique_customers,
    SUM(s.total_amount) / COUNT(DISTINCT s.customer_id) as revenue_per_customer,
    RANK() OVER (PARTITION BY sr.region_name ORDER BY SUM(s.total_amount) DESC) as region_rank,
    RANK() OVER (ORDER BY SUM(s.total_amount) DESC) as overall_rank
FROM 
    sales_reps sr
    INNER JOIN sales_transactions s ON sr.rep_id = s.sales_rep_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
GROUP BY 
    sr.rep_name, sr.region_name
ORDER BY 
    total_revenue DESC;

-- =============================================
-- Data Quality Check Queries
-- =============================================

-- Check for missing values
SELECT 
    'Missing Product IDs' as issue,
    COUNT(*) as count
FROM sales_transactions 
WHERE product_id IS NULL
    AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)

UNION ALL

SELECT 
    'Missing Customer IDs' as issue,
    COUNT(*) as count
FROM sales_transactions 
WHERE customer_id IS NULL
    AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)

UNION ALL

SELECT 
    'Zero Amount Transactions' as issue,
    COUNT(*) as count
FROM sales_transactions 
WHERE total_amount <= 0
    AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR)

UNION ALL

SELECT 
    'Negative Quantity Sold' as issue,
    COUNT(*) as count
FROM sales_transactions 
WHERE quantity_sold < 0
    AND transaction_date >= DATE_SUB(CURDATE(), INTERVAL 1 YEAR);

-- =============================================
-- Views Creation for Dashboard
-- =============================================

-- Create view for dashboard consumption
CREATE OR REPLACE VIEW vw_dashboard_sales_summary AS
SELECT 
    DATE(transaction_date) as sale_date,
    YEAR(transaction_date) as year,
    MONTH(transaction_date) as month,
    QUARTER(transaction_date) as quarter,
    p.category_name,
    c.region_name,
    COUNT(s.transaction_id) as transaction_count,
    SUM(s.total_amount) as daily_revenue,
    SUM(s.quantity_sold) as units_sold,
    AVG(s.total_amount) as avg_order_value
FROM 
    sales_transactions s
    INNER JOIN products p ON s.product_id = p.product_id
    INNER JOIN customers c ON s.customer_id = c.customer_id
WHERE 
    s.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 2 YEAR)
GROUP BY 
    DATE(transaction_date),
    YEAR(transaction_date),
    MONTH(transaction_date),
    QUARTER(transaction_date),
    p.category_name,
    c.region_name;