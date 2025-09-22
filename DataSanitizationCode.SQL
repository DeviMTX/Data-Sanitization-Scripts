/*
 * Purpose:
 *    OPTIMIZED VERSION
 *    Shows which fields succeeded/failed and specific error details
 *    Updated to use DataSanityTablesList_70_objects table
 *    FIXED: Now matching against Fake_Data column instead of Fake_DataType
 *    FIXED: .invalid suffix only for email fields, ROW_NUMBER cycling approach
 *    FIXED: LEFT function error with proper column size validation
 *    FIXED: Enhanced cleanup to prevent RowNum column from appearing
 *    OPTIMIZED: Enhanced error handling, performance improvements, better cleanup
*/

-- Create tables to track processing results
IF OBJECT_ID('tempdb..#ProcessedObjects') IS NOT NULL
    DROP TABLE #ProcessedObjects;
CREATE TABLE #ProcessedObjects (
    ObjectAPI NVARCHAR(255),
    Status NVARCHAR(50),
    ProcessedDate DATETIME DEFAULT GETDATE(),
    ErrorMessage NVARCHAR(MAX)
);

IF OBJECT_ID('tempdb..#FieldProcessingResults') IS NOT NULL
    DROP TABLE #FieldProcessingResults;
CREATE TABLE #FieldProcessingResults (
    ObjectAPI NVARCHAR(255),
    FieldAPI NVARCHAR(255),
    Status NVARCHAR(50),
    ProcessedDate DATETIME DEFAULT GETDATE(),
    ErrorMessage NVARCHAR(MAX)
);

--------------------------------------------
-- TEST: Process only ONE specific ObjectAPI
--------------------------------------------
-- CHANGE THIS VALUE TO TEST WITH A DIFFERENT OBJECT
DECLARE @ObjectAPI NVARCHAR(255) = 'Application_Document__c'; -- Testing with Application_Document__c object

DECLARE @sql NVARCHAR(MAX);
DECLARE @fieldList NVARCHAR(MAX);
DECLARE @ObjectStatus NVARCHAR(50) = 'SUCCESS'; -- Track overall object status

-- Verify the test object exists in your table
IF NOT EXISTS (SELECT 1 FROM DataSanityTablesList_70_objects WHERE ObjectAPI = @ObjectAPI)
BEGIN
    PRINT 'ERROR: Test ObjectAPI ''' + @ObjectAPI + ''' not found in DataSanityTablesList_70_objects table';
    PRINT 'Available ObjectAPIs:';
    SELECT DISTINCT ObjectAPI FROM DataSanityTablesList_70_objects;
    RETURN;
END

PRINT 'TESTING WITH OBJECT: ' + @ObjectAPI;
PRINT 'Fields to be processed:';
SELECT FieldAPI, Fake_DataType, Fake_Data 
FROM DataSanityTablesList_70_objects 
WHERE ObjectAPI = @ObjectAPI;

--------------------------------------------
-- SECTION 1: Drop & Create Table for this ObjectAPI
--------------------------------------------
PRINT 'Executing SECTION 1: Creating tables for ' + @ObjectAPI;
SET @sql = N'
    DROP TABLE IF EXISTS dbo.' + @ObjectAPI + '_Append_Invalid_SOQL;
    DROP TABLE IF EXISTS dbo.' + @ObjectAPI + '_Append_Invalid;
    CREATE TABLE dbo.' + @ObjectAPI + '_Append_Invalid_SOQL (
        SOQL NVARCHAR(MAX)
    );';
EXEC sp_executesql @sql;
PRINT 'SECTION 1 completed successfully';
-- End SECTION 1

--------------------------------------------
-- SECTION 2: Build the comma-separated FieldAPI list and INSERT the SOQL
--------------------------------------------
PRINT 'Executing SECTION 2: Building SOQL for ' + @ObjectAPI;
-- Build a string like: FieldAPI1, FieldAPI2, ... for this ObjectAPI
SELECT @fieldList = STUFF((
     SELECT ', ' + FieldAPI
     FROM (
         SELECT DISTINCT FieldAPI
         FROM DataSanityTablesList_70_objects
         WHERE ObjectAPI = @ObjectAPI
     ) AS t
     FOR XML PATH(''), TYPE
).value('.', 'NVARCHAR(MAX)'),1,2,'');

PRINT 'Field list: ' + @fieldList;

SET @sql = N'
    INSERT INTO dbo.' + @ObjectAPI + '_Append_Invalid_SOQL
    VALUES(''SELECT Id, ' + @fieldList + ' from ' + @ObjectAPI + ''')';
EXEC sp_executesql @sql;
PRINT 'SECTION 2 completed successfully';
-- End SECTION 2

