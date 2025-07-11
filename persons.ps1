#####################################################
# HelloID-Conn-Prov-Source-Magister-Students
# Multiple enrollments per student are processed as contracts.
#
#####################################################

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Debugging and logging preferences
$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Convert configuration from JSON
$c = $configuration | ConvertFrom-Json

# Get configuration parameters
$baseUri = $c.BaseUrl
$username = $c.Username
$password = $c.Password
$layout = $c.Layout


# Construct Magister API URI
$uri = "$baseUri/doc?Function=GetData&Library=Data&SessionToken=$username%3B$password&Layout=$layout&Parameters=&Type=CSV&Encoding=ANSI"

# Enable debug logging based on configuration
switch ($($c.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

Write-Information "Start person import: Base URL: [$baseUri], Using username: $username"

#region functions
# Function to handle HTTP errors for better error messages
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

# Function to sort persons by period status (active, future, past) with preference for IDONDERWIJSSOORT 4 for active status
function Sort-PersonsByPeriodStatus {
    param (
        [array]$Persons
    )
    $Persons | Sort-Object @{
        Expression = {
            switch ($_.PeriodStatus.ToLower()) {
                "active" { 1 } # Active statuses
                "future" { 2 } # Future statuses
                "past"   { 3 } # Past statuses
                default  { 4 } # For unknown statuses
            }
        }
    }
}
#endregion functions

#region query persons
try {
    Write-Verbose "Querying Persons"

    $result = Invoke-WebRequest -Method GET -Uri $uri -UseBasicParsing
    $data = $result.content
    # Convert CSV data to PowerShell objects
    $persons = ConvertFrom-Csv $data -Delimiter ";"

    # Your original period classification logic (determining active, future, or past periods)
    $today = Get-Date 
    $persons | Add-Member -MemberType NoteProperty -Name "PeriodStatus" -Value "" -Force
    $persons | ForEach-Object {
        # Split academic year into start and end year
        $studyperiodStartyear = $_.studyperiod.split("/")[0]
        $studyperiodEndYear = $_.studyperiod.split("/")[1]
        # Define start and end date of study period
        $studyperiodStartDate = Get-Date "$studyperiodStartyear-08-01"
        $studyperiodEndDate = Get-Date "$studyperiodEndYear-07-31"

        # Determine period status
        if($studyperiodStartDate -gt $today) {
            $_.PeriodStatus = "future"
        }
        elseif($studyperiodStartDate -le $today -and $studyperiodEndDate -gt $today) {
            $_.PeriodStatus = "active"
        }
        elseif($studyperiodStartDate -le $today -and $studyperiodEndDate -le $today) {
            $_.PeriodStatus = "past"
        }
        else {
            Throw "error calculation" # Throw error if status cannot be calculated
        }
    }

   
    $persons = Sort-PersonsByPeriodStatus -Persons $persons
#test
      #$persons = $persons | where-object stamnr -eq '2035903' 
     #Write-Warning ($persons | ConvertTo-Json)
    # Group records per student (Stamnr)
    $studentGroups = $persons | Group-Object Stamnr
    $filteredPersons = @()

    foreach ($group in $studentGroups) {
        $mainRecord = $null
        
        # 1. First try to find an active record
        $mainRecord = $group.Group | Where-Object { $_.PeriodStatus.ToLower() -eq "active" } | Select-Object -First 1

        # 2. If no active found, look for first future record (first after earlier sorting)
        if (-not $mainRecord) {
            $mainRecord = $group.Group | Where-Object { $_.PeriodStatus.ToLower() -eq "future" } | Select-Object -First 1
        }

        # 3. If still no active record found (e.g. all are 'future' or 'past'), take first record from the (already sorted) group
        if (-not $mainRecord) {
            $mainRecord = $group.Group[0]
        }

        # Collect ALL contracts for this student, including specific mentor and education information per contract
        $allContracts = [System.Collections.ArrayList]@()
        foreach ($record in $group.Group) {
            if (![string]::IsNullOrEmpty($record.STUDYPERIOD)) {
                # Determine mentor details for THIS specific enrollment record
                # Use CMENTORCODE/NAME if available, otherwise PMENTORCODE/NAME
                $currentMentorCode = if ($record.CMENTORCODE) { $record.CMENTORCODE } else { $record.PMENTORCODE }
                $currentMentorName = if ($record.CMENTORNAME) { $record.CMENTORNAME } else { $record.PMENTORNAME }

                $contract = [PSCustomObject]@{
                    StudyPeriod        = $record.STUDYPERIOD
                    Class              = $record.CLASS
                    ProfileCode        = $record.PROFILECODE
                    ProfileDescription = $record.PROFILEDESC
                    StartDate          = $record.studiebegindatum
                    EndDate            = $record.studieeinddatum
                    Status             = $record.PeriodStatus
                    # Add specific mentor details for this contract
                    MentorCode         = $currentMentorCode
                    MentorName         = $currentMentorName
                    Location           = $record.LOCATION
                    Study              = $record.STUDY
                }
                [void]$allContracts.Add($contract)
            }
        }

        # Add all collected contracts to the main record of the student
        # The $mainRecord is now guaranteed to be the highest priority enrollment.
        $mainRecord | Add-Member -MemberType NoteProperty -Name "AllContracts" -Value $allContracts -Force
        $filteredPersons += $mainRecord
    }

    Write-Information "Successfully queried Persons. Result count: $($filteredPersons.count)"

    if ($filteredPersons.Count -eq 0) {
        throw "Empty Persons data, aborting..."
    }
}
catch {
    $ex = $PSItem
    $errorMessage = if ($ex.Exception.Response) {
        [System.IO.StreamReader]::new($ex.Exception.Response.GetResponseStream()).ReadToEnd()
    } else {
        $ex.Exception.Message
    }
    Write-Verbose "Error: $errorMessage"
    throw "Could not query Persons. Error: $errorMessage"
}
#endregion query persons

#region query enhancing and exporting person
try {
    Write-Verbose 'Enhancing and exporting person objects to HelloID'

    $processedPersons = @()
    foreach ($person in $filteredPersons) {
        # Create new object for person and copy all properties from selected main record
        # This ensures all top-level attributes (including Class, Study, Location, etc.)
        # match the values of the highest priority enrollment ($person is already the mainRecord here).

        $personOutputObject = [PSCustomObject]@{
            ExternalId         = $person.Stamnr
            DisplayName        = "$($person.FIRSTNAME) $($person.PREFIX) $($person.LASTNAME) ($($person.Stamnr))".Replace("  ", " ")
            NamingConvention   = "B"
            PersonType         = "Leerling"
            # Explicitly copy all top-level attributes from selected mainRecord ($person)
            INITIALS           = $person.INITIALS
            FIRSTNAME          = $person.FIRSTNAME
            PREFIX             = $person.PREFIX
            LASTNAME           = $person.LASTNAME
            Email              = $person.Email
            GENDER             = $person.GENDER
            BIRTHDATE          = $person.BIRTHDATE
            STREET             = $person.STREET
            HOUSENR            = $person.HOUSENR
            HOUSENRSUFIX       = $person.HOUSENRSUFIX
            POSTALCODE         = $person.POSTALCODE
            CITY               = $person.CITY
            Loginaccount_Naam  = $person."Loginaccount.Naam"
            Mobiel_nr          = $person.Mobiel_nr
            EXTERNEID          = $person.EXTERNEID
            PMENTORMAIL        = $person.PMENTORMAIL
            CMENTORMAIL        = $person.CMENTORMAIL
            PeriodStatus       = $person.PeriodStatus # Status of main record
            
            # These fields should now have the correct values from the priority enrollment
            Class              = $person.CLASS
            Study              = $person.STUDY
            STUDYPERIOD        = $person.STUDYPERIOD
            Location           = $person.LOCATION
            MentorCode         = if ($person.CMENTORCODE) { $person.CMENTORCODE } else { $person.PMENTORCODE } 
            MentorName         = if ($person.CMENTORNAME) { $person.CMENTORNAME } else { $person.PMENTORNAME }
        }

 
        # Process all contracts previously collected in AllContracts
        $contracts = [System.Collections.ArrayList]@()
        foreach ($contract in $person.AllContracts) {
            $contractObj = [PSCustomObject]@{
                # Contract ExternalId must be unique
                ExternalId         = "$($person.Stamnr)_$($contract.StudyPeriod)_$($contract.Class)_$($contract.ProfileCode)_$($contract.StartDate)"
                StartDate          = $contract.StartDate
                EndDate            = $contract.EndDate
                Class              = $contract.Class
                ProfileCode        = $contract.ProfileCode
                ProfileDescription = $contract.ProfileDescription
                Study              = $contract.Study 
                Location           = $contract.Location 
                Year               = $contract.StudyPeriod
                StudyPeriod        = $contract.StudyPeriod
                # Get MentorCode and MentorName directly from contract object
                MentorCode         = $contract.MentorCode
                MentorName         = $contract.MentorName
                ContractStatus     = $contract.Status
            }
            [void]$contracts.Add($contractObj)
        }
#Write-Warning ($contractObj | ConvertTo-Json)
        # Add processed contracts to new person output object
        $personOutputObject | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $contracts -Force
        $processedPersons += $personOutputObject
    }

   

    $output = $processedPersons | ConvertTo-Json -Depth 10
    # Replace "Loginaccount.Naam" with "Loginaccount_Naam" for JSON compatibility
    $output = $output.Replace("Loginaccount.Naam", "Loginaccount_Naam")
    Write-Output $output
    Write-Information "Successfully enhanced and exported person objects to HelloID. Result count: $($processedPersons.count)"
}
catch {
    Write-Verbose "Error enhancing persons: $($_.Exception.Message)"
    throw "Error enhancing persons: $($_.Exception.Message)"
}
#endregion query enhancing and exporting person