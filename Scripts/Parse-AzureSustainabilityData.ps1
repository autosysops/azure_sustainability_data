# Install module to extract data from PDF
Install-Module -Name ExtractPDFData -Confirm:$false -Force
Import-Module -Name ExtractPDFData -Force

# Retrieve all Sustainability Reports
$regions = Invoke-RestMethod -Uri "https://datacenters.microsoft.com/globe/data/geo/regions.json" -Method Get

# Create a folder to store the sustainability fact sheets
if (-not (Test-Path "Files")) {
    $null = New-Item -Name "Files" -Type Directory
}

# Store data
$regiondata = @()

foreach ($region in ($regions | Where-Object { ($_.sustainabilityFactsheet -ne "") -and ($_.sustainabilityFactsheet -ne $null) })) {

    # Download the factsheet
    Invoke-WebRequest -Uri "https://datacenters.microsoft.com/globe$($region.sustainabilityFactsheet)" -Method GET -OutFile (Join-Path $PSScriptRoot "..\Files\$($region.id).pdf")

    $text = Export-PDFDataTextWithLayout -Path (Join-Path $PSScriptRoot "..\Files\$($region.id).pdf") -Page 2

    $pastHeader = $false

    foreach ($line in ($text -split '\r?\n')) {
        if ($line -like "*CARBON*WATER*") {
            if (-not $pastHeader) {
                # Get the words in the header
                $inWord = $false
                $words = @()
                for ($charindex = 0; $charindex -lt $line.Length; $charindex++) {
                    if ((-not $inWord) -and ($line[$charindex] -ne " ")) {
                        $word = @{
                            start = $charindex
                        }
                        $inWord = $true
                    }

                    if ($inWord -and (($line[$charindex] -eq " ") -or ($charindex -eq ($line.Length - 1)))) {
                        $word.end = $charindex
                        $word.word = $line[($word.start)..($word.end - 1)] -join ""
                        $words += $word
                        $inWord = $false
                    }
                }

                # Get avarage distance between words
                $distances = @()
                for ($w = 0; $w -lt ($words.count - 1); $w++) {
                    $distances += $words[$w + 1].start - $words[$w].end
                }
                $padding = [System.Math]::Round(($distances | Measure-Object -Minimum).Minimum / 2, 0)

                # Create the columns
                $columns = @()
                $columns += @{
                    Name  = "Text"
                    Start = 0
                    End   = $words[0].start - ($padding + 1)
                    Text  = @()
                }

                foreach ($word in $words) {
                    $columns += @{
                        Name  = $word.word
                        Start = $word.start - $padding
                        End   = $word.end + $padding
                        Text  = @()
                    }
                }
            }

            $pastHeader = $true
        }

        if ($pastHeader) {
            # Find the texts
            $inText = $false
            $spaces = 0
            for ($charindex = 0; $charindex -lt $line.Length; $charindex++) {
                if ((-not $inText) -and ($line[$charindex] -ne " ")) {
                    $inText = $true
                    $textStart = $charindex
                }

                if ($inText) {
                    if ($line[$charindex] -eq " ") {
                        $spaces++
                    }

                    if ($line[$charindex] -ne " ") {
                        $spaces = 0
                    }
                }

                if (($spaces -gt 3) -or (($charindex -eq ($line.Length - 1)) -and $inText)) {
                    $hits = @()
                    #Write-Host "Text = $($line[($textStart..$charindex)] -join '')"
                    foreach ($column in $columns) {
                        #Write-Host "column = $($column.Name)"
                        #Write-Host "textstart = $textStart"
                        #Write-Host "column start = $($column.Start)"
                        #Write-Host "textend = $charindex"
                        #Write-Host "column end = $($column.End)"
                        if (($textStart -lt $column.Start) -and ($charindex -lt $column.Start)) {
                            $hits += @{
                                Percentage = 0
                                Column     = $column.Name
                            }
                            #Write-Host "SKIP 1"
                            continue
                        }

                        if (($textStart -gt $column.End) -and ($charindex -gt $column.End)) {
                            $hits += @{
                                Percentage = 0
                                Column     = $column.Name
                            }
                            #Write-Host "SKIP 2"
                            continue
                        }

                        $left = $column.Start - $textStart
                        $right = $charindex - $column.End

                        if ($left -lt 0) { $left = 0 }
                        if ($right -lt 0) { $right = 0 }

                        $hits += @{
                            Percentage = [System.Math]::Round((1 - (($left + $right) / ($charindex - $textStart + 1))) * 100, 0)
                            Column     = $column.Name
                        }

                        #Write-Host "Percentage = $([System.Math]::Round((1 - (($left + $right) / ($charindex - $textStart)))*100,0))"
                    }

                    $columnname = ($hits | Where-Object { $_.Percentage -eq ($hits.Percentage | Measure-Object -Maximum).Maximum }).Column
                    #Write-Host "Name HIT = $columnname"
                    $column = $columns | Where-Object { $_.Name -eq $columnname }
                    $column.text += $line[($textStart..$charindex)] -join ""
                    $inText = $false
                    $spaces = 0
                }
            }
        }
    }

    # retrieve the PUE data
    $carbondata = (($columns | Where-Object { $_.Name -eq "CARBON" }).text -join " ")
    if ($carbondata -match "(\d+(?:[,.]\d+))(.*)(\(PUE\))") {
        $pue = $matches[1]
    }
    else {
        $pue = $null
    }

    # retrieve renewable energy data
    if ($carbondata -match "(\d+%)(.*)(enewable energy coverage)") {
        $renewable = $matches[1]
    }
    else {
        $renewable = $null
    }

    # retrieve WUE data
    $waterdata = (($columns | Where-Object { $_.Name -eq "WATER" }).text -join " ")
    if ($waterdata -match "(\d+(?:[,.]\d+))(.*)(\(WUE\))") {
        $wue = $matches[1]
    }
    else {
        $wue = $null
    }

    # Store data
    $regiondata += [ordered]@{
        id     = $region.id
        carbon = [ordered]@{
            pue      = $pue
            renewable = $renewable
        }
        water  = [ordered]@{
            wue = $wue
        }
    }
}

# Remove the files folder
Remove-Item -Path "Files" -Recurse

# Output the file
$regiondata | ConvertTo-Json | Out-File (Join-Path $PSScriptRoot "..\regiondata.json")