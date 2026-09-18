-- ==========================================
-- UrbanCart E-Commerce Analytics — SQL Portfolio
-- ==========================================

-- ==========================================
-- SECTION 1: DATABASE SCHEMA
-- ==========================================

CREATE DATABASE urbancart_db;
USE urbancart_db;

CREATE TABLE Customers (
    customer_id INT PRIMARY KEY,
    customer_name VARCHAR(50) NOT NULL,
    email VARCHAR(50) UNIQUE,
    city VARCHAR(50),
    signup_date DATE,
    customer_segment VARCHAR(20)
);

CREATE TABLE Orders (
    order_id INT PRIMARY KEY,
    customer_id INT,
    order_date DATE,
    order_status VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES Customers(customer_id)
);

CREATE TABLE Products (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(30),
    category VARCHAR(30),
    cost_price DECIMAL(10,2)
);

CREATE TABLE Order_Items (
    order_item_id INT PRIMARY KEY,
    order_id INT,
    product_id INT,
    quantity INT,
    unit_price DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES Orders(order_id),
    FOREIGN KEY (product_id) REFERENCES Products(product_id)
);

CREATE TABLE Deliveries (
    delivery_id INT PRIMARY KEY,
    order_id INT,
    expected_date DATE,
    actual_date DATE,
    delivery_status VARCHAR(20),
    FOREIGN KEY (order_id) REFERENCES Orders(order_id)
);

-- Load data (paths are environment-specific — replace with your own CSV locations)
SET GLOBAL local_infile = 1;

LOAD DATA INFILE '/path/to/customers.csv' INTO TABLE Customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA INFILE '/path/to/products.csv' INTO TABLE Products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA INFILE '/path/to/orders.csv' INTO TABLE Orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA INFILE '/path/to/order_items.csv' INTO TABLE Order_Items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

LOAD DATA INFILE '/path/to/deliveries.csv' INTO TABLE Deliveries
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

-- Verify row counts match source files
SELECT
 (SELECT COUNT(*) FROM Customers) AS customers,
 (SELECT COUNT(*) FROM Products) AS products,
 (SELECT COUNT(*) FROM Orders) AS orders,
 (SELECT COUNT(*) FROM Order_Items) AS order_items,
 (SELECT COUNT(*) FROM Deliveries) AS deliveries;


-- ==========================================
-- SECTION 2: DATA CLEANING — DETECTION & FIXES
-- ==========================================

-- Missing email check
SELECT COUNT(*) FROM customers WHERE email IS NULL;

-- Duplicate customers by name + email
SELECT customer_name, email, COUNT(*) AS duplicate_count
FROM customers
WHERE email IS NOT NULL
GROUP BY customer_name, email
HAVING COUNT(*) > 1;

-- Inspect inconsistent categorical values
SELECT DISTINCT city FROM customers;
SELECT DISTINCT category FROM products;

-- Inspect price outliers
SELECT * FROM order_items ORDER BY unit_price DESC LIMIT 10;

-- Standardize city naming
UPDATE customers
SET city = CASE
    WHEN city IN ('hyderabad','HYDERABAD','Hyd') THEN 'Hyderabad'
    WHEN city IN ('mumbai','Bombay') THEN 'Mumbai'
    WHEN city IN ('bangalore','Bengaluru') THEN 'Bangalore'
    WHEN city IN ('delhi','New Delhi') THEN 'Delhi'
    WHEN city IN ('chennai','Madras') THEN 'Chennai'
    WHEN city = 'pune' THEN 'Pune'
    WHEN city IN ('kolkata','Calcutta') THEN 'Kolkata'
    WHEN city = 'ahmedabad' THEN 'Ahmedabad'
    ELSE city
END
WHERE city IS NOT NULL;

-- Standardize category naming
UPDATE products
SET category = CASE
    WHEN category = 'fashion' THEN 'Fashion'
    WHEN category = 'Home and Kitchen' THEN 'Home & Kitchen'
    ELSE category
END
WHERE category IS NOT NULL;

-- Verify standardization
SELECT DISTINCT city FROM customers;
SELECT DISTINCT category FROM products;

-- Duplicate customer resolution: check order history split across duplicate IDs
-- (duplicate customers were injected with customer_id > 13000)
SELECT c.customer_id, c.customer_name, c.email, COUNT(o.order_id) AS order_count
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.customer_id > 13000
GROUP BY c.customer_id, c.customer_name, c.email
ORDER BY order_count DESC;