--------------------------------------------
-- SECTION 3: Execute the bulk SOQL procedure for this ObjectAPI
--------------------------------------------
PRINT 'Executing SECTION 3: Running SF_BulkSOQL for ' + @ObjectAPI;
SET @sql = N'EXEC SF_BulkSOQL ''R3PERF'', ''' + @ObjectAPI + '_Append_Invalid''';
EXEC sp_executesql @sql;
PRINT 'SECTION 3 completed successfully';
-- End SECTION 3

--------------------------------------------
-- SECTION 4: Create backup table and update fields with fake data (FIXED VERSION)
--------------------------------------------
PRINT 'Executing SECTION 4: Creating backup and updating fields with fake data for ' + @ObjectAPI;

-- Create backup table first
SET @sql = N'
    DROP TABLE IF EXISTS dbo.' + @ObjectAPI + '_Backup;
    SELECT * INTO dbo.' + @ObjectAPI + '_Backup 
    FROM dbo.' + @ObjectAPI + '_Append_Invalid;';
EXEC sp_executesql @sql;
PRINT 'Backup table created: ' + @ObjectAPI + '_Backup';

-- Check if RowNum column already exists and remove it
IF EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = @ObjectAPI + '_Append_Invalid' 
    AND COLUMN_NAME = 'RowNum'
)
BEGIN
    PRINT 'WARNING: RowNum column already exists in the table!';
    PRINT 'Removing existing RowNum column first...';
    
    SET @sql = N'
        ALTER TABLE dbo.' + @ObjectAPI + '_Append_Invalid 
        DROP COLUMN RowNum;';
    EXEC sp_executesql @sql;
    PRINT 'Existing RowNum column removed';
END

-- Add RowNum column for cycling through fake data (with error handling)
BEGIN TRY
    SET @sql = N'
        ALTER TABLE dbo.' + @ObjectAPI + '_Append_Invalid 
        ADD RowNum INT IDENTITY(1,1);';
    EXEC sp_executesql @sql;
    PRINT 'RowNum column added for cycling';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 2705 -- Column already exists
    BEGIN
        PRINT 'RowNum column already exists, skipping creation';
    END
    ELSE
    BEGIN
        PRINT 'ERROR adding RowNum column: ' + ERROR_MESSAGE();
        THROW;
    END
END CATCH

-- Create performance index
SET @sql = N'
    CREATE NONCLUSTERED INDEX IX_' + @ObjectAPI + '_RowNum 
    ON dbo.' + @ObjectAPI + '_Append_Invalid (RowNum);';
EXEC sp_executesql @sql;
PRINT 'Performance index created';

-- Get counts and validate data
DECLARE @FakeNameCount INT, @FakeAddressCount INT, @TotalRows INT, @TotalFields INT;
SELECT @FakeNameCount = COUNT(*) FROM FakeNameTable;
SELECT @FakeAddressCount = COUNT(*) FROM FakeAddressTable;
SELECT @TotalRows = COUNT(*) FROM dbo.Application_Document__c_Append_Invalid;
SELECT @TotalFields = COUNT(DISTINCT FieldAPI) FROM DataSanityTablesList_70_objects WHERE ObjectAPI = @ObjectAPI;

PRINT 'FakeNameTable has ' + CAST(@FakeNameCount AS VARCHAR(10)) + ' records';
PRINT 'FakeAddressTable has ' + CAST(@FakeAddressCount AS VARCHAR(10)) + ' records';
PRINT 'Total rows to process: ' + CAST(@TotalRows AS VARCHAR(10));
PRINT 'Total fields to process: ' + CAST(@TotalFields AS VARCHAR(10));

-- Performance warning for large datasets
IF @TotalRows > 10000
    PRINT 'WARNING: Large dataset detected. Processing may take longer.';

-- Process each field with ROW_NUMBER cycling approach
DECLARE @Field NVARCHAR(255);
DECLARE @FakeDataType NVARCHAR(255);
DECLARE @FakeData NVARCHAR(255);
DECLARE @ColumnSize INT;
DECLARE @ErrorCount INT = 0;
DECLARE @SuccessCount INT = 0;

DECLARE fieldCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT FieldAPI, Fake_DataType, Fake_Data
    FROM DataSanityTablesList_70_objects
    WHERE ObjectAPI = @ObjectAPI;
