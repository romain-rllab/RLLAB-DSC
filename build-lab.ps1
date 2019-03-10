
$LocalModules = Get-ChildItem ".\Modules" -Directory
$ModulePath = "$($env:PROGRAMFILES)\WindowsPowerShell\Modules\"

$LocalModules | Foreach-Object {
    Get-Childitem (Join-Path $ModulePath $_.Name) -Filter "$($_.Name).psd1" -Recurse | % {
        import-module $_
    } 
}

Configuration DeployMyLab
{
     
    Import-DscResource -Module PSDesiredStateConfiguration,xActiveDirectory,xNetworking,xSmbShare,xDhcpServer,xComputerManagement

    Node $AllNodes.Where{$_.ServerType -eq "DC"}.NodeName
    {
        LocalConfigurationManager            
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        } 

        xIPAddress IPAddress {
            InterfaceAlias = 'Ethernet'
            IPAddress = $Node.IPAddress
            AddressFamily = 'IPV4'
        }         
            
        File NTDSFolder            
        {            
            DestinationPath = 'C:\NTDS'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }            
                    
        WindowsFeature InstallADDS             
        {             
            Ensure = "Present"             
            Name = "AD-Domain-Services"             
        }        
              
        xADDomain ADDomain             
        {             
            DomainName = $ConfigurationData.NonNodeData.DomainNameFQDN       
            DomainNetbiosName = $ConfigurationData.NonNodeData.DomainName    
            DomainAdministratorCredential = $ConfigurationData.NonNodeData.Credentials         
            SafemodeAdministratorPassword = $Node.ActiveDirectoryConfiguration.DSRMCredentials       
            DatabasePath = 'C:\NTDS'            
            LogPath = 'C:\NTDS'            
            DependsOn = "[WindowsFeature]InstallADDS","[File]NTDSFolder"            
        }

        $Node.ActiveDirectoryConfiguration.OrganizationalUnits.foreach( {
            xADOrganizationalUnit "OU=$($_.Name),$($_.Path))"
            {
                Ensure = 'Present'
                Name = $_.Name
                Path = $_.Path
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                ProtectedFromAccidentalDeletion = $true
            }
        })

        $Node.ActiveDirectoryConfiguration.Users.foreach( {
            xADUser $_.UserName
            {
                DomainName = $ConfigurationData.NonNodeData.DomainName
                Ensure = 'Present'
                Username = $_.UserName
                Path = $Node.ActiveDirectoryConfiguration.UserLocation."$($_.Type)"
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                Enabled = $true
                Password = $ConfigurationData.NonNodeData.DefaultUserCredentials
                UserPrincipalName = "$($_.Username)@$($ConfigurationData.NonNodeData.DomainNameFQDN)"
            }
        })

        $Node.ActiveDirectoryConfiguration.Computers.foreach( {
            xADComputer $_.ComputerName
            {
                
                Ensure = 'Present'
                ComputerName = $_.ComputerName
                Path = $Node.ActiveDirectoryConfiguration.ComputerLocation."$($_.Type)"
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                Enabled = $true
            }
        })

        $Node.ActiveDirectoryConfiguration.Groups.foreach( {
            xADGroup $_.GroupName
            {
                Ensure = 'Present'
                GroupName = $_.GroupName
                Category = 'Security'
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                GroupScope = $_.GroupScope
                Path = $Node.ActiveDirectoryConfiguration.GroupLocation."$($_.GroupType)"
                Description = $_.Description
                MembershipAttribute = 'SamAccountName'
                Members = $_.Members
            }
        })
        
        
    }
    Node $AllNodes.Where{$_.ServerType -eq "Member"}.NodeName
    {
        LocalConfigurationManager               
        {            
            ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'            
            RebootNodeIfNeeded = $true            
        } 

        xIPAddress IPAddress {
            InterfaceAlias = 'Ethernet'
            IPAddress = $Node.IPAddress
            AddressFamily = 'IPV4'
        }         
            
        xDefaultGatewayAddress GW
        {
            InterfaceAlias = 'Ethernet'
            AddressFamily = 'IPV4'
            Address = $Node.Gateway
            DependsOn = '[xIPAddress]IPAddress'
        }

        xDnsServerAddress DNS

        {
            InterfaceAlias = 'Ethernet'
            Address        = $Node.DNSServer
            AddressFamily  = 'IPV4'
            Validate       = $false
            DependsOn = '[xIPAddress]IPAddress'

        } 
        
        File FolderShares            
        {            
            DestinationPath = 'C:\Shares'            
            Type = 'Directory'            
            Ensure = 'Present'            
        }            

        File DSCFolder         
        {            
            DestinationPath = 'C:\Shares\DSCFolder'            
            Type = 'Directory'            
            Ensure = 'Present'        
            DependsOn = '[File]FolderShares'    
        }  

        xSmbShare DSCShare
        {
          Ensure = 'Present'
          Name   = 'Share1'
          Path = 'C:\Shares\DSCFolder'
          Description = "This is a shared folder for my lab"  
          DependsOn = '[File]DSCFolder'
        }

        xComputer NewNameAndJoinDomain
        { 
            Name          = $Node.NodeName
            DomainName = $ConfigurationData.NonNodeData.DomainNameFQDN
            Credential = $ConfigurationData.NonNodeData.Credentials
            DependsOn = '[xIPAddress]IPAddress','[xDnsServerAddress]DNS'
        }

        WindowsFeature DHCP {
            Ensure = 'Present'
            Name = 'DHCP'
            IncludeAllSubFeature = $true  
        }

        WindowsFeature RSAT-DHCP {
            Ensure = 'Present'
            Name = 'RSAT-DHCP'
        }

        WindowsFeature RSAT            
        {             
            Ensure = "Present"             
            Name = "RSAT-ADDS"             
        }  
        xDhcpServerScope DHCPLabScope {
            
            Ensure = 'Present'
            ScopeID = $Node.DHCPConfiguration.DHCPScope
            IPStartRange = $Node.DHCPConfiguration.DHCPScopeStart
            IPEndRange = $Node.DHCPConfiguration.DHCPScopeEnd
            Name = $Node.DHCPConfiguration.DHCPScopeName
            SubnetMask = '255.255.255.0'
            LeaseDuration = '00:08:00'
            State = 'Active'
            AddressFamily = 'IPv4'
        }

        xDhcpServerOption DHCPLabServerOption {
            Ensure = 'Present'
            ScopeID =  $Node.DHCPConfiguration.DHCPScope
            DnsDomain = $ConfigurationData.NonNodeData.DomainNameFQDN
            DnsServerIPAddress = $Node.DNSServer
            Router = $Node.Gateway
            AddressFamily = 'IPV4'
            DependsOn = '[xDhcpServerScope]DHCPLabScope'
        }
        
        xDhcpServerAuthorization AuthorizeDHCP
        {
            Ensure = 'Present'
            PSDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials 
            DnsName = $ConfigurationData.NonNodeData.DomainNameFQDN
            DependsOn = '[WindowsFeature]DHCP'
        }

    }
}

