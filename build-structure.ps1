Configuration DeployMyStructure
{
    Import-DscResource -Module xActiveDirectory

    Node $AllNodes.Where{$_.ServerType -eq "DC"}.NodeName
    {

       $Node.OrganizationalUnits.foreach( {
            xADOrganizationalUnit "OU=$($_.Name),$($_.Path))"
            {
                Ensure = 'Present'
                Name = $_.Name
                Path = $_.Path
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                ProtectedFromAccidentalDeletion = $true
            }
        })

        $Node.Users.foreach( {
            xADUser $_.UserName
            {
                DomainName = $ConfigurationData.NonNodeData.DomainName
                Ensure = 'Present'
                Username = $_.UserName
                Path = $Node.UserLocation."$($_.Type)"
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                Enabled = $true
                Password = $ConfigurationData.NonNodeData.DefaultUserCredentials
                UserPrincipalName = "$($_.Username)@$($ConfigurationData.NonNodeData.DomainNameFQDN)"
            }
        })

        $Node.Computers.foreach( {
            xADComputer $_.ComputerName
            {
                
                Ensure = 'Present'
                ComputerName = $_.ComputerName
                Path = $Node.ComputerLocation."$($_.Type)"
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                Enabled = $true
            }
        })

        $Node.Groups.foreach( {
            xADGroup $_.GroupName
            {
                Ensure = 'Present'
                GroupName = $_.GroupName
                Category = 'Security'
                PsDscRunAsCredential = $ConfigurationData.NonNodeData.Credentials
                GroupScope = $_.GroupScope
                Path = $Node.GroupLocation."$($_.GroupType)"
                Description = $_.Description
                MembershipAttribute = 'SamAccountName'
                Members = $_.Members
            }
        })

    }
    
}

$ConfigurationData = @{

    AllNodes = 
    @(
        @{ 
            NodeName = '*'
        },
        @{
            NodeName = "RLLAB-CORP-DC1"
            ServerType = 'DC'
            PSDscAllowDomainUser = $true
            PsDscAllowPlainTextPassword = $true   

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
        },
        
        @{
            NodeName = "RLLAB-CORP-SRV1"
            ServerType = 'Member'
            PSDscAllowDomainUser = $true
            PsDscAllowPlainTextPassword = $true
        }
    );
    NonNodeData =  @{
        DefaultUserCredentials =  (Get-Credential -UserName "(Password Only)" -Message "Default User Credentials") 
        Credentials =  (Get-Credential -UserName "RLLAB\Administrator" -Message "Build and join Password") 
        DomainNameFQDN = "RLLAB.NET"
        DomainName = "RLLAB"
    }
}

DeployMyStructure -ConfigurationData $ConfigurationData 
Start-DscConfiguration -ComputerName $env:computername -Wait -Force -Path .\DeployMyStructure -Verbose   