OPEN fieldCursor;
FETCH NEXT FROM fieldCursor INTO @Field, @FakeDataType, @FakeData;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Processing field: ' + @Field + ' with type: ' + @FakeDataType + ' and data: ' + @FakeData;
    
    BEGIN TRY
        -- Get the actual column size for this field with proper validation
        SELECT @ColumnSize = CHARACTER_MAXIMUM_LENGTH
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = @ObjectAPI + '_Append_Invalid'
        AND COLUMN_NAME = @Field;
        
        -- FIXED: Proper validation for column size
        IF @ColumnSize IS NULL OR @ColumnSize <= 0
        BEGIN
            -- For MAX columns or unknown sizes, use a reasonable default
            SET @ColumnSize = 1000;
            PRINT 'Column ' + @Field + ' has unknown size, using default: ' + CAST(@ColumnSize AS VARCHAR(10));
        END
        ELSE
        BEGIN
            PRINT 'Column ' + @Field + ' has size: ' + CAST(@ColumnSize AS VARCHAR(10));
        END
        
        -- Build the appropriate UPDATE statement with ROW_NUMBER cycling
        IF @FakeData = 'FakeName: Name'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.Name, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        Name
                    FROM FakeNameTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeNameCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeName: FirstName'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.FirstName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        FirstName
                    FROM FakeNameTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeNameCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeName: MiddleName'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.MiddleName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        MiddleName
                    FROM FakeNameTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeNameCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeName: Lastname'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.LastName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        LastName
                    FROM FakeNameTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeNameCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeName: CodeName'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.CodeName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        CodeName
                    FROM FakeNameTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeNameCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeAddress: Address'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.FakeFullAddress, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        FakeFullAddress
                    FROM FakeAddressTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeAddressCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeAddress: Street'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.FakeStreetName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        FakeStreetName
                    FROM FakeAddressTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeAddressCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeAddress: StreetNumber'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.FakeStreetNumber, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        FakeStreetNumber
                    FROM FakeAddressTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeAddressCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeAddress: AttentionName'
        BEGIN
            SET @sql = N'
                UPDATE t1 
                SET ' + @Field + ' = LEFT(t2.FakeAttentionName, ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                FROM dbo.' + @ObjectAPI + '_Append_Invalid t1
                INNER JOIN (
                    SELECT 
                        ROW_NUMBER() OVER (ORDER BY Id) as rn,
                        FakeAttentionName
                    FROM FakeAddressTable
                ) t2 ON ((t1.RowNum - 1) % ' + CAST(@FakeAddressCount AS VARCHAR(10)) + ') + 1 = t2.rn
                WHERE t1.' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeEmail: Email'
        BEGIN
            -- Only email fields get .invalid suffix
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(CONCAT(''fakedata@fake.com'', ''.invalid''), ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakePhone: Phone'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''999-999-9999'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeText: Text'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''Loreum Ipsum'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeSSN: SSN'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''111-11-1111'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeSSN: SSN4 Digits'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''1111'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeData: AccountNumber'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''1122334455'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE IF @FakeData = 'FakeData: RoutingNumber'
        BEGIN
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''333555888'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
        END
        ELSE
        BEGIN
            -- Default case for any unmapped types
            SET @sql = N'UPDATE dbo.' + @ObjectAPI + '_Append_Invalid 
                        SET ' + @Field + ' = LEFT(''FakeData'', ' + CAST(@ColumnSize AS VARCHAR(10)) + ')
                        WHERE ' + @Field + ' IS NOT NULL;';
            PRINT 'WARNING: Using default fake data for unmapped Fake_Data: ' + @FakeData;
        END
        
        -- Execute the update
        EXEC sp_executesql @sql;
        
        -- Log success and update counters
        INSERT INTO #FieldProcessingResults (ObjectAPI, FieldAPI, Status, ErrorMessage)
        VALUES (@ObjectAPI, @Field, 'SUCCESS', 'Field updated successfully');
        
        SET @SuccessCount = @SuccessCount + 1;
        PRINT 'Field ' + @Field + ' updated successfully';
        PRINT 'Progress: ' + CAST(@SuccessCount AS VARCHAR(10)) + '/' + CAST(@TotalFields AS VARCHAR(10)) + ' fields completed';
        
    END TRY
    BEGIN CATCH
        -- Log error and set object status to failure
        INSERT INTO #FieldProcessingResults (ObjectAPI, FieldAPI, Status, ErrorMessage)
        VALUES (@ObjectAPI, @Field, 'ERROR', ERROR_MESSAGE());
        
        SET @ObjectStatus = 'FAILED';
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'ERROR updating field ' + @Field + ': ' + ERROR_MESSAGE();
        PRINT 'SQL that failed: ' + @sql;
    END CATCH
    
    FETCH NEXT FROM fieldCursor INTO @Field, @FakeDataType, @FakeData;
END
CLOSE fieldCursor;
DEALLOCATE fieldCursor;

-- Enhanced cleanup with better error handling
PRINT 'Starting cleanup process...';

-- First, try to drop the performance index
BEGIN TRY
    SET @sql = N'
        DROP INDEX IF EXISTS IX_' + @ObjectAPI + '_RowNum 
        ON dbo.' + @ObjectAPI + '_Append_Invalid;';
    EXEC sp_executesql @sql;
    PRINT 'Performance index removed successfully';
END TRY
BEGIN CATCH
    PRINT 'WARNING: Could not remove performance index: ' + ERROR_MESSAGE();
END CATCH

-- Then, remove the RowNum column with multiple attempts
DECLARE @CleanupAttempts INT = 0;
DECLARE @MaxAttempts INT = 3;
DECLARE @CleanupSuccess BIT = 0;

WHILE @CleanupAttempts < @MaxAttempts AND @CleanupSuccess = 0
BEGIN
    SET @CleanupAttempts = @CleanupAttempts + 1;
    PRINT 'Cleanup attempt ' + CAST(@CleanupAttempts AS VARCHAR(2)) + ' of ' + CAST(@MaxAttempts AS VARCHAR(2));
    
    BEGIN TRY
        SET @sql = N'
            ALTER TABLE dbo.' + @ObjectAPI + '_Append_Invalid 
            DROP COLUMN RowNum;';
        EXEC sp_executesql @sql;
        PRINT 'RowNum column removed successfully on attempt ' + CAST(@CleanupAttempts AS VARCHAR(2));
        SET @CleanupSuccess = 1;
    END TRY
    BEGIN CATCH
        PRINT 'Attempt ' + CAST(@CleanupAttempts AS VARCHAR(2)) + ' failed: ' + ERROR_MESSAGE();
        
        IF @CleanupAttempts = @MaxAttempts
        BEGIN
            PRINT 'ERROR: Could not remove RowNum column after ' + CAST(@MaxAttempts AS VARCHAR(2)) + ' attempts';
            PRINT 'You may need to manually remove the RowNum column from the table';
        END
        ELSE
        BEGIN
            -- Wait a moment before retry
            WAITFOR DELAY '00:00:01';
        END
    END CATCH
END

-- Verify the column was removed
IF EXISTS (
    SELECT 1 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = @ObjectAPI + '_Append_Invalid' 
    AND COLUMN_NAME = 'RowNum'
)
BEGIN
    PRINT 'WARNING: RowNum column still exists in the table!';
    PRINT 'You may need to manually run: ALTER TABLE dbo.' + @ObjectAPI + '_Append_Invalid DROP COLUMN RowNum;';
END
ELSE
BEGIN
    PRINT 'SUCCESS: RowNum column has been completely removed';
END

-- Log overall object processing result
INSERT INTO #ProcessedObjects (ObjectAPI, Status, ErrorMessage)
VALUES (@ObjectAPI, @ObjectStatus, 'All fields processed');

PRINT 'SECTION 4 completed successfully';
PRINT 'Summary: ' + CAST(@SuccessCount AS VARCHAR(10)) + ' successful, ' + CAST(@ErrorCount AS VARCHAR(10)) + ' errors';
-- End SECTION 4

--------------------------------------------
-- SECTION 5: Display Results
--------------------------------------------
PRINT '=== PROCESSING RESULTS ===';
PRINT 'Object: ' + @ObjectAPI;
PRINT 'Status: ' + @ObjectStatus;
PRINT '';

-- Show field-level results
PRINT 'Field Processing Results:';
SELECT 
    FieldAPI,
    Status,
    ErrorMessage
FROM #FieldProcessingResults
WHERE ObjectAPI = @ObjectAPI;

-- Show summary
PRINT '';
PRINT 'Summary:';
SELECT 
    Status,
    COUNT(*) as FieldCount
FROM #FieldProcessingResults
WHERE ObjectAPI = @ObjectAPI
GROUP BY Status;

PRINT '';
PRINT 'Backup table created: ' + @ObjectAPI + '_Backup';
PRINT 'Updated table: ' + @ObjectAPI + '_Append_Invalid';
PRINT '=== END RESULTS ===';

--------------------------------------------
-- SECTION 6:
--------------------------------------------

IF @ObjectStatus = 'SUCCESS'
BEGIN
    PRINT '========================================';
    PRINT 'EXECUTING SECTION 6: Updating Salesforce for ' + @ObjectAPI;
    PRINT '========================================';
    SET @sql = N'EXEC SF_BulkOps ''Update:BulkAPI'',''R3PERF'',''' + @ObjectAPI + '_Append_Invalid''';
    EXEC sp_executesql @sql;
    PRINT 'Salesforce update completed for object: ' + @ObjectAPI;
END
ELSE
BEGIN
    PRINT 'SKIPPING SECTION 6: Object ' + @ObjectAPI + ' had failures - not updating Salesforce';
END


-- End SECTION 6