-- Match each duplicate back to its original record
SELECT
    orig.customer_id AS original_id,
    dup.customer_id AS duplicate_id,
    dup.customer_name,
    dup.email,
    (SELECT COUNT(*) FROM orders WHERE customer_id = orig.customer_id) AS original_orders,
    (SELECT COUNT(*) FROM orders WHERE customer_id = dup.customer_id) AS duplicate_orders
FROM customers dup
JOIN customers orig
    ON dup.customer_name = orig.customer_name
    AND dup.email <=> orig.email   -- NULL-safe equality, since some duplicates have missing email
    AND orig.customer_id < 13000
WHERE dup.customer_id > 13000;

-- Reassign duplicate customers' orders to their original ID before deleting the duplicate record
-- (prevents silently losing real transaction history)
UPDATE orders o
JOIN customers dup ON o.customer_id = dup.customer_id
JOIN customers orig ON dup.customer_name = orig.customer_name
    AND dup.email <=> orig.email
    AND orig.customer_id < 13000
SET o.customer_id = orig.customer_id
WHERE dup.customer_id > 13000;

-- Verify no orders still reference a duplicate ID
SELECT COUNT(*) FROM orders WHERE customer_id > 13000;

-- Remove the now-redundant duplicate customer records
DELETE FROM customers WHERE customer_id > 13000;

-- Final verification
SELECT COUNT(*) FROM customers;
SELECT customer_name, email, COUNT(*)
FROM customers
WHERE email IS NOT NULL
GROUP BY customer_name, email
HAVING COUNT(*) > 1;


-- ==========================================
-- SECTION 3: BUSINESS ANALYSIS (25 QUERIES)
-- ==========================================

-- A. Foundational (SELECT, WHERE, CASE, ORDER BY)

-- 1. Total revenue and total orders
SELECT SUM(oi.quantity * oi.unit_price) AS total_revenue, COUNT(DISTINCT o.order_id) AS total_orders
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id;

-- 2. Orders by status
SELECT order_status, COUNT(*) AS total_orders
FROM orders
GROUP BY order_status;

-- 3. Customers by segment, with a CASE-based value tier
SELECT customer_id, customer_name, customer_segment,
    CASE
        WHEN customer_segment = 'Premium' THEN 'High Priority'
        WHEN customer_segment = 'Regular' THEN 'Standard'
        ELSE 'New/Unclassified'
    END AS priority_tier
FROM customers;

-- 4. Top 10 most expensive products
SELECT product_name, category, cost_price
FROM products
ORDER BY cost_price DESC
LIMIT 10;

-- 5. Orders placed in a specific date range
SELECT order_id, customer_id, order_date
FROM orders
WHERE order_date BETWEEN '2024-06-01' AND '2024-08-31'
ORDER BY order_date;

-- B. Aggregations, GROUP BY, HAVING

-- 6. Revenue by category
SELECT p.category, SUM(oi.quantity * oi.unit_price) AS category_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY category_revenue DESC;

-- 7. Revenue by city
SELECT c.city, SUM(oi.quantity * oi.unit_price) AS city_revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.city
ORDER BY city_revenue DESC;

-- 8. Customers with more than 5 orders (HAVING on aggregate)
SELECT customer_id, COUNT(*) AS order_count
FROM orders
GROUP BY customer_id
HAVING COUNT(*) > 5
ORDER BY order_count DESC;

-- 9. Average order value by month
SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
    SUM(oi.quantity * oi.unit_price) / COUNT(DISTINCT o.order_id) AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY order_month
ORDER BY order_month;

-- 10. Products that generated zero revenue in the last 3 months
SELECT p.product_id, p.product_name
FROM products p
WHERE p.product_id NOT IN (
    SELECT DISTINCT oi.product_id
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_date >= '2024-07-01'
);

-- C. Joins (INNER, LEFT, SELF)

-- 11. Orders with delivery status (LEFT JOIN, since some orders may lack delivery records)
SELECT o.order_id, o.order_status, d.delivery_status, d.expected_date, d.actual_date
FROM orders o
LEFT JOIN deliveries d ON o.order_id = d.order_id;

-- 12. Full order detail: customer + product + category in one row (multi-table INNER JOIN)
SELECT o.order_id, c.customer_name, p.product_name, p.category, oi.quantity, oi.unit_price
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
LIMIT 100;

-- 13. Customers who share the same city (SELF JOIN)
SELECT a.customer_name AS customer_1, b.customer_name AS customer_2, a.city
FROM customers a
JOIN customers b ON a.city = b.city AND a.customer_id < b.customer_id
LIMIT 50;

