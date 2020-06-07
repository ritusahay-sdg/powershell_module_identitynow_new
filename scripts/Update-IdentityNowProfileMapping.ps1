function Update-IdentityNowProfileMapping {
    <#
.SYNOPSIS
Update IdentityNow Profile Attribute Mapping.

.DESCRIPTION
Update IdentityNow Profile Attribute Mapping.

.PARAMETER ID
(required) ID of the Identity Profile to update

.PARAMETER IdentityAttribute
(required) Priority value for the Identity Profile

.PARAMETER sourceType
(required) specify Null to clear the mapping, complex for setting a rule, or Standard for account attribute or account attribute with transform

.PARAMETER source
not needed for null
for account attribute specify source:accountAttribute or as a two part array
for transform specify source:accountAttribute:transform or as a three part array
for complex provide the name of the rule

.EXAMPLE
Update-IdentityNowProfileOrder -id 1285 -IdentityAttribute uid -sourceType Standard -source 'AD:SamAccountName'

.EXAMPLE
Update-IdentityNowProfileOrder -id 1285 -IdentityAttribute uid -sourceType Standard -source @('AD','SamAccountName','transform-UID')

.EXAMPLE
Update-IdentityNowProfileOrder -id 1285 -IdentityAttribute uid -sourceType Null

.EXAMPLE
Update-IdentityNowProfileOrder -id 1285 -IdentityAttribute managerDn -sourceType Complex -source 'Rule - IdentityAttribute - Get Manager'

.EXAMPLE
$idp=Get-IdentityNowProfile
$source=@('AD','samAccountName','Transform-UID')
$idp.id | foreach {Update-IdentityNowProfileMapping -ID $_ -IdentityAttribute uid -sourceType Standard -source $source; Start-IdentityNowProfileUserRefresh -id $_}

.LINK
http://darrenjrobinson.com/sailpoint-identitynow

#>

    [cmdletbinding()]
    param( 
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$ID,
        [Parameter(Mandatory = $true)]
        [string]$IdentityAttribute,
        [Parameter(Mandatory = $true)]
        [validateset('Null', 'Standard','Complex')][string]$sourceType,
        $source
        
    )

    $v3Token = Get-IdentityNowAuth

    if ($v3Token.access_token) {
        try {
            $updateProfile = Get-IdentityNowProfile -ID $id
            switch($sourceType){
                Null{$mapping=$null}
                Standard{
                    $source=$source.Split(':')
                    $idnsource=Get-IdentityNowSource
                    $idnsource=$idnsource.where{$_.name -eq $source[0]}[0]
                    if ($idnsource.count -ne 1){Write-Error "Problem getting source '$($source[0])'";exit}
                    $attributes=[pscustomobject]@{
                        applicationId=$idnsource.externalId
                        applicationName=$idnsource.health.name
                        attributeName=$source[1]
                        sourceName=$idnsource.name
                    }
                    $mapping=[pscustomobject]@{
                        attributeName=$IdentityAttribute
                        attributes=$null
                        type=$null
                    }
                    switch ($source.count){
                        2{
                            $mapping.type='accountAttribute'
                            $mapping.attributes=$attributes
                        }
                        3{
                            $mapping.type='reference'
                            $mapping.attributes=[pscustomobject]@{
                                id=$source[2]
                                input=$attributes
                            }
                        }
                        default{
                            write-error "unable to get two or three items from source parameter $($_)"
                            quit
                        }
                    }

                }
                Complex{
                    $idnrule=Get-IdentityNowRule -ID $source
                    $rule=[pscustomobject]@{
                        id=$idnrule.id
                        name=$idnrule.name
                    }
                    $mapping=[pscustomobject]@{
                        attributeName=$IdentityAttribute
                        attributes=$rule
                        type='rule'
                    }
                    if ($idnrule -eq $null){Write-Error "rule $source not found";exit}
                }
            }
            $body=[pscustomobject]@{
                id=$id
                attributeConfig=$updateprofile.attributeConfig
            }
            if ($mapping){
                if ($body.attributeConfig.attributeTransforms.attributename -contains $IdentityAttribute){
                    $index=$body.attributeConfig.attributeTransforms.attributename.IndexOf($IdentityAttribute)
                    $body.attributeConfig.attributeTransforms[$index]=$mapping
                }else{
                    $body.attributeConfig.attributeTransforms+=$mapping
                }
            }else{
                $index=$body.attributeConfig.attributeTransforms.attributename.IndexOf($IdentityAttribute)
                if ($index -ne -1){
                    $body.attributeConfig.attributeTransforms=$body.attributeConfig.attributeTransforms.where{$_.attributename -ne $identityattribute}
                }
            }
            
            $url="https://$($IdentityNowConfiguration.orgName).identitynow.com/api/profile/update/$($ID)"
            $response = Invoke-WebRequest -Uri $url -Method Post -UseBasicParsing -Body ($body | convertto-json -depth 100) -ContentType 'application/json' -Headers @{Authorization = "$($v3Token.token_type) $($v3Token.access_token)" }
            return $response
        }
        catch {
            Write-Error "update failed $($_)" 
        }
    }
    else {
        Write-Error "Authentication Failed. Check your AdminCredential and v3 API ClientID and ClientSecret. $($_)"
        return $v3Token
    } 
}
