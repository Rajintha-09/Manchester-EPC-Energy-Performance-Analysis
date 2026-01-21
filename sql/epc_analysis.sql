-- =====================================================
-- EPC ANALYSIS FOR POWER BI
-- =====================================================
--Check Data Loaded Correctly
SELECT 'Certificate Records' AS Dataset, COUNT(*) AS TotalRecords
FROM EPC.dbo.certificate_new
UNION ALL
SELECT 'Recommendation Records', COUNT(*)
FROM EPC.dbo.recommendations_new;
GO

--drop unnecessary columns physically for better analyasis 
ALTER TABLE dbo.certificate_new
DROP COLUMN 
      [ADDRESS2],
	  [ADDRESS1],
	  [ADDRESS3],
      [COUNTY],
	  [LOCAL_AUTHORITY],
	  [LOCAL_AUTHORITY_LABEL],
	  SHEATING_ENERGY_EFF,
	  SHEATING_ENV_EFF,
	  FLOOR_ENERGY_EFF,
	  FLOOR_ENV_EFF;

--count NULL values
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + 
    'SELECT ''' + COLUMN_NAME + ''' AS ColumnName, COUNT(*) AS NullCount
     FROM EPC.dbo.certificate_new
     WHERE [' + COLUMN_NAME + '] IS NULL
     UNION ALL '
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'certificate_new'
  AND TABLE_SCHEMA = 'dbo';

-- Remove the last 'UNION ALL'
SET @sql = LEFT(@sql, LEN(@sql) - LEN(' UNION ALL '));

-- Wrap in derived table to order by NullCount descending
SET @sql = 'SELECT ColumnName, NullCount
            FROM (' + @sql + ') AS Counts
            ORDER BY NullCount DESC;';
EXEC sp_executesql @sql;


--There are no duplicates in this dataset. Its Guaranteed by authors.


--convert every "NO DATA!", "unknown" and "N/A" values(invalid strings) to null in the dataset
IF OBJECT_ID('dbo.CleanInvalidStrings', 'P') IS NOT NULL
    DROP PROCEDURE dbo.CleanInvalidStrings;
GO

CREATE PROCEDURE dbo.CleanInvalidStrings
    @TableName SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX) = N'';

    -- Build dynamic SQL to update all string columns
    SELECT @sql = @sql + 
        'UPDATE ' + QUOTENAME(@TableName) + '
         SET ' + QUOTENAME(COLUMN_NAME) + ' = NULL
         WHERE LOWER(' + QUOTENAME(COLUMN_NAME) + ') IN (
            ''no data!'',
            ''nodata!'',
            ''unknown'',
            ''n/a'',
            ''none'',
            ''invalid!'',
            ''not defined''
         ); '
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = @TableName
      AND DATA_TYPE IN ('varchar','nvarchar','char','nchar','text','ntext');

    -- Execute the dynamic SQL
    EXEC sp_executesql @sql;
END
GO
EXEC dbo.CleanInvalidStrings 'certificate_new';



-- VIEW 1: PROPERTY IDENTIFICATION & LOCATION(manchester) WITHOUT NULL VALUES
-- Use for: Property lookup, geographic analysis, filtering by area
go
CREATE VIEW vw_EPC_Property_Info AS
SELECT 
    LMK_KEY,
    ADDRESS,
    POSTCODE,
    POSTTOWN,
    BUILDING_REFERENCE_NUMBER,
    UPRN,
    UPRN_SOURCE,
    CONSTITUENCY,
    CONSTITUENCY_LABEL
FROM EPC.dbo.certificate_new
WHERE LMK_KEY IS NOT NULL
  AND ADDRESS IS NOT NULL
  AND POSTCODE IS NOT NULL
  AND POSTTOWN IS NOT NULL
  AND BUILDING_REFERENCE_NUMBER IS NOT NULL
  AND UPRN IS NOT NULL
  AND UPRN_SOURCE IS NOT NULL
  AND CONSTITUENCY IS NOT NULL
  AND CONSTITUENCY_LABEL IS NOT NULL;
go


-- VIEW 2: ENERGY RATINGS & EFFICIENCY
-- Use for: Performance scoring, before/after comparisons, rating distribution
CREATE VIEW vw_EPC_Energy_Ratings AS
SELECT 
    LMK_KEY,
    CURRENT_ENERGY_RATING,
    POTENTIAL_ENERGY_RATING,
    CURRENT_ENERGY_EFFICIENCY,
    POTENTIAL_ENERGY_EFFICIENCY,
    ENVIRONMENT_IMPACT_CURRENT,
    ENVIRONMENT_IMPACT_POTENTIAL,
    ENERGY_CONSUMPTION_CURRENT,
    ENERGY_CONSUMPTION_POTENTIAL
FROM [certificate_new];
go
-- VIEW 3: CARBON EMISSIONS
-- Use for: Environmental impact analysis, carbon reduction potential
CREATE VIEW vw_EPC_Carbon_Emissions AS
SELECT 
    LMK_KEY,
    CO2_EMISSIONS_CURRENT,
    CO2_EMISSIONS_POTENTIAL,
    CO2_EMISS_CURR_PER_FLOOR_AREA,
    ENVIRONMENT_IMPACT_CURRENT,
    ENVIRONMENT_IMPACT_POTENTIAL
FROM [certificate_new];
go
-- VIEW 4: COST ANALYSIS
-- Use for: Running costs, savings potential, cost breakdown by utility
CREATE VIEW vw_EPC_Costs AS
SELECT 
    LMK_KEY,
    LIGHTING_COST_CURRENT,
    LIGHTING_COST_POTENTIAL,
    HEATING_COST_CURRENT,
    HEATING_COST_POTENTIAL,
    HOT_WATER_COST_CURRENT,
    HOT_WATER_COST_POTENTIAL,
    (LIGHTING_COST_CURRENT + HEATING_COST_CURRENT + HOT_WATER_COST_CURRENT) AS TOTAL_COST_CURRENT,
    (LIGHTING_COST_POTENTIAL + HEATING_COST_POTENTIAL + HOT_WATER_COST_POTENTIAL) AS TOTAL_COST_POTENTIAL,
    (LIGHTING_COST_CURRENT - LIGHTING_COST_POTENTIAL) AS LIGHTING_SAVINGS,
    (HEATING_COST_CURRENT - HEATING_COST_POTENTIAL) AS HEATING_SAVINGS,
    (HOT_WATER_COST_CURRENT - HOT_WATER_COST_POTENTIAL) AS HOT_WATER_SAVINGS
FROM [certificate_new];
go
-- VIEW 5: PROPERTY CHARACTERISTICS
-- Use for: Property type analysis, building form segmentation
CREATE VIEW vw_EPC_Property_Characteristics AS
SELECT 
    LMK_KEY,
    PROPERTY_TYPE,
    BUILT_FORM,
    CONSTRUCTION_AGE_BAND,
    TENURE,
    TOTAL_FLOOR_AREA,
    NUMBER_HABITABLE_ROOMS,
    NUMBER_HEATED_ROOMS,
    FLOOR_LEVEL,
    FLAT_TOP_STOREY,
    FLAT_STOREY_COUNT,
    FLOOR_HEIGHT,
    EXTENSION_COUNT
FROM [certificate_new]
WHERE 
    BUILT_FORM IS NOT NULL
    AND TENURE IS NOT NULL
    AND CONSTRUCTION_AGE_BAND IS NOT NULL;

go

--Calculate the contruction duration of the property
--if CONSTRUCTION_AGE_BAND is NULL replaces it with 'Unknown'.
UPDATE EPC.dbo.certificate_new
SET CONSTRUCTION_AGE_BAND = 'Unknown'
WHERE CONSTRUCTION_AGE_BAND IS NULL;


go
CREATE VIEW building_age_dates AS
SELECT 
    CONSTRUCTION_AGE_BAND,
    
    -- Extract start date
    CASE 
        WHEN CONSTRUCTION_AGE_BAND LIKE '%-%' THEN 
            SUBSTRING(CONSTRUCTION_AGE_BAND, 
                     CHARINDEX(':', CONSTRUCTION_AGE_BAND) + 2, 
                     4)
        WHEN CONSTRUCTION_AGE_BAND NOT LIKE '%-%' AND CONSTRUCTION_AGE_BAND NOT LIKE '%NULL%' THEN 
            CONSTRUCTION_AGE_BAND
        ELSE NULL
    END AS start_year,
    
    -- Extract end date
    CASE 
        WHEN CONSTRUCTION_AGE_BAND LIKE '%-%' THEN 
            SUBSTRING(CONSTRUCTION_AGE_BAND, 
                     CHARINDEX('-', CONSTRUCTION_AGE_BAND) + 1, 
                     4)
        WHEN CONSTRUCTION_AGE_BAND NOT LIKE '%-%' AND CONSTRUCTION_AGE_BAND NOT LIKE '%NULL%' THEN 
            CONSTRUCTION_AGE_BAND
        ELSE NULL
    END AS end_year
    
FROM certificate_new;


-- VIEW 6: BUILDING FABRIC (Walls, Roof, Floor, Windows)
-- Use for: Insulation analysis, fabric improvement opportunities
go
CREATE VIEW vw_EPC_Building_Fabric AS
SELECT 
    LMK_KEY,
    WALLS_DESCRIPTION,
    WALLS_ENERGY_EFF,
    WALLS_ENV_EFF,
    ROOF_DESCRIPTION,
    ROOF_ENERGY_EFF,
    ROOF_ENV_EFF,
    FLOOR_DESCRIPTION,
    WINDOWS_DESCRIPTION,
    WINDOWS_ENERGY_EFF,
    WINDOWS_ENV_EFF,
    GLAZED_TYPE,
    GLAZED_AREA,
    MULTI_GLAZE_PROPORTION
FROM [certificate_new];
go
-- VIEW 7: HEATING SYSTEMS
-- Use for: Heating system analysis, upgrade opportunities
CREATE VIEW vw_EPC_Heating_Systems AS
SELECT 
    LMK_KEY,
    MAINHEAT_DESCRIPTION,
    MAINHEAT_ENERGY_EFF,
    MAINHEAT_ENV_EFF,
    MAIN_HEATING_CONTROLS,
    MAINHEATCONT_DESCRIPTION,
    MAINHEATC_ENERGY_EFF,
    MAINHEATC_ENV_EFF,
    SECONDHEAT_DESCRIPTION,
    MAIN_FUEL,
    MAINS_GAS_FLAG,
    NUMBER_OPEN_FIREPLACES,
    HEAT_LOSS_CORRIDOR,
    UNHEATED_CORRIDOR_LENGTH
FROM [certificate_new];
go
-- VIEW 8: HOT WATER & LIGHTING
-- Use for: Hot water system and lighting efficiency analysis
CREATE VIEW vw_EPC_Hot_Water_Lighting AS
SELECT 
    LMK_KEY,
    HOTWATER_DESCRIPTION,
    HOT_WATER_ENERGY_EFF,
    HOT_WATER_ENV_EFF,
    SOLAR_WATER_HEATING_FLAG,
    LIGHTING_DESCRIPTION,
    LIGHTING_ENERGY_EFF,
    LIGHTING_ENV_EFF,
    LOW_ENERGY_LIGHTING,
    FIXED_LIGHTING_OUTLETS_COUNT,
    LOW_ENERGY_FIXED_LIGHT_COUNT
FROM [certificate_new];
go
-- VIEW 9: RENEWABLE ENERGY & ADVANCED FEATURES
-- Use for: Renewable energy analysis, green technology adoption
CREATE VIEW vw_EPC_Renewables AS
SELECT 
    LMK_KEY,
    PHOTO_SUPPLY,
    SOLAR_WATER_HEATING_FLAG,
    WIND_TURBINE_COUNT,
    MECHANICAL_VENTILATION,
    ENERGY_TARIFF
FROM [certificate_new];
go
-- VIEW 10: INSPECTION & ADMIN DATA
-- Use for: Data quality, reporting periods, transaction analysis
CREATE VIEW vw_EPC_Admin AS
SELECT 
    LMK_KEY,
    INSPECTION_DATE,
    LODGEMENT_DATE,
    TRANSACTION_TYPE,
    REPORT_TYPE
FROM [certificate_new];
go

-- COMPREHENSIVE VIEW: Key Metrics Summary

CREATE VIEW vw_EPC_Dashboard_Summary AS
SELECT 
    LMK_KEY,
    CURRENT_ENERGY_RATING,
    POTENTIAL_ENERGY_RATING,
    CURRENT_ENERGY_EFFICIENCY,
    POTENTIAL_ENERGY_EFFICIENCY,
    (POTENTIAL_ENERGY_EFFICIENCY - CURRENT_ENERGY_EFFICIENCY) AS EFFICIENCY_GAP,
    TOTAL_FLOOR_AREA,
    CO2_EMISSIONS_CURRENT,
    CO2_EMISSIONS_POTENTIAL,
    (CO2_EMISSIONS_POTENTIAL - CO2_EMISSIONS_CURRENT ) AS CO2_REDUCTION_POTENTIAL,
    (LIGHTING_COST_CURRENT + HEATING_COST_CURRENT + HOT_WATER_COST_CURRENT) AS TOTAL_COST_CURRENT,
    (LIGHTING_COST_POTENTIAL + HEATING_COST_POTENTIAL + HOT_WATER_COST_POTENTIAL) AS TOTAL_COST_POTENTIAL,
    (LIGHTING_COST_CURRENT + HEATING_COST_CURRENT + HOT_WATER_COST_CURRENT) - 
    (LIGHTING_COST_POTENTIAL + HEATING_COST_POTENTIAL + HOT_WATER_COST_POTENTIAL) AS ANNUAL_SAVINGS_POTENTIAL
FROM [certificate_new];
go



-- CTE + VIEW = date dimension for Power BI
CREATE VIEW vw_EPC_inspection_DateDimension AS
WITH DateRange AS (
    SELECT 
        MIN(CAST(INSPECTION_DATE AS DATE)) AS StartDate,
        MAX(CAST(INSPECTION_DATE AS DATE)) AS EndDate
    FROM certificate_new
),
Tally AS (
    SELECT TOP (40000) 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
    FROM master..spt_values
),
Calendar AS (
    SELECT DATEADD(DAY, N, StartDate) AS CalendarDate
    FROM DateRange
    JOIN Tally ON N <= DATEDIFF(DAY, StartDate, EndDate)
)
SELECT 
    CalendarDate AS Date,
    YEAR(CalendarDate) AS Year,
    MONTH(CalendarDate) AS Month,
    DATENAME(MONTH, CalendarDate) AS MonthName,
    DATEPART(QUARTER, CalendarDate) AS Quarter,
    DATEPART(WEEK, CalendarDate) AS WeekOfYear,
    DATENAME(WEEKDAY, CalendarDate) AS DayName,
    DAY(CalendarDate) AS DayOfMonth
FROM Calendar;
GO


CREATE VIEW vw_EPC_lodgement_DateDimension AS
WITH DateRange AS (
    SELECT 
        MIN(CAST(LODGEMENT_DATE AS DATE)) AS StartDate,
        MAX(CAST(LODGEMENT_DATE AS DATE)) AS EndDate
    FROM certificate_new
),
Tally AS (
    SELECT TOP (40000) 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS N
    FROM master..spt_values
),
Calendar AS (
    SELECT DATEADD(DAY, N, StartDate) AS CalendarDate
    FROM DateRange
    JOIN Tally ON N <= DATEDIFF(DAY, StartDate, EndDate)
)
SELECT 
    CalendarDate AS Date,
    YEAR(CalendarDate) AS Year,
    MONTH(CalendarDate) AS Month,
    DATENAME(MONTH, CalendarDate) AS MonthName,
    DATEPART(QUARTER, CalendarDate) AS Quarter,
    DATEPART(WEEK, CalendarDate) AS WeekOfYear,
    DATENAME(WEEKDAY, CalendarDate) AS DayName,
    DAY(CalendarDate) AS DayOfMonth
FROM Calendar;
GO