-- =====================================================
-- HELMS Universal Data Sanitization Script (FIXED)
-- =====================================================
-- This is a universal script that can sanitize ANY table
-- Just modify the configuration section below for your specific table
-- 
-- WORKFLOW:
-- 1. Create functions for fake data generation
-- 2. Copy table from original schema to dbo schema
-- 3. Sanitize data in dbo.[TableName] with specified columns
-- 4. Migrate sanitized table to R3_Sanity
-- 
-- IMPORTANT: 
-- 1. BACKUP YOUR DATABASE BEFORE RUNNING THIS SCRIPT
-- 2. Test on a copy of the database first
-- 3. Run in a transaction so you can rollback if needed
-- =====================================================

-- =====================================================
-- CONFIGURATION SECTION - MODIFY THESE VALUES
-- =====================================================

-- Table Configuration
DECLARE @SourceSchema NVARCHAR(50) = 'Helms_master'        -- Source schema (e.g., 'Helms_master', 'dbo')
DECLARE @TableName NVARCHAR(100) = 'YOUR_TABLE_NAME'       -- Table name (e.g., 'Case_Action', 'Complaints_Cases')
DECLARE @BackupTableName NVARCHAR(100) = 'YOUR_TABLE_NAME_Backup'    -- Backup table name

-- Column Sanitization Configuration
-- Format: ColumnName|FakeDataType
-- FakeDataType options: FakeText, FakeName, FakeEmail, FakePhone, FakeStreet, FakeZipcode
-- Example: 'Name|FakeName,Email|FakeEmail,Phone|FakePhone,Address|FakeStreet,Zipcode|FakeZipcode,Comments|FakeText'
DECLARE @ColumnsToSanitize NVARCHAR(MAX) = 'YOUR_COLUMN_NAME|FakeText'

-- =====================================================
-- PART 1: CREATE FAKE DATA GENERATION FUNCTIONS
-- =====================================================

USE [HELMS_Stage_PreProd]
GO

-- Function to generate fake text (returns Lorem Ipsum)
CREATE OR ALTER FUNCTION dbo.GenerateFakeText(@length INT = 50)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    RETURN 'Lorem Ipsum'
END
GO

