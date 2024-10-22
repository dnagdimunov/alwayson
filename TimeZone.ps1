Get-TimeZone -ListAvailable | Where {$_.Id -like '*Mountain*'}
Set-TimeZone -Id "Mountain Standard Time"