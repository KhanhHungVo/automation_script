# $dbServer = "."
# $dbName = "sftsboasydcoredb01-ipaddress"

Param(
    [Parameter(Mandatory=$true)] [string]$dbName = '',
    [string]$dbServer = "ASWVNWKS117\SQLSERVER2014",
    [string]$userid = '',
    [string]$password = '',
    [string]$sqlPath = "C:\Users\H.VoKH\Documents\boa\DataAccess\SQL\UpdateScripts\BOALedger"
)

function NormalizeVersion($ver) 
{
    $ss = $ver.Trim().split('.')
    $major = $ss[0]
    $minor = $ss[1]

    if ($major.length -eq 1) {
        $major = "0$major"
    }
    if ($minor.length -eq 1) {
        $minor = "00$minor"
    }
    if ($minor.length -eq 2) {
        $minor = "0$minor"
    }

    return "${major}.${minor}"
}

function ExecuteSqlScriptFile($dbServer, $dbName, $fileName, $userid, $password)
{

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "" -foregroundcolor "blue"
    Write-Host "Running SQLCMD on $fileName @ $now" -foregroundcolor "blue"

    if($userid -eq '' -or $password -eq '' ){
        sqlcmd -S $dbServer -d $dbName -E -b -i $fileName
    } else {
        sqlcmd -S $dbServer -u $userid -P $password -d $dbName -E -b -i $fileName
    }
    
    if ($LastExitCode -ne 0) 
    {  
        Throw "SQLCMD FAILED processing $fileName with exit code $LastExitCode"  
    }

    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "Finished SQLCMD @ $now" -foregroundcolor "blue"
}

function ExecuteSqlScalar($dbServer, $dbName, $sql, $userid, $password)
{
    if($userid -eq '' -or $password -eq '' ){
        $cstr = "Server=$dbServer;Database=$dbName;Integrated Security=True;"
    } else {
        $cstr = "User ID=$userid;Password=$password;Initial Catalog=$dbName;Data Source=$dbServer"
    }
    Write-Host $cstr

    # $cstr = "Server=$dbServer;Database=$dbName;Integrated Security=True;"
    $cn = New-Object System.Data.SqlClient.SqlConnection($cstr)
    $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $cn)
    $cn.Open()
    $result = $cmd.ExecuteScalar()
    $cn.Close()

    return $result
}

$schemaVersionSql = "SELECT strOptionId FROM [dbo].[SystemConfigOptions] WHERE strOption = 'SchemaVersion'"

$dbVersion = ExecuteSqlScalar $dbServer $dbName $schemaVersionSql $userid $password
$currentSchemaVersion = NormalizeVersion $dbVersion

Write-Host "Current Database Schema: $currentSchemaVersion" -foregroundcolor "blue"

$finalizeScriptName = "FinaliseBOALedgerUpdate.sql"
$upgradeScriptFiles = @{}

foreach ($scriptFile in Get-ChildItem $sqlPath | where-object -FilterScript {$_.GetType().FullName -eq 'System.IO.FileInfo' -and $_.Name -ne $finalizeScriptName }) 
{
    $scriptFileVersion = NormalizeVersion $scriptFile.Name.split(' ')[0]
    if ($scriptFileVersion -ge $currentSchemaVersion) 
    {
        $upgradeScriptFiles.Add($scriptFileVersion, $scriptFile)
    }
}
if ($upgradeScriptFiles.count -eq 0) 
{
    Write-Host "Schema upgrade NOT required."  -foregroundcolor "blue"
}
else 
{
    foreach ($nvp in $upgradeScriptFiles.GetEnumerator() | sort-object Name) 
    {
        $scriptFile = $nvp.Value
        ExecuteSqlScriptFile $dbServer $dbName $scriptFile.Fullname $userid $password  
    }

    $finalizeScriptPath = "$sqlPath\$finalizeScriptName"
    if (Test-Path $finalizeScriptPath)
    {
        ExecuteSqlScriptFile $dbServer $dbName $finalizeScriptPath $userid $password 
    }

    # Last check that we are at the latest schema version
    $scriptFile = ($upgradeScriptFiles.GetEnumerator() | sort-object -Descending Name  | Select-Object -first 1).Value
    $lastestUpdateVersion = NormalizeVersion $scriptFile.Name.split(' ')[2]

    $result = ExecuteSqlScalar $dbServer $dbName $schemaVersionSql $userid $password 
    $currentSchemaVersion = NormalizeVersion $result

    if ($lastestUpdateVersion -ne $currentSchemaVersion) 
    {
        Throw "BOALedger schema has not been correctly updated from '$currentSchemaVersion' to the latest schema version '$lastestUpdateVersion'"
    }
    else
    {
        Write-Host "Latest Database Schema: $currentSchemaVersion" -foregroundcolor "blue"
    }
}