-- Function to generate fake names using FakeNameTable
CREATE OR ALTER FUNCTION dbo.GenerateFakeName(@type NVARCHAR(20))
RETURNS NVARCHAR(100)
AS
BEGIN
    DECLARE @result NVARCHAR(100) = ''
    DECLARE @randomId INT
    
    -- Generate a random number based on current time and type
    SET @randomId = ABS(CHECKSUM(CAST(GETDATE() AS VARBINARY(8)) + CAST(@type AS VARBINARY(8)))) % 1000
    
    IF @type = 'FirstName'
    BEGIN
        SELECT TOP 1 @result = FirstName 
        FROM FakeNameTable 
        WHERE FirstName IS NOT NULL 
        ORDER BY (ABS(CHECKSUM(CAST(FirstName AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    END
    ELSE IF @type = 'LastName'
    BEGIN
        SELECT TOP 1 @result = LastName 
        FROM FakeNameTable 
        WHERE LastName IS NOT NULL 
        ORDER BY (ABS(CHECKSUM(CAST(LastName AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    END
    ELSE IF @type = 'MiddleName'
    BEGIN
        SELECT TOP 1 @result = MiddleName 
        FROM FakeNameTable 
        WHERE MiddleName IS NOT NULL 
        ORDER BY (ABS(CHECKSUM(CAST(MiddleName AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    END
    ELSE IF @type = 'Name'
    BEGIN
        SELECT TOP 1 @result = Name 
        FROM FakeNameTable 
        WHERE Name IS NOT NULL 
        ORDER BY (ABS(CHECKSUM(CAST(Name AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    END
    
    RETURN ISNULL(@result, 'Unknown')
END
GO

-- Function to generate fake email (returns fakeemail@fake.com)
CREATE OR ALTER FUNCTION dbo.GenerateFakeEmail()
RETURNS NVARCHAR(255)
AS
BEGIN
    RETURN 'fakeemail@fake.com'
END
GO

-- Function to generate fake phone (returns 9999999999)
CREATE OR ALTER FUNCTION dbo.GenerateFakePhone()
RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN '9999999999'
END
GO

-- Function to generate fake street address using FakeAddressTable
CREATE OR ALTER FUNCTION dbo.GenerateFakeStreet()
RETURNS NVARCHAR(200)
AS
BEGIN
    DECLARE @result NVARCHAR(200) = ''
    DECLARE @randomId INT
    
    -- Generate a random number based on current time
    SET @randomId = ABS(CHECKSUM(CAST(GETDATE() AS VARBINARY(8)))) % 1000
    
    SELECT TOP 1 @result = FakeStreetNumber + ' ' + FakeStreetName
    FROM FakeAddressTable 
    WHERE FakeStreetNumber IS NOT NULL AND FakeStreetName IS NOT NULL
    ORDER BY (ABS(CHECKSUM(CAST(FakeStreetNumber AS VARBINARY(8)) + CAST(FakeStreetName AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    
    RETURN ISNULL(@result, '123 Main St')
END
GO

-- Function to generate fake zipcode using FakeAddressTable
CREATE OR ALTER FUNCTION dbo.GenerateFakeZipcode()
RETURNS NVARCHAR(10)
AS
BEGIN
    DECLARE @result NVARCHAR(10) = ''
    DECLARE @randomId INT
    
    -- Generate a random number based on current time
    SET @randomId = ABS(CHECKSUM(CAST(GETDATE() AS VARBINARY(8)))) % 1000
    
    SELECT TOP 1 @result = FakeZipCode
    FROM FakeAddressTable 
    WHERE FakeZipCode IS NOT NULL
    ORDER BY (ABS(CHECKSUM(CAST(FakeZipCode AS VARBINARY(8)) + CAST(@randomId AS VARBINARY(8)))))
    
    RETURN ISNULL(@result, '12345')
END
GO

-- =====================================================
-- PART 2: COPY TABLE FROM SOURCE TO dbo SCHEMA
-- =====================================================

USE [HELMS_Stage_PreProd]
GO

-- Re-declare variables for this batch
DECLARE @SourceSchema NVARCHAR(50) = 'Helms_master'
DECLARE @TableName NVARCHAR(100) = 'YOUR_TABLE_NAME'
DECLARE @BackupTableName NVARCHAR(100) = 'YOUR_TABLE_NAME_Backup'

DECLARE @SourceTable NVARCHAR(150) = @SourceSchema + '.' + @TableName
DECLARE @BackupTable NVARCHAR(150) = @SourceSchema + '.' + @BackupTableName
DECLARE @WorkingTable NVARCHAR(150) = 'dbo.' + @TableName + '_Sanity'

PRINT 'Creating copy of ' + @SourceTable + ' in dbo schema...'

-- Create backup of original table first
PRINT 'Creating backup of original ' + @SourceTable + ' table...'
DECLARE @DropBackupSQL NVARCHAR(500) = 'IF OBJECT_ID(''' + @BackupTable + ''', ''U'') IS NOT NULL DROP TABLE ' + @BackupTable
EXEC sp_executesql @DropBackupSQL

DECLARE @CreateBackupSQL NVARCHAR(500) = 'SELECT * INTO ' + @BackupTable + ' FROM ' + @SourceTable
EXEC sp_executesql @CreateBackupSQL

-- Create working copy in dbo schema
PRINT 'Creating working copy in dbo schema...'
DECLARE @DropWorkingSQL NVARCHAR(500) = 'IF OBJECT_ID(''' + @WorkingTable + ''', ''U'') IS NOT NULL DROP TABLE ' + @WorkingTable
EXEC sp_executesql @DropWorkingSQL

DECLARE @CreateWorkingSQL NVARCHAR(500) = 'SELECT * INTO ' + @WorkingTable + ' FROM ' + @SourceTable
EXEC sp_executesql @CreateWorkingSQL

PRINT 'Copy created successfully: ' + @WorkingTable
PRINT 'Original table preserved: ' + @SourceTable
PRINT 'Backup created: ' + @BackupTable
PRINT ''

GO

-- =====================================================
-- PART 3: SANITIZE DATA IN dbo.[TableName] WITH RANDOM VALUES
-- =====================================================

USE [HELMS_Stage_PreProd]
GO

-- Re-declare variables for this batch
DECLARE @SourceSchema NVARCHAR(50) = 'Helms_master'
DECLARE @TableName NVARCHAR(100) = 'YOUR_TABLE_NAME'
DECLARE @ColumnsToSanitize NVARCHAR(MAX) = 'YOUR_COLUMN_NAME|FakeText'

DECLARE @WorkingTable NVARCHAR(150) = 'dbo.' + @TableName + '_Sanity'

BEGIN TRANSACTION

PRINT 'Starting data sanitization with TRULY RANDOM values...'

-- Show current data count
DECLARE @RecordCount INT
DECLARE @CountSQL NVARCHAR(500) = 'SELECT @Count = COUNT(*) FROM ' + @WorkingTable
EXEC sp_executesql @CountSQL, N'@Count INT OUTPUT', @Count = @RecordCount OUTPUT
PRINT 'Total records in ' + @WorkingTable + ': ' + CAST(@RecordCount AS NVARCHAR(10))

-- Parse the columns configuration
DECLARE @ColumnList TABLE (ColumnName NVARCHAR(100), FakeDataType NVARCHAR(50))
INSERT INTO @ColumnList
SELECT 
    LTRIM(RTRIM(LEFT(Item, CHARINDEX('|', Item) - 1))) as ColumnName,
    LTRIM(RTRIM(RIGHT(Item, LEN(Item) - CHARINDEX('|', Item)))) as FakeDataType
FROM (
    SELECT value as Item
    FROM STRING_SPLIT(@ColumnsToSanitize, ',')
) t

-- Build WHERE clause for non-null records
DECLARE @WhereClause NVARCHAR(MAX) = ''
SELECT @WhereClause = @WhereClause + 
    CASE WHEN @WhereClause = '' THEN '' ELSE ' OR ' END +
    ColumnName + ' IS NOT NULL'
FROM @ColumnList

-- Show records that will be updated
DECLARE @UpdateCount INT
DECLARE @UpdateCountSQL NVARCHAR(500) = 'SELECT @Count = COUNT(*) FROM ' + @WorkingTable + ' WHERE ' + @WhereClause
EXEC sp_executesql @UpdateCountSQL, N'@Count INT OUTPUT', @Count = @UpdateCount OUTPUT
PRINT 'Records that will be updated: ' + CAST(@UpdateCount AS NVARCHAR(10))

-- Process each column type that needs random values
DECLARE @ColumnName NVARCHAR(100), @FakeDataType NVARCHAR(50)
DECLARE column_cursor CURSOR FOR 
SELECT ColumnName, FakeDataType FROM @ColumnList WHERE FakeDataType IN ('FakeName', 'FakeStreet', 'FakeZipcode')

OPEN column_cursor
FETCH NEXT FROM column_cursor INTO @ColumnName, @FakeDataType

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Processing ' + @ColumnName + ' with ' + @FakeDataType + '...'
    
    -- Update the column with random values using CROSS APPLY (no temp tables)
    DECLARE @UpdateColumnSQL NVARCHAR(MAX)
    
    IF @FakeDataType = 'FakeName'
    BEGIN
        SET @UpdateColumnSQL = 
            'UPDATE v SET ' + @ColumnName + ' = fn.Name ' +
            'FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum FROM ' + @WorkingTable + ' WHERE ' + @ColumnName + ' IS NOT NULL) v ' +
            'CROSS APPLY ( ' +
                'SELECT Name, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum ' +
                'FROM FakeNameTable WHERE Name IS NOT NULL ' +
            ') fn ' +
            'WHERE (v.RowNum % (SELECT COUNT(*) FROM FakeNameTable WHERE Name IS NOT NULL)) + 1 = fn.RowNum'
    END
    ELSE IF @FakeDataType = 'FakeStreet'
    BEGIN
        SET @UpdateColumnSQL = 
            'UPDATE v SET ' + @ColumnName + ' = fa.FakeStreet ' +
            'FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum FROM ' + @WorkingTable + ' WHERE ' + @ColumnName + ' IS NOT NULL) v ' +
            'CROSS APPLY ( ' +
                'SELECT FakeStreetNumber + '' '' + FakeStreetName as FakeStreet, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum ' +
                'FROM FakeAddressTable WHERE FakeStreetNumber IS NOT NULL AND FakeStreetName IS NOT NULL ' +
            ') fa ' +
            'WHERE (v.RowNum % (SELECT COUNT(*) FROM FakeAddressTable WHERE FakeStreetNumber IS NOT NULL AND FakeStreetName IS NOT NULL)) + 1 = fa.RowNum'
    END
    ELSE IF @FakeDataType = 'FakeZipcode'
    BEGIN
        SET @UpdateColumnSQL = 
            'UPDATE v SET ' + @ColumnName + ' = fa.FakeZipCode ' +
            'FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum FROM ' + @WorkingTable + ' WHERE ' + @ColumnName + ' IS NOT NULL) v ' +
            'CROSS APPLY ( ' +
                'SELECT FakeZipCode, ROW_NUMBER() OVER (ORDER BY NEWID()) as RowNum ' +
                'FROM FakeAddressTable WHERE FakeZipCode IS NOT NULL ' +
            ') fa ' +
            'WHERE (v.RowNum % (SELECT COUNT(*) FROM FakeAddressTable WHERE FakeZipCode IS NOT NULL)) + 1 = fa.RowNum'
    END
    
    EXEC sp_executesql @UpdateColumnSQL
    
    FETCH NEXT FROM column_cursor INTO @ColumnName, @FakeDataType
END

CLOSE column_cursor
DEALLOCATE column_cursor

-- Process columns that don't need random values (FakeText, FakeEmail, FakePhone)
DECLARE @SimpleUpdateSQL NVARCHAR(MAX) = ''
SELECT @SimpleUpdateSQL = @SimpleUpdateSQL + 
    CASE WHEN @SimpleUpdateSQL = '' THEN '' ELSE ', ' END +
    ColumnName + ' = CASE WHEN ' + ColumnName + ' IS NOT NULL THEN ' +
    CASE FakeDataType
        WHEN 'FakeText' THEN '''Lorem Ipsum'''
        WHEN 'FakeEmail' THEN '''fakeemail@fake.com'''
        WHEN 'FakePhone' THEN '''9999999999'''
        ELSE '''Lorem Ipsum'''
    END +
    ' ELSE ' + ColumnName + ' END'
FROM @ColumnList
WHERE FakeDataType IN ('FakeText', 'FakeEmail', 'FakePhone')

-- Execute simple updates if any
IF @SimpleUpdateSQL != ''
BEGIN
    DECLARE @FullSimpleUpdateSQL NVARCHAR(MAX) = 'UPDATE ' + @WorkingTable + ' SET ' + @SimpleUpdateSQL + ' WHERE ' + @WhereClause
    PRINT 'Executing simple value updates...'
    EXEC sp_executesql @FullSimpleUpdateSQL
END

-- Show results
DECLARE @UpdatedCount INT = @@ROWCOUNT
PRINT 'Records updated: ' + CAST(@UpdatedCount AS NVARCHAR(10))

-- Verify the changes
PRINT 'Verification - Sample of updated records:'
DECLARE @SampleSQL NVARCHAR(500) = 'SELECT TOP 5 * FROM ' + @WorkingTable + ' WHERE ' + @WhereClause
EXEC sp_executesql @SampleSQL

COMMIT TRANSACTION
PRINT 'Data sanitization with TRULY RANDOM values completed!'

GO

-- =====================================================
-- PART 4: MIGRATE SANITIZED TABLE TO R3_SANITY
-- =====================================================

USE [HELMS_Stage_R3_Sanity]
GO

-- Re-declare variables for this batch
DECLARE @TableName NVARCHAR(100) = 'YOUR_TABLE_NAME'

DECLARE @WorkingTable NVARCHAR(150) = 'dbo.' + @TableName + '_Sanity'
DECLARE @TargetTable NVARCHAR(150) = 'dbo.' + @TableName + '_Sanity'

PRINT 'Starting migration of sanitized ' + @WorkingTable + ' table to R3_Sanity...'

-- Drop existing table if it exists
DECLARE @DropTargetSQL NVARCHAR(500) = 'IF OBJECT_ID(''' + @TargetTable + ''', ''U'') IS NOT NULL BEGIN PRINT ''WARNING: ' + @TargetTable + ' already exists in R3_Sanity. Dropping existing table...'' DROP TABLE ' + @TargetTable + ' END'
EXEC sp_executesql @DropTargetSQL

-- Create the table in R3_Sanity
PRINT 'Creating table in R3_Sanity...'
DECLARE @MigrateSQL NVARCHAR(500) = 'SELECT * INTO ' + @TargetTable + ' FROM HELMS_Stage_PreProd.' + @WorkingTable
EXEC sp_executesql @MigrateSQL

-- Show migration results
DECLARE @MigratedCount INT
DECLARE @MigrateCountSQL NVARCHAR(500) = 'SELECT @Count = COUNT(*) FROM ' + @TargetTable
EXEC sp_executesql @MigrateCountSQL, N'@Count INT OUTPUT', @Count = @MigratedCount OUTPUT
PRINT 'Records migrated to R3_Sanity: ' + CAST(@MigratedCount AS NVARCHAR(10))

-- Show sample of migrated data
PRINT ''
PRINT 'Sample of migrated data in R3_Sanity:'
DECLARE @SampleMigrateSQL NVARCHAR(500) = 'SELECT TOP 3 * FROM ' + @TargetTable
EXEC sp_executesql @SampleMigrateSQL

PRINT 'Migration completed successfully!'

GO

-- =====================================================
-- PART 5: RESTORE FROM BACKUP (IF NEEDED)
-- =====================================================

/*
-- RESTORE SCRIPT (Uncomment and run if needed to restore original data)

USE [HELMS_Stage_PreProd]
GO

-- Re-declare variables for restore
DECLARE @SourceSchema NVARCHAR(50) = 'Helms_master'
DECLARE @TableName NVARCHAR(100) = 'YOUR_TABLE_NAME'
DECLARE @BackupTableName NVARCHAR(100) = 'YOUR_TABLE_NAME_Backup'

DECLARE @SourceTable NVARCHAR(150) = @SourceSchema + '.' + @TableName
DECLARE @BackupTable NVARCHAR(150) = @SourceSchema + '.' + @BackupTableName
DECLARE @WorkingTable NVARCHAR(150) = 'dbo.' + @TableName + '_Sanity'

PRINT 'Restoring original data from backup table...'

-- Restore original table
DECLARE @RestoreSQL NVARCHAR(500) = 'TRUNCATE TABLE ' + @SourceTable + ' INSERT INTO ' + @SourceTable + ' SELECT * FROM ' + @BackupTable
EXEC sp_executesql @RestoreSQL

PRINT 'Table restored from backup successfully!'

-- Clean up working copy
DECLARE @CleanupSQL NVARCHAR(500) = 'DROP TABLE IF EXISTS ' + @WorkingTable
EXEC sp_executesql @CleanupSQL
PRINT 'Working copy removed successfully!'
*/

PRINT 'Universal sanitization script execution completed!'
PRINT ''
PRINT 'SUMMARY:'
PRINT '- Original table: Helms_master.YOUR_TABLE_NAME (preserved)'
PRINT '- Backup table: Helms_master.YOUR_TABLE_NAME_Backup (created)'
PRINT '- Working copy: dbo.YOUR_TABLE_NAME_Sanity (sanitized)'
PRINT '- Migrated table: dbo.YOUR_TABLE_NAME_Sanity in R3_Sanity (final result)'
