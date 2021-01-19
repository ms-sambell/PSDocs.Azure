# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#
# Azure Resource Manager documentation definitions
#

# A function to break out parameters from an ARM template.
function global:GetTemplateParameter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$Path
    )
    process {
        $template = Get-Content -Path $Path -Raw | ConvertFrom-Json;
        foreach ($property in $template.parameters.PSObject.Properties) {
            $result = [PSCustomObject]@{
                Name = $property.Name
                Description = ''
                DefaultValue = $Null
                AllowedValues = $Null
            }
            if ([bool]$property.Value.PSObject.Properties['metadata'] -and [bool]$property.Value.metadata.PSObject.Properties['description']) {
                $result.Description = $property.Value.metadata.description;
            }
            if ([bool]$property.Value.PSObject.Properties['defaultValue']) {
                $result.DefaultValue = $property.Value.defaultValue;
            }
            if ([bool]$property.Value.PSObject.Properties['allowedValues']) {
                $result.AllowedValues = $property.Value.allowedValues;
            }
            $result;
        }
    }
}

# A function to create an example JSON parameter file snippet.
function global:GetTemplateExample {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$Path
    )
    process {
        if (![System.IO.Path]::IsPathRooted($Path)) {
            $Path = Join-Path -Path $PWD -ChildPath $Path;
        }
        $template = Get-Content -Path $Path -Raw | ConvertFrom-Json;
        $normalPath = $Path;
        if ($normalPath.StartsWith($PWD, [System.StringComparison]::InvariantCultureIgnoreCase)) {
            $normalPath = $Path.Substring(([String]$PWD).Length);
            $normalPath = ($normalPath -replace '\\', '/').TrimStart('/');
        }
        $baseContent = [PSCustomObject]@{
            '$schema'= "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json`#"
            contentVersion = '1.0.0.0'
            metadata = [PSCustomObject]@{
                template = $normalPath
            }
            parameters = [ordered]@{}
        }
        foreach ($property in $template.parameters.PSObject.Properties) {
            $propertyValue = $Null;
            $hasMetadata = [bool]$property.Value.PSObject.Properties['metadata'];

            if ($hasMetadata -and [bool]$property.Value.metadata.PSObject.Properties['ignore'] -and $True -eq $property.Value.metadata.ignore) {
                continue;
            }

            if ($property.Value.type -eq 'securestring') {
                $param = [PSCustomObject]@{
                    reference = [PSCustomObject]@{
                        keyVault = [PSCustomObject]@{
                            id = ''
                        }
                        secretName = ''
                    }
                };
                $baseContent.parameters[$property.Name] = $param;
                continue;
            }

            if ($hasMetadata -and [bool]$property.Value.metadata.PSObject.Properties['example'] -and $Null -ne $property.Value.metadata.example) {
                $propertyValue = $property.Value.metadata.example;
            }
            elseif ([bool]$property.Value.PSObject.Properties['defaultValue'] -and $Null -ne $property.Value.defaultValue) {
                $propertyValue = $property.Value.defaultValue;
            }
            elseif ($property.Value.type -eq 'array') {
                $propertyValue = @();
            }
            elseif ($property.Value.type -eq 'object') {
                $propertyValue = [PSCustomObject]@{};
            }
            elseif ($property.Value.type -eq 'int') {
                $propertyValue = 0;
            }
            elseif ($property.Value.type -eq 'string') {
                $propertyValue = '';
            }

            $param = [PSCustomObject]@{
                value = $propertyValue
            }
            $baseContent.parameters[$property.Name] = $param
        }
        $baseContent;
    }
}

# A function to import metadata
function global:GetTemplateMetadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$Path
    )
    process {
        $template = Get-Content -Path $Path -Raw | ConvertFrom-Json;
        if ([bool]$template.PSObject.Properties['metadata']) {
            return $template.metadata;
        }
    }
}

# A function to import outputs
function global:GetTemplateOutput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [String]$Path
    )
    process {
        $template = Get-Content -Path $Path -Raw | ConvertFrom-Json;
        foreach ($property in $template.outputs.PSObject.Properties) {
            $output = [PSCustomObject]@{
                Name = $property.Name
                Type = $property.Value.type
                Description = ''
            }
            if ([bool]$property.Value.PSObject.Properties['metadata'] -and [bool]$property.Value.metadata.PSObject.Properties['description']) {
                $output.Description = $property.Value.metadata.description
            }
            $output;
        }
    }
}

# Synopsis: A definition to generate markdown for an ARM template
Document 'README' {

    # Read JSON files
    $templatePath = $InputObject;
    $parameters = GetTemplateParameter -Path $templatePath;
    $metadata = GetTemplateMetadata -Path $templatePath;
    $outputs = GetTemplateOutput -Path $templatePath;

    # Set document title
    if ($Null -ne $metadata -and [bool]$metadata.PSObject.Properties['name']) {
        Title $metadata.name
    }
    else {
        Title $LocalizedData.DefaultTitle
    }

    # Write opening line
    if ($Null -ne $metadata -and [bool]$metadata.PSObject.Properties['description']) {
        $metadata.description
    }

    # Add table and detail for each parameter
    Section $LocalizedData.Parameters {
        $parameters | Table -Property @{ Name = $LocalizedData.ParameterName; Expression = { $_.Name }},
            @{ Name = $LocalizedData.Description; Expression = { $_.Description }}

        foreach ($parameter in $parameters) {
            Section $parameter.Name {
                $parameter.Description;

                if (![String]::IsNullOrEmpty($parameter.DefaultValue)) {
                    $LocalizedData.DefaultValue -f [String]::Concat('`', $parameter.DefaultValue, '`');
                }
                if ($Null -ne $parameter.AllowedValues -and $parameter.AllowedValues.Length -gt 0) {
                    $allowedValuesString = $parameter.AllowedValues | ForEach-Object {
                        [String]::Concat('`', $_, '`')
                    }
                    $LocalizedData.AllowedValues -f ([String]::Join(', ', $allowedValuesString));
                }
            }
        }
    }

    # Add table for outputs
    Section $LocalizedData.Outputs {
        $outputs | Table -Property @{ Name = $LocalizedData.Name; Expression = { $_.Name }},
            @{ Name = $LocalizedData.Type; Expression = { $_.Type }},
            @{ Name = $LocalizedData.Description; Expression = { $_.Description }}
    }

    # Insert snippet
    $example = GetTemplateExample -Path $templatePath;
    Section $LocalizedData.Snippets {
        $example | Code 'json'
    }
}