-- 14. Orders where delivery was delayed
SELECT o.order_id, c.customer_name, d.expected_date, d.actual_date
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN deliveries d ON o.order_id = d.order_id
WHERE d.delivery_status = 'Delayed';

-- D. Subqueries

-- 15. Customers whose total spend is above the average customer spend
SELECT customer_id, total_spend FROM (
    SELECT o.customer_id, SUM(oi.quantity * oi.unit_price) AS total_spend
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY o.customer_id
) AS customer_totals
WHERE total_spend > (
    SELECT AVG(total_spend) FROM (
        SELECT o.customer_id, SUM(oi.quantity * oi.unit_price) AS total_spend
        FROM orders o
        JOIN order_items oi ON o.order_id = oi.order_id
        GROUP BY o.customer_id
    ) AS sub
);

-- 16. Products priced above their category's average
SELECT product_name, category, cost_price
FROM products p1
WHERE cost_price > (
    SELECT AVG(cost_price) FROM products p2 WHERE p2.category = p1.category
);

-- E. CTEs

-- 17. Monthly revenue using a CTE
WITH monthly_rev AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY order_month
)
SELECT * FROM monthly_rev ORDER BY order_month;

-- 18. Top 5 customers per city using a CTE + window function
WITH customer_spend AS (
    SELECT c.city, c.customer_id, c.customer_name,
        SUM(oi.quantity * oi.unit_price) AS total_spend,
        RANK() OVER (PARTITION BY c.city ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS city_rank
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY c.city, c.customer_id, c.customer_name
)
SELECT * FROM customer_spend WHERE city_rank <= 5;

-- F. Window Functions (RANK, LAG/LEAD, running totals)

-- 19. Rank products by revenue within their category
SELECT category, product_name, product_revenue,
    RANK() OVER (PARTITION BY category ORDER BY product_revenue DESC) AS rank_in_category
FROM (
    SELECT p.category, p.product_name, SUM(oi.quantity * oi.unit_price) AS product_revenue
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY p.category, p.product_name
) AS product_totals;

-- 20. Month-over-month revenue change using LAG
WITH monthly_rev AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY order_month
)
SELECT order_month, revenue,
    LAG(revenue) OVER (ORDER BY order_month) AS prev_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY order_month) AS mom_change
FROM monthly_rev;

-- 21. Running total of revenue over time
WITH monthly_rev AS (
    SELECT DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY order_month
)
SELECT order_month, revenue,
    SUM(revenue) OVER (ORDER BY order_month) AS running_total
FROM monthly_rev;

-- 22. Days between a customer's consecutive orders (LEAD)
SELECT customer_id, order_id, order_date,
    LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date,
    DATEDIFF(LEAD(order_date) OVER (PARTITION BY customer_id ORDER BY order_date), order_date) AS days_to_next_order
FROM orders
ORDER BY customer_id, order_date;

-- G. Customer & Business Analysis

-- 23. Repeat purchase rate (cross-validated against Python: 84.41%)
SELECT
    COUNT(DISTINCT CASE WHEN order_count > 1 THEN customer_id END) AS repeat_customers,
    COUNT(DISTINCT customer_id) AS total_customers,
    ROUND(COUNT(DISTINCT CASE WHEN order_count > 1 THEN customer_id END) / COUNT(DISTINCT customer_id) * 100, 2) AS repeat_rate_pct
FROM (
    SELECT customer_id, COUNT(*) AS order_count
    FROM orders
    GROUP BY customer_id
) AS t;

-- 24. Top 10% customer revenue contribution (cross-validated against Python: 32.65%)
WITH customer_totals AS (
    SELECT o.customer_id, SUM(oi.quantity * oi.unit_price) AS total_spend
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY o.customer_id
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY total_spend DESC) AS decile
    FROM customer_totals
)
SELECT
    SUM(CASE WHEN decile = 1 THEN total_spend ELSE 0 END) AS top10pct_revenue,
    SUM(total_spend) AS total_revenue,
    ROUND(SUM(CASE WHEN decile = 1 THEN total_spend ELSE 0 END) / SUM(total_spend) * 100, 2) AS pct_from_top10
FROM ranked;

-- 25. Year-over-year comparison (limited by ~16-month dataset range)
SELECT
    MONTH(o.order_date) AS order_month_num,
    YEAR(o.order_date) AS order_year,
    SUM(oi.quantity * oi.unit_price) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY order_year, order_month_num
ORDER BY order_month_num, order_year;
