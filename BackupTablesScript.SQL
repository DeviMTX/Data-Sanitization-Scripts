
DECLARE @SanitizeTableName NVARCHAR(256);
DECLARE @OriginalTableName NVARCHAR(256);
DECLARE @SQLStatement      NVARCHAR(MAX);

DECLARE table_backup_cursor CURSOR FOR
SELECT name
FROM   sys.tables
WHERE  name LIKE '%_Sanitize'
  AND type = 'U';     -- Ensures we only get user tables

OPEN table_backup_cursor;
FETCH NEXT FROM table_backup_cursor INTO @SanitizeTableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @OriginalTableName = REPLACE(@SanitizeTableName, '_Sanitize', '_Original');

    -- Check if the original table already exists before trying to create it
    IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = @OriginalTableName)
    BEGIN
        BEGIN TRY
            SET @SQLStatement = 'SELECT * INTO ' + QUOTENAME('dbo') + '.' + QUOTENAME(@OriginalTableName) +
                                ' FROM ' + QUOTENAME('dbo') + '.' + QUOTENAME(@SanitizeTableName) + ';';

            PRINT 'Creating backup for: ' + QUOTENAME(@SanitizeTableName) + ' -> ' + QUOTENAME(@OriginalTableName);
            EXEC sp_executesql @SQLStatement;
        END TRY
        BEGIN CATCH
            -- If an error occurs, print it and continue to the next table
            PRINT '---!!! ERROR backing up ' + QUOTENAME(@SanitizeTableName) + ': ' + ERROR_MESSAGE();
        END CATCH
    END
    ELSE
    BEGIN
        PRINT '---!!! SKIPPING ' + QUOTENAME(@SanitizeTableName) + ' because ' + QUOTENAME(@OriginalTableName) + ' already exists.';
    END

    FETCH NEXT FROM table_backup_cursor INTO @SanitizeTableName;
END;

CLOSE table_backup_cursor;
DEALLOCATE table_backup_cursor;

PRINT '=================================';
PRINT 'All backup tables processed.';
PRINT '=================================';
