-- =================================================
-- analysis.sql | Cornwall Housing Affordability Project
-- Purpose      : Answer the five research questions
-- Tool         : MySQL 8.0
-- Author       : Ed
-- =================================================
-- WHY MEDIAN NOT MEAN:
-- Property prices are right-skewed. A handful of
-- multi-million pound coastal properties would drag
-- the mean up significantly. Median represents the
-- typical buyer's experience.
-- =================================================

USE cornwall_housing;

-- =================================================
-- Q1: HOW HAS MEDIAN PRICE CHANGED OVER TIME?
-- =================================================

WITH annual_medians AS (
    SELECT 
        year,
        MAX(total) AS transactions,
        AVG(price) AS median_price
    FROM (
        SELECT year, price,
               ROW_NUMBER() OVER (PARTITION BY year ORDER BY price) AS rn,
               COUNT(*) OVER (PARTITION BY year) AS total
        FROM ppd_clean
        WHERE property_type != 'Other'
    ) ranked
    WHERE rn IN (FLOOR((total+1)/2), CEIL((total+1)/2))
    GROUP BY year
)
SELECT
    year,
    transactions,
    ROUND(median_price, 0) AS median_price,
    ROUND(LAG(median_price) OVER (ORDER BY year), 0) AS prev_year_median,
    ROUND(100.0 * (median_price - LAG(median_price) OVER (ORDER BY year)) 
          / LAG(median_price) OVER (ORDER BY year), 1) AS yoy_growth_pct
FROM annual_medians
ORDER BY year;
-- Finding: prices rose 481% from 1995 to 2026
-- Biggest single year growth: 2002 at +35.2%
-- Biggest drop: 2009 at -7.9% (financial crisis)
-- Pandemic surge: 2021 at +10.0%

-- =================================================
-- Q2: HOW HAVE PRICES CHANGED BY AREA?
-- =================================================

SELECT 
    year,
    area,
    MAX(total) AS transactions,
    ROUND(AVG(price), 0) AS median_price
FROM (
    SELECT year, area, price,
           ROW_NUMBER() OVER (PARTITION BY year, area ORDER BY price) AS rn,
           COUNT(*) OVER (PARTITION BY year, area) AS total
    FROM ppd_clean
    WHERE property_type != 'Other'
) ranked
WHERE rn IN (FLOOR((total+1)/2), CEIL((total+1)/2))
GROUP BY year, area
ORDER BY area, year;
-- Finding: Falmouth highest median in 2026 at £350,000
-- Redruth/Camborne most affordable at £250,000
-- Falmouth grew most since 1995 at +567%
-- Redruth/Camborne surprising second at +541%
-- Hypothesis partially confirmed: coastal towns led
-- but inland areas grew faster than expected

-- =================================================
-- Q3: WHAT PREMIUM DO NEW BUILDS CARRY?
-- =================================================

WITH nb_medians AS (
    SELECT 
        year,
        new_build,
        MAX(total) AS transactions,
        ROUND(AVG(price), 0) AS median_price
    FROM (
        SELECT year, new_build, price,
               ROW_NUMBER() OVER (PARTITION BY year, new_build ORDER BY price) AS rn,
               COUNT(*) OVER (PARTITION BY year, new_build) AS total
        FROM ppd_clean
        WHERE property_type != 'Other'
    ) ranked
    WHERE rn IN (FLOOR((total+1)/2), CEIL((total+1)/2))
    GROUP BY year, new_build
)
SELECT
    n.year,
    n.median_price                                          AS new_build_median,
    e.median_price                                          AS existing_median,
    n.transactions                                          AS new_build_sales,
    e.transactions                                          AS existing_sales,
    ROUND(100.0 * (n.median_price - e.median_price) 
          / e.median_price, 1)                              AS premium_pct
FROM nb_medians n
JOIN nb_medians e ON n.year = e.year AND e.new_build = 'Existing'
WHERE n.new_build = 'New build'
ORDER BY n.year;
-- Finding: premium is NOT consistent over 30 years
-- 1995-2001: small positive premium 7-24%
-- 2002-2015: new builds CHEAPER than existing
-- lowest point 2010: -12.8% (post-crash discounting)
-- 2016-2026: premium returns, reaching 22.8% in 2023
-- Hypothesis confirmed for recent period only

-- =================================================
-- Q4: ARE THERE SEASONAL PATTERNS IN TRANSACTIONS?
-- =================================================

SELECT 
    month,
    CASE month
        WHEN 1  THEN 'January'
        WHEN 2  THEN 'February'
        WHEN 3  THEN 'March'
        WHEN 4  THEN 'April'
        WHEN 5  THEN 'May'
        WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'
        WHEN 8  THEN 'August'
        WHEN 9  THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END AS month_name,
    COUNT(*) AS total_transactions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all
FROM ppd_clean
GROUP BY month
ORDER BY month;
-- Finding: Cornwall market is surprisingly flat seasonally
-- No dramatic summer peak as hypothesised
-- Only clear pattern: January dip at 6.6%
-- February also quiet at 7.2%
-- March-December broadly even at 7.4-9.0%
-- Hypothesis NOT confirmed
-- Likely explanation: Land Registry records completion
-- date not offer date -- summer decisions complete
-- in autumn, smoothing seasonal peaks
