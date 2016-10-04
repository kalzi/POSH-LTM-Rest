﻿Function Set-iRule 
{
    <#
        .SYNOPSIS
            Create or updates an iRule
        .DESCRIPTION
            Can create a new, and update an existing iRule.
            Removes iRule from VirtualServers and adds them back again after uploading new iRule.
            The command supports -whatif
        .PARAMETER iRuleContent
            The content of the iRule (as a string).
            Alias: iRuleContent
        .PARAMETER Partition
            The partition on the F5 to put the iRule on. The full path will be /Partition/iRuleName.
        .PARAMETER OverWrite
            Overwrite the iRule already present on F5. It will:
            - check if any VirtualServers have the iRule configured
            - remove the iRule from those VirtualServers
            - delete old and upload new iRule
            - add the iRule back to the VirtualServers.
        .EXAMPLE
            Set-iRule -name 'NameThatMakesSense' -apiAnonymous $ObjectofStrings
    #>
    [cmdletbinding(SupportsShouldProcess = $True)]
    param (
        $F5Session = $Script:F5Session,
        [Parameter(Mandatory)]
        [string]$Name,
        [Alias('apiAnonymous')]
        [Parameter(Mandatory)]
        [string]$iRuleContent,
        [string]$Partition = 'Common',
        [switch]$OverWrite
    )
    
    begin {
        Test-F5Session -F5Session ($F5Session)

        $URI = ($F5Session.BaseURL + 'rule')
    }
    
    process {
        $newitem = New-F5Item -Name $Name
        
        $kind = 'tm:ltm:rule:rulestate'
        
        $iRuleFullName = "/$Partition/$Name"
            
        $JSONBody = @{
            kind         = $kind
            name         = $newitem.Name
            fullPath     = $newitem.Name
            apiAnonymous = $iRuleContent
        }
                
        $JSONBody = $JSONBody | ConvertTo-Json -Compress
        
        #Caused by a bug in ConvertTo-Json https://windowsserver.uservoice.com/forums/301869-powershell/suggestions/11088243-provide-option-to-not-encode-html-special-characte
        #'<', '>' and ''' are replaced by ConvertTo-Json to \\u003c, \\u003e and \\u0027. The F5 API doesn't understand this. Change them back.
        $ReplaceChars = @{
            '\\u003c' = '<'
            '\\u003e' = '>'
            '\\u0027' = "'"
        }

        foreach ($Char in $ReplaceChars.GetEnumerator()) 
        {
            $JSONBody = $JSONBody -replace $Char.Key, $Char.Value
        }
        
        $iRuleonServer = Get-iRule -Name $newitem.Name -ErrorAction SilentlyContinue
        
        if ($iRuleonServer)
        {
            if ($iRuleonServer.apiAnonymous -eq $iRuleContent)
            {
                Write-Verbose -Message 'iRule on server is already in place'
                $iRulesDifferent = $false
                $true
            }
            
            else
            {
                $iRulesDifferent = $True

                if ($OverWrite)
                {
                    Write-Verbose -Message 'iRule on server is different from current version, and OverWrite flag was set. Removing the iRule from VirtualServer and adding the new one.'
                    
                    $VirtualServers = Get-VirtualServer | Where-Object -Property rules -EQ -Value $iRuleFullName
                    
                    foreach ($Virtualserver in $VirtualServers)
                    {
                        if ($pscmdlet.ShouldProcess($Virtualserver.Name, "Remove iRule $Name from VirtualServer"))
                        {
                            $Null = $Virtualserver | Remove-iRuleFromVirtualServer -iRuleName $Name
                        }
                    }
                    
                    if ($pscmdlet.ShouldProcess($F5Session.Name, "Deleting iRule $Name"))
                    {
                        $URIOldiRule = $F5Session.GetLink($iRuleonServer.selfLink)
                        Invoke-RestMethodOverride -Method DELETE -URI $URIOldiRule -Credential $F5Session.Credential
                    }
                }
                
                else
                {
                    Write-Warning -Message 'iRule on server is different from current version, set OverWrite flag to overwrite current iRule.'
                }
            }
        }
        
        if ( (-not $iRuleonServer) -or ($iRuleonServer -and $iRulesDifferent -and $OverWrite) )
        {
            if ($pscmdlet.ShouldProcess($F5Session.Name, "Uploading iRule $Name"))
            {
                Invoke-RestMethodOverride -Method POST -URI "$URI" -Credential $F5Session.Credential -Body $JSONBody -ContentType 'application/json' -AsBoolean
            }
            
            foreach ($Virtualserver in $VirtualServers)
            {
                if ($pscmdlet.ShouldProcess($Virtualserver.Name, "Add iRule $Name"))
                {
                    $Null = Get-VirtualServer -name $Virtualserver.Name | Add-iRuleToVirtualServer -iRuleName $Name
                }
            }
        }
    }
}
