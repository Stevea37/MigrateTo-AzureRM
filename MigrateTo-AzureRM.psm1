function MigrateTo-AzureRM {
     <# 
             .SYNOPSIS 
             Migrates Azure Classic Virtual Networks, and all dependent resources to Resource Manager. 
  
  
             .DESCRIPTION 
             Running this command will allow you to migrate a Virtual Network, and the resources within it to Resource Manager. 
  
             If you choose not to specify subscription ID's, a Virtual Network Name, Credentials, etc. you will be provided with an interface via the command line. 
     
             .PARAMETER AzureCredentials 
             You can pass in a credential object to use to sign in to Azure. 
             
             
             .PARAMETER RMSubscriptionId 
             Used to specify the ID of the subscription you want to migrate your Virtual Network and it's resources to. 
             
             
             
             .PARAMETER ClassicSubscriptionId 
             Used to specify the ID of the subscription where your Classic resources are located. 
             
             
             
             .PARAMETER VirtualNetworkName 
             Specify the name of the classic Virtual Network you would like to migrate. 
  
              
             .PARAMETER AllVirtualNetworks
             Specify this switch to migrate all virtual networks in the classic subscription.


             .PARAMETER Force 
             Specify this switch to automatically choose "yes" when committing the migration after the migration preparation. 
  
  
             .EXAMPLE 
                      The following example will run the function silently: 
             
             $c = Get-Credential 
             MigrateTo-AzureRM -AzureCredentials $c ` 
                               -RMSubscriptionId e87ec6e6-874c-4295-9ba2-17ddb4bfd911 ` 
                               -ClassicSubscriptionId e87ec6e6-874c-4295-9ba2-17ddb4bfd911 ` 
                               -VirtualNetworkName MIG-VNet ` 
                               -Force 
  
             .EXAMPLE 
             If you are unsure of what information to pass in to the cmdlet, the following example will provide an interactive interface for the user to provide input: 
  
             MigrateTo-AzureVM 
  
             #>
    [CmdletBinding()]
    param(
        [System.Management.Automation.PSCredential]$AzureCredentials = (Get-Credential -Message "Please enter Azure credentials"),
        [string]$RMSubscriptionId,
        [string]$ClassicSubscriptionId,
        [string][parameter(ParameterSetName="SpecifyNetwork")]$VirtualNetworkName,
        [switch][parameter(ParameterSetName="AllNetworks")]$AllVirtualNetworks,
        [switch]$Force
    
    )



    #--------------------------------------------------------------------------------------------------------------------------------------
    # Prepare for Migration
    #--------------------------------------------------------------------------------------------------------------------------------------
    Start-Transcript -Path "$env:temp\MigrateTo-AzureRM\$(Get-Date -Format YYmmddHHmmss).log"
    
    if ((Get-Module Azure,AzureRM -ListAvailable).Count -lt 2)
    {
       Write-Error "Make sure you have the Azure & AzureVM modules installed on your workstation, along with their sub-modules. For more informatiom, visit https://github.com/Azure/azure-powershell."
       break
    }
    elseif ((Get-Module Azure,AzureRM).Count -lt 2)
    {
        Import-Module Azure,AzureRM -ErrorVariable FailedToLoad
        if ($FailedToLoad)
        {
            Write-Error "The modules Azure & AzureRM could not be imported."
            break
        }
    }

    Clear-AzureProfile -Force

    #--------------------------------------------------------------------------------------------------------------------------------------
    # Azure RM Login
    #--------------------------------------------------------------------------------------------------------------------------------------

    try
    {
        $loggingin = Login-AzureRmAccount -Credential $AzureCredentials
        Write-Host " "
        Write-Host " "
        Write-Host "Logged into tenant $($loggingin.Context.Tenant) using login $($loggingin.Context.Account)" -ForegroundColor Green
    }
    catch
    {
        Write-Host $Error[0].Exception.Message -ForegroundColor Red
        break
    }

    if ($RMSubscriptionId)
    {
        $RMSubID = $RMSubscriptionId
       
        try
        {
            Select-AzureRmSubscription -SubscriptionId $RMSubID | Out-Null
        }
        catch
        {
            Write-Error "The Azure RM Subscription ID you provided is invalid. Please verify the ID is correct, or specify the function without the `"-RMSubscriptionID`" parameter."
            break
        }

    }
    else
    {
        $Subscriptions = Get-AzureRmSubscription -WarningAction SilentlyContinue

        if ($Subscriptions.Count -eq 1)
        {
            Select-AzureRmSubscription -SubscriptionId $Subscriptions.SubscriptionId | out-null
            $RMSubID = $Subscriptions.SubscriptionId
        }

        elseif ($Subscriptions.Count -gt 1)
        {

            $SubNum = 1
            Write-host " "
            Write-host "Please choose the Subscription for AZURE RESOURCE MANAGER" -ForegroundColor Yellow
            Write-host "---------------------------------------------------------" -ForegroundColor Yellow
            
            foreach ($Subscription in $Subscriptions)
            {
                Write-host "$($SubNum): " -ForegroundColor Green -NoNewline
                Write-host "$($Subscription.SubscriptionName) ($($Subscription.SubscriptionId))" -ForegroundColor Yellow
                $SubNum++
            }

            Write-host " "
            do
            {
                Write-Host "You have more than one subscription, please enter the number of the subscription you wish to use:" -ForegroundColor Yellow
                $SubOption = Read-host

                if (($SubOption -gt $SubNum) -or ($SubOption -eq 0))
                {
                    Write-Host "That number does not correlate to any of your subscriptions!" -ForegroundColor Red
                }

            } while (($SubOption -gt $SubNum) -or ($SubOption -eq 0))

            Write-host "Using Azure Subscription: $($Subscriptions[($SubOption - 1)].SubscriptionName)" -ForegroundColor Green
            Select-AzureRmSubscription -SubscriptionId $($Subscriptions[($SubOption - 1)].SubscriptionId) | out-null
            $RMSubID = $($Subscriptions[($SubOption - 1)].SubscriptionId)
        }
        else
        {
            Write-Error "You have no Subscriptions"
            break   
        }

    }


    #--------------------------------------------------------------------------------------------------------------------------------------
    # Azure Classic Login
    #--------------------------------------------------------------------------------------------------------------------------------------
    try
    {
        Add-AzureAccount -Credential $AzureCredentials | out-null
    }
    catch
    {
        Write-Host $Error[0].Exception.Message -ForegroundColor Red
        break
    }

    if ($ClassicSubscriptionId)
    {
        $CLSubID = $ClassicSubscriptionId

        try
        {
            Select-AzureSubscription -SubscriptionId $CLSubID | Out-Null
        }
        catch
        {
            Write-Error "The Azure Classic Subscription ID you provided is invalid. Please verify the ID is correct, or specify the function without the `"-ClassicSubscriptionID`" parameter."
            break
        }

    }
    else
    {
        $Subscriptions = Get-AzureSubscription -WarningAction SilentlyContinue

        if ($Subscriptions.Count -eq 1)
        {
            Select-AzureSubscription -SubscriptionId $Subscriptions.SubscriptionId
            $CLSubID = $Subscriptions.SubscriptionId
        }
        elseif ($Subscriptions.Count -gt 1)
        {
            $SubNum = 1
            Write-Host " "
            Write-host "Please choose the Subscription for AZURE CLASSIC" -ForegroundColor Yellow
            Write-host "------------------------------------------------" -ForegroundColor Yellow

            foreach ($Subscription in $Subscriptions)
            {
                Write-host "$($SubNum): " -ForegroundColor Green -NoNewline
                Write-host "$($Subscription.SubscriptionName) ($($Subscription.SubscriptionId))" -ForegroundColor Yellow
                $SubNum++
            }

            Write-host " "

            do
            {
                Write-Host "You have more than one subscription, please enter the number of the subscription you wish to use:" -ForegroundColor Yellow
                $SubOption = Read-host

                if (($SubOption -gt $SubNum) -or ($SubOption -eq 0))
                {
                    Write-Host "That number does not correlate to any of your subscriptions!" -ForegroundColor Red
                }
                else
                {
                    Write-host "Using Azure Subscription: $($Subscriptions[($SubOption - 1)].SubscriptionName)" -ForegroundColor Green
                    Select-AzureSubscription -SubscriptionId $($Subscriptions[($SubOption - 1)].SubscriptionId)
                    $CLSubID = $($Subscriptions[($SubOption - 1)].SubscriptionId)
                }

            } while (($SubOption -gt $SubNum) -or ($SubOption -eq 0))

        }
        else
        {
            Write-Error "You have no Subscriptions"
            break
        }
    }



    #--------------------------------------------------------------------------------------------------------------------------------------
    # Register Subscriptions to required namespace
    #--------------------------------------------------------------------------------------------------------------------------------------
    $RegisterUpdate = $false
    Write-Host " "
    Write-Host "Checking ProviderNamespace Registration for selected subscriptions..." -ForegroundColor Yellow

    foreach ($ID in ($RMSubID,$CLSubID))
    {
        Select-AzureRmSubscription -SubscriptionId $ID | Out-Null

        if (!((Get-AzureRmResourceProvider -ProviderNamespace Microsoft.ClassicInfrastructureMigrate).RegistrationState -eq "Registered"))
        {
            Register-AzureRmResourceProvider -ProviderNamespace Microsoft.ClassicInfrastructureMigrate -Force
            $RegisterUpdate = $true
        }

    }

    if ($RegisterUpdate)
    {
        Write-Host " "
        Write-Host "One or more ProvideNamespaces required registration, waiting for registration to propogate..." -ForegroundColor Yellow
        $percentage = 0.16666666666666666666666666666667

        for ($a=1; $a -lt 600; $a++)
        {
            $percentage += 0.16666666666666666666666666666667
            Write-Progress -Activity "Updating Microsoft.ClassicInfrastructureMigrate Registration..." -SecondsRemaining $(600 - $a) -PercentComplete $percentage -Status "Updating..."
            Start-Sleep 1
        }

        Write-Progress -Activity "Updating Microsoft.ClassicInfrastructureMigrate Registration..." -Completed -Status "Updated."
    }

    Select-AzureRmSubscription -SubscriptionId $RMSubID | Out-Null



    #--------------------------------------------------------------------------------------------------------------------------------------
    # Virtual Network selection
    #--------------------------------------------------------------------------------------------------------------------------------------

    $VNets = Get-AzureVNetSite
    $VirtualNetworks = $null
    if (!$VNets)
    {
        Write-Error "No Classic Virtual Networks were found under the subscription $((Get-AzureSubscription -SubscriptionId $CLSubID).SubscriptionName) ($CLSubID)"
        break
    }
    elseif ($AllVirtualNetworks)
    {
        $VirtualNetworks = $VNets.Name
    }
    elseif (($VirtualNetworkName -ne $null) -and ($VNets | ? { $_.Name -ieq $VirtualNetworkName}))
    {
        $VirtualNetworks = $VirtualNetworkName
    }
    elseif (($VirtualNetworkName -eq $null) -and ($AllVirtualNetworks -eq $null))
    {
        $VNetNum = 1
        Write-Host " "
        Write-host "Which Virtual Network would you like to migrate?" -ForegroundColor Yellow
        Write-host "------------------------------------------------" -ForegroundColor Yellow

        foreach ($VNet in $VNets)
        {
            Write-host "$($VNetNum): " -ForegroundColor Green -NoNewline
            Write-host "$($VNet.Name) ($($VNet.Location))" -ForegroundColor Yellow
            $VNetNum++
        }

        Write-host " "

        do
        {
            Write-Host "You have more than one Virtual Network, please enter the number of the Virtual Network you wish to migrate:" -ForegroundColor Yellow
            $VNetOption = Read-host

            if (($VNetOption -gt $VNetNum) -or ($VNetOption -eq 0))
            {
                Write-Host "That number does not correlate to any of your Virtual Networks!" -ForegroundColor Red
            }
            else
            {
                $VirtualNetworks = "$($VNets[($VNetOption - 1)].Name)"
            }

        } while (($VNetOption -gt $VNetNum) -or ($VNetOption -eq 0))

    }
    else
    {
        Write-Error "The Virtual Network Name you specified is not recognised."
    }



    #--------------------------------------------------------------------------------------------------------------------------------------
    # Migrate Virtual Network
    #--------------------------------------------------------------------------------------------------------------------------------------

    foreach ($VirtualNetwork in $VirtualNetworks)
    {
            Write-Host " "
            Write-host "Preparing for migration of Azure Virtual Network $VirtualNetwork..." -ForegroundColor Yellow
            Write-Host " "
            Write-Host "VERBOSE LOG" -ForegroundColor Cyan
            Move-AzureVirtualNetwork -Prepare -VirtualNetworkName $VirtualNetwork -Verbose
            Write-Host " "

            if ($?)
            {
                Write-Host "Preparation Complete." -ForegroundColor Green
            }
            else
            {
                $Error[0]
                Write-Host "Navigate to the Resource Group `'<Name of Failed Resource>-Migrated`' to view the deployment log for any failures." -ForegroundColor Red
                break
            }

    }

    do
    {

        if (!$Force)
        {
            Write-Host "The Virtual Network is now ready to be moved. Would you like to continue? (y/n)" -ForegroundColor Yellow
            $MoveOption = Read-Host 
        }
        else
        {
            $MoveOption = 'y'
        }

        if ($MoveOption -ieq "y")
        {
            Write-Host "Committing Migration..." -ForegroundColor Yellow
            Write-Host " "
            Write-Host "VERBOSE LOG" -ForegroundColor Cyan
            Move-AzureVirtualNetwork -Commit -VirtualNetworkName $($VNets[($VNetOption - 1)].Name) -Verbose
            Write-Host " "
        }
        elseif ($MoveOption -ieq "n")
        {
            Write-Host "Aborting Migration..." -ForegroundColor Yellow
            Write-Host " "
            Write-Host "VERBOSE LOG" -ForegroundColor Cyan
            Move-AzureVirtualNetwork -Abort -VirtualNetworkName $($VNets[($VNetOption - 1)].Name) -Verbose
            Write-Host " "
        }
        else
        {
            Write-Host "You did not provide a valid option!" -ForegroundColor Red
        }

    } while (($MoveOption -ine "y") -and ($MoveOption -ine "n"))
    Stop-Transcript
} 

Export-ModuleMember -Function MigrateTo-AzureRM 