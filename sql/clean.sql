-- =================================================
-- clean.sql | Cornwall Housing Affordability Project
-- Purpose   : Clean and shape raw PPD data
-- Tool      : MySQL 8.0
-- Author    : Edgar M
-- =================================================

USE cornwall_housing;

-- =================================================
-- STEP 1: DATA QUALITY CHECKS
-- Run these first to understand the raw data
-- =================================================

-- Row count.
SELECT COUNT(*) AS total_rows FROM ppd_raw;

-- Check for missing values in key columns
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN postcode IS NULL OR postcode = '' THEN 1 ELSE 0 END) AS null_postcode,
    SUM(CASE WHEN town_city IS NULL OR town_city = '' THEN 1 ELSE 0 END) AS null_town,
    SUM(CASE WHEN street IS NULL OR street = '' THEN 1 ELSE 0 END) AS null_street
FROM ppd_raw;

-- Transaction categories
-- Decision: exclude Category B (repossessions, right-to-buy,
-- company transfers) as these are not open-market prices
SELECT ppd_category_type, COUNT(*) AS count FROM ppd_raw 
GROUP BY ppd_category_type;

-- Property type distribution
SELECT property_type, COUNT(*) AS count FROM ppd_raw 
GROUP BY property_type ORDER BY count DESC;

-- =================================================
-- STEP 2: CREATE CLEAN TABLE
-- Decisions documented inline
-- =================================================

-- Drop table if rebuilding
DROP TABLE IF EXISTS ppd_clean;

CREATE TABLE ppd_clean AS
SELECT
    transaction_id,

    -- Price cast to number
    CAST(price AS UNSIGNED) AS price,

    -- Extract year and month from date string
    date_of_transfer,
    CAST(SUBSTRING(date_of_transfer,1,4) AS UNSIGNED) AS year,
    CAST(SUBSTRING(date_of_transfer,6,2) AS UNSIGNED) AS month,

    -- Postcode: keep but flag missing rows
    -- Decision: retain missing postcodes for price analysis
    -- but exclude from map visuals
    postcode,
    CASE WHEN postcode IS NULL OR postcode = '' 
         THEN 1 ELSE 0 END AS postcode_missing,

    -- Decode property type codes to readable labels
    property_type AS property_type_code,
    CASE property_type
        WHEN 'D' THEN 'Detached'
        WHEN 'S' THEN 'Semi-detached'
        WHEN 'T' THEN 'Terraced'
        WHEN 'F' THEN 'Flat'
        WHEN 'O' THEN 'Other'
    END AS property_type,

    -- Decode new build flag
    old_new AS new_build_code,
    CASE old_new 
        WHEN 'Y' THEN 'New build' 
        ELSE 'Existing' 
    END AS new_build,

    -- Decode tenure
    duration AS tenure_code,
    CASE duration
        WHEN 'F' THEN 'Freehold'
        WHEN 'L' THEN 'Leasehold'
        ELSE 'Unknown'
    END AS tenure,

    -- Town and area grouping
    -- Decision: group towns into four analytical areas
    -- reflecting distinct housing markets in Cornwall
    town_city,
    CASE
        WHEN UPPER(TRIM(town_city)) IN 
            ('REDRUTH','CAMBORNE','POOL','ILLOGAN','PORTREATH') 
            THEN 'Redruth / Camborne'
        WHEN UPPER(TRIM(town_city)) IN 
            ('TRURO','THREEMILESTONE','KENWYN','CHACEWATER') 
            THEN 'Truro'
        WHEN UPPER(TRIM(town_city)) IN 
            ('FALMOUTH','PENRYN','MYLOR','FLUSHING') 
            THEN 'Falmouth'
        WHEN UPPER(TRIM(town_city)) IN 
            ('PENZANCE','NEWLYN','MOUSEHOLE','MARAZION') 
            THEN 'Penzance'
        ELSE 'Other Cornwall'
    END AS area,

    district,
    county

FROM ppd_raw
WHERE ppd_category_type = 'A'        -- standard transactions only
AND record_status IN ('A','C')        -- exclude deleted records
AND CAST(price AS UNSIGNED) >= 1000   -- exclude nominal transfers
AND CAST(price AS UNSIGNED) <= 50000000; -- exclude data errors

-- =================================================
-- STEP 3: VALIDATE CLEAN TABLE
-- Confirm cleaning worked correctly
-- =================================================

-- Row count after cleaning
-- Expect fewer rows than raw due to Category B exclusions
SELECT COUNT(*) AS clean_rows FROM ppd_clean;

-- Confirm date range
SELECT 
    MIN(date_of_transfer) AS earliest_sale,
    MAX(date_of_transfer) AS latest_sale,
    COUNT(DISTINCT year) AS years_covered
FROM ppd_clean;

-- Transactions per year
-- Look for recognisable patterns: 2008 crash, 2021 surge
SELECT year, COUNT(*) AS transactions
FROM ppd_clean
GROUP BY year
ORDER BY year;

-- Area distribution
SELECT area, COUNT(*) AS transactions
FROM ppd_clean
GROUP BY area
ORDER BY transactions DESC;

-- Property type distribution after decoding
SELECT property_type, COUNT(*) AS transactions,
       ROUND(100.0 * COUNT(*) / 
       (SELECT COUNT(*) FROM ppd_clean), 1) AS percentage
FROM ppd_clean
GROUP BY property_type
ORDER BY transactions DESC;
