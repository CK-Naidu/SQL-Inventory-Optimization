-- =============================================
--  Urban Retail Co. Inventory Analytics Project
--  SQL Script for Schema + Analysis Queries
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
-- Analytics Queries
-- =====================

-- 1. Stock Level by Store and Region
SELECT 
    s.StoreID,
    r.RegionName,
    SUM(it.InventoryLevel) AS TotalInventory,
    ROUND(AVG(it.InventoryLevel), 2) AS AvgInventory
FROM InventoryTransactions it
JOIN Stores s ON it.StoreID = s.StoreID
JOIN Regions r ON s.RegionID = r.RegionID
GROUP BY s.StoreID, r.RegionName;

-- 2. Reorder Point Detection (1.5 * Avg Daily Sales)
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
    ROUND(AvgSales.AvgDailySales * 1.5, 2) AS ReorderPoint
FROM InventoryTransactions it
JOIN AvgSales ON it.ProductID = AvgSales.ProductID AND it.StoreID = AvgSales.StoreID
GROUP BY it.ProductID, it.StoreID, AvgSales.AvgDailySales
HAVING MAX(it.InventoryLevel) < (AvgSales.AvgDailySales * 1.5);

-- 3. Stockout Rate (% of Days Inventory = 0)
SELECT 
    ProductID,
    StoreID,
    ROUND(SUM(CASE WHEN InventoryLevel = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS StockoutRatePercent
FROM InventoryTransactions
GROUP BY ProductID, StoreID
ORDER BY StockoutRatePercent DESC;

-- 4. Inventory Turnover (Total Sold / Avg Inventory)
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
