-- =============================================
--  Urban Retail Co. Inventory Analytics Project
--  Final SQL Script with Schema, ETL, and KPI Queries
-- =============================================

-- Create Schema
CREATE DATABASE IF NOT EXISTS urban_retail_db;
USE urban_retail_db;

-- =====================
-- Schema Design
-- =====================

CREATE TABLE Regions (
    RegionID INT PRIMARY KEY AUTO_INCREMENT,
    RegionName VARCHAR(50) NOT NULL
);

CREATE TABLE Stores (
    StoreID VARCHAR(10) PRIMARY KEY,
    RegionID INT,
    FOREIGN KEY (RegionID) REFERENCES Regions(RegionID)
);

CREATE TABLE Categories (
    CategoryID INT PRIMARY KEY AUTO_INCREMENT,
    CategoryName VARCHAR(50) NOT NULL
);

CREATE TABLE Products (
    ProductID VARCHAR(10) PRIMARY KEY,
    CategoryID INT,
    FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID)
);

CREATE TABLE InventoryTransactions (
    TransactionID INT PRIMARY KEY AUTO_INCREMENT,
    Date DATE,
    StoreID VARCHAR(10),
    ProductID VARCHAR(10),
    InventoryLevel INT,
    UnitsSold INT,
    UnitsOrdered INT,
    DemandForecast DECIMAL(10,2),
    Price DECIMAL(10,2),
    Discount INT,
    WeatherCondition VARCHAR(50),
    HolidayPromotion INT,
    CompetitorPricing DECIMAL(10,2),
    Seasonality VARCHAR(50),
    FOREIGN KEY (StoreID) REFERENCES Stores(StoreID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- =====================
-- ETL: Populate Normalized Tables
-- =====================

-- Insert Regions
INSERT IGNORE INTO Regions (RegionName)
SELECT DISTINCT Region FROM inventory_forecasting_raw;

-- Insert Stores
INSERT IGNORE INTO Stores (StoreID, RegionID)
SELECT DISTINCT `Store ID`,
    (SELECT RegionID FROM Regions WHERE RegionName = r.Region)
FROM inventory_forecasting_raw r;

-- Insert Categories
INSERT IGNORE INTO Categories (CategoryName)
SELECT DISTINCT Category FROM inventory_forecasting_raw;

-- Insert Products
INSERT IGNORE INTO Products (ProductID, CategoryID)
SELECT DISTINCT `Product ID`,
    (SELECT CategoryID FROM Categories WHERE CategoryName = r.Category)
FROM inventory_forecasting_raw r;

-- Insert Inventory Transactions
INSERT INTO InventoryTransactions (
    Date, StoreID, ProductID, InventoryLevel, UnitsSold, UnitsOrdered,
    DemandForecast, Price, Discount, WeatherCondition, HolidayPromotion,
    CompetitorPricing, Seasonality
)
SELECT 
    STR_TO_DATE(Date, '%Y-%m-%d'),
    `Store ID`,
    `Product ID`,
    `Inventory Level`,
    `Units Sold`,
    `Units Ordered`,
    `Demand Forecast`,
    Price,
    Discount,
    `Weather Condition`,
    `Holiday/Promotion`,
    `Competitor Pricing`,
    Seasonality
FROM inventory_forecasting_raw;

-- =====================
-- KPI / Analytics Queries
-- =====================

-- 1. Total & Avg Inventory by Store and Region
SELECT 
    s.StoreID,
    r.RegionName,
    SUM(it.InventoryLevel) AS TotalInventory,
    ROUND(AVG(it.InventoryLevel), 2) AS AvgInventory
FROM InventoryTransactions it
JOIN Stores s ON it.StoreID = s.StoreID
JOIN Regions r ON s.RegionID = r.RegionID
GROUP BY s.StoreID, r.RegionName;

-- 2. Reorder Point Detection (Demo: 3.0x Threshold)
WITH AvgSales AS (
    SELECT 
        ProductID,
        StoreID,
        ROUND(AVG(UnitsSold), 2) AS AvgDailySales
    FROM InventoryTransactions
    GROUP BY ProductID, StoreID
)
SELECT 
    it.ProductID,
    it.StoreID,
    MAX(it.InventoryLevel) AS CurrentInventory,
    ROUND(AvgSales.AvgDailySales * 3.0, 2) AS ReorderPoint
FROM InventoryTransactions it
JOIN AvgSales ON it.ProductID = AvgSales.ProductID AND it.StoreID = AvgSales.StoreID
GROUP BY it.ProductID, it.StoreID, AvgSales.AvgDailySales
HAVING MAX(it.InventoryLevel) < (AvgSales.AvgDailySales * 3.0)
ORDER BY ReorderPoint DESC;

-- 3. Stockout Rate (Days Inventory = 0)
SELECT 
    ProductID,
    StoreID,
    ROUND(SUM(CASE WHEN InventoryLevel = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS StockoutRatePercent
FROM InventoryTransactions
GROUP BY ProductID, StoreID
ORDER BY StockoutRatePercent DESC;

-- 4. Inventory Turnover Rate
WITH AvgInventory AS (
    SELECT 
        ProductID,
        StoreID,
        ROUND(AVG(InventoryLevel), 2) AS AvgInventory
    FROM InventoryTransactions
    GROUP BY ProductID, StoreID
),
TotalSold AS (
    SELECT 
        ProductID,
        StoreID,
        SUM(UnitsSold) AS TotalUnitsSold
    FROM InventoryTransactions
    GROUP BY ProductID, StoreID
)
SELECT 
    s.ProductID,
    s.StoreID,
    s.TotalUnitsSold,
    i.AvgInventory,
    ROUND(s.TotalUnitsSold / i.AvgInventory, 2) AS TurnoverRate
FROM TotalSold s
JOIN AvgInventory i ON s.ProductID = i.ProductID AND s.StoreID = i.StoreID
ORDER BY TurnoverRate DESC;

-- 5. Fast vs Slow-Moving Products
SELECT 
    p.ProductID,
    c.CategoryName,
    SUM(it.UnitsSold) AS TotalUnitsSold,
    CASE 
        WHEN SUM(it.UnitsSold) > 1000 THEN 'Fast-Moving'
        ELSE 'Slow-Moving'
    END AS ProductType
FROM InventoryTransactions it
JOIN Products p ON it.ProductID = p.ProductID
JOIN Categories c ON p.CategoryID = c.CategoryID
GROUP BY p.ProductID, c.CategoryName
ORDER BY TotalUnitsSold DESC;

-- 6. Overstocked & Slow-Moving Products
SELECT 
    ProductID,
    StoreID,
    AVG(InventoryLevel) AS AvgInventory,
    SUM(UnitsSold) AS TotalUnitsSold
FROM InventoryTransactions
GROUP BY ProductID, StoreID
HAVING AvgInventory > 100 AND TotalUnitsSold < 500;

-- 7. Weather Impact on Sales
SELECT 
    WeatherCondition,
    AVG(UnitsSold) AS AvgUnitsSold
FROM InventoryTransactions
GROUP BY WeatherCondition;

-- 8. Demand Forecast vs Actual Sales Accuracy
SELECT 
    ProductID,
    StoreID,
    ROUND(AVG(DemandForecast), 2) AS AvgForecast,
    ROUND(AVG(UnitsSold), 2) AS AvgSold,
    ROUND(AVG(UnitsSold) - AVG(DemandForecast), 2) AS ForecastAccuracy
FROM InventoryTransactions
GROUP BY ProductID, StoreID
ORDER BY ForecastAccuracy DESC;

-- 9. Inventory Age Proxy: Days with Low Sales (< 5)
SELECT 
    ProductID,
    StoreID,
    COUNT(*) AS TotalDays,
    SUM(CASE WHEN UnitsSold < 5 THEN 1 ELSE 0 END) AS LowSalesDays
FROM InventoryTransactions
GROUP BY ProductID, StoreID;