$ConfigData = @{

    AllNodes = 
    @(
        @{
            NodeName = "*"

        },
        @{
            NodeName = "RLLAB-CORP-DC1"
            ServerType = 'DC'
            PSDscAllowDomainUser = $true
            PsDscAllowPlainTextPassword = $true
            IPAddress = "192.168.0.1/24"

            ActiveDirectoryConfiguration = @{
                DSRMCredentials = (Get-Credential -UserName '(DSRM Password)' -Message "DSRM Password")     
                OrganizationalUnits = @(
                    #objets à la racine du domaine
                    @{
                        Name = 'CORP'
                        Path = "DC=RLLAB,DC=NET"
                        
                    },
                    @{
                        Name = 'Admin'
                        Path = "DC=RLLAB,DC=NET"
                        
                    },
                    #OUs dans la section "CORP"
                    @{
                        Name="Users"
                        Path="OU=CORP,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Servers"
                        Path="OU=CORP,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Computers"
                        Path= "OU=CORP,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Groups"
                        Path= "OU=CORP,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Rights"
                        Path= "OU=CORP,DC=RLLAB,DC=NET"
                    },
                    #OUs dans la section "Admin"
                    @{
                        Name="Services"
                        Path="OU=Admin,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Users"
                        Path="OU=Admin,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Groups"
                        Path="OU=Admin,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Rights"
                        Path="OU=Admin,DC=RLLAB,DC=NET"
                    },
                    @{
                        Name="Servers"
                        Path="OU=Admin,DC=RLLAB,DC=NET"
                    }
            
                )

                Computers = @(
                    @{
                        Type = 'Server'
                        ComputerName = 'RLLAB-CORP-SRV1'
                    },
                    @{
                        Type = 'Workstation'
                        ComputerName = 'RLLAB-CORP-WKS1'
                    }
                )
                
                Users = @(
                    @{
                        Type = 'Standard'
                        UserName = 'user1'
                                        
                    },
                    @{
                        UserName = 'sys-wks-domainjoin'
                        Type = 'Service'
                    },
                    @{
                        UserName = 'romain-adm'
                        Type = 'Admin'
                    }
                )

                Groups =  @(
                    @{
                        GroupType = 'Standard'
                        GroupName = 'GG-DSC-Readers'
                        GroupScope = 'Global'
                        Description = 'Acces en lecture sur le partage DSC'

                    },
                    @{
                        GroupType = 'StandardRights'
                        GroupName = 'LG-DSC-Readers'
                        GroupScope = 'DomainLocal'
                        Members = 'GG-DSC-Readers'
                        Description = 'Utilisateurs en lecture sur le partage DSC'
                    },
                    @{
                        GroupType = 'Secure'
                        GroupName = 'GG-WKS-Domain-Join'
                        GroupScope = 'Global'
                        Members = 'sys-wks-domainjoin'
                        Description = 'Groupe de comptes qui peuvent joindre des poste de travail au domaine'
                    },
                    @{
                        GroupType = 'SecureRights'
                        GroupName = 'LG-WKS-Domain-Join'
                        GroupScope = 'DomainLocal'
                        Members = 'GG-WKS-Domain-Join'
                        Description = 'Droit de jonction de poste de travail au domaine'

                    }
                )
                ComputerLocation = @{
                    Server = 'OU=Servers,OU=CORP,DC=RLLAB,DC=NET'
                    Workstation = 'OU=Computers,OU=CORP,DC=RLLAB,DC=NET'
                }
                GroupLocation = @{
                    Standard = 'OU=Groups,OU=CORP,DC=RLLAB,DC=NET'
                    StandardRights = 'OU=Rights,OU=CORP,DC=RLLAB,DC=NET'
                    Secure = 'OU=Groups,OU=Admin,DC=RLLAB,DC=NET'
                    SecureRights ='OU=Rights,OU=Admin,DC=RLLAB,DC=NET'
                }
                UserLocation = 
                @{
                    Service = 'OU=Services,OU=Admin,DC=RLLAB,DC=NET'
                    Admin = 'OU=Users,OU=Admin,DC=RLLAB,DC=NET'
                    Standard = 'OU=Users,OU=CORP,DC=RLLAB,DC=NET'
                }
            }
            

        },
        
        @{
            NodeName = "RLLAB-CORP-SRV1"
            ServerType = 'Member'
            PSDscAllowDomainUser = $true
            PsDscAllowPlainTextPassword = $true
            IPAddress = "192.168.0.2/24"  
            DNSServer = "192.168.0.1"   
            Gateway = "192.168.0.255"  
            DHCPConfiguration = @{
                DHCPScope = "192.168.0.0"
                DHCPScopeName = "DHCPLABScope"
                DHCPScopeStart = "192.168.0.32"
                DHCPScopeEnd = "192.168.0.64"
            }
        }
    );
    NonNodeData =  @{
        DefaultUserCredentials =  (Get-Credential -UserName "(Password Only)" -Message "Default User Credentials") 
        Credentials =  (Get-Credential -UserName "RLLAB\Administrator" -Message "Build and join Password") 
        DomainNameFQDN = "RLLAB.NET"
        DomainName = "RLLAB"
    }
}

DeployMyLab -ConfigurationData $ConfigData 
Set-DSCLocalConfigurationManager -Path .\DeployMyLab -Verbose   
Start-DscConfiguration -ComputerName $env:computername -Wait -Force -Path .\DeployMyLab -Verbose   