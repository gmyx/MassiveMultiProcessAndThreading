[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "", Justification="Global Vars cannot be avoided in module testing")]
Param()

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:exePath = $here

remove-module MultyProcessing -ErrorAction Ignore
Import-Module -Name $here\MultiProcessing.psm1 -force

InModuleScope MultiProcessing {
    Describe "OoPSyncronizedHandles Class" {
        Context "Param validations" {
            It "Throws an error on ::New if 0 params supplied" {
                {[OoPSyncronizedHandles]::New()} | Should -Throw 'Cannot find an overload for "new" and the argument count: "0".'
            }

            It "Throws an error on ::New if 1 params supplied" {
                {[OoPSyncronizedHandles]::New(1)} | Should -Throw 'Cannot find an overload for "new" and the argument count: "1".'
            }

            It "Doesn't throw an error on ::New if 2 params supplied" {
                {[OoPSyncronizedHandles]::New(1, $null)} | Should -Not -Throw
            }
        }
        Context "Returns values" {
            It "Returns an OoPSyncronizedHandles object" {
                ([OoPSyncronizedHandles]::New(1, $null)).GetType().ToString() | Should -Be "OoPSyncronizedHandles"
            }
            It "Returns an object with the correct values" {
                $Process = 1
                $PSCode = 10
                $Item = [OoPSyncronizedHandles]::New($Process, $PSCode)
                $Item.Process | Should -Be $Process
                $Item.PSCode | Should -Be $PSCode
            }
        }
    }
    Describe "Invoke-MultiProcessing function" {
        [System.Collections.ArrayList]$List = @()
        $List.Add("1") | Out-Null

        Context "Param validations" {
            It "Throws an error if Path is missing" {
                {Invoke-MultiProcessing} | Should -Throw 'Path is required'
            }
            It "Throws an error if ParameterToForward is missing" {
                {Invoke-MultiProcessing -Path "Invalid"} | Should -Throw 'ParameterToForward is required'
            }
            It "Throws an error if ObjectList is missing" {
                {Invoke-MultiProcessing -Path "Invalid" -ParameterToForward "Param"} | Should -Throw 'ObjectList is required'
            }
            It "Throw an error if Path is invalid" {
                {Invoke-MultiProcessing -Path "Invalid" -ObjectList $List} | Should -Throw 'Path is invalid'
            }
        }
        <#Context "" {

        }#>
    }
}