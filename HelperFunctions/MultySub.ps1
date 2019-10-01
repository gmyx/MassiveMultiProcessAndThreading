#Middle man code that run in the seperate PS process
[CmdletBinding()]
param(
    [string]$Path,
    [string]$ParameterToForward,
    [string]$ExecutingFrom,
    [object]$SingleObject,
    [string]$TranscriptPath = $null
)

$AbortStatus = $false

if ($TranscriptPath -ne $null) {
    start-transcript "$TranscriptPath\$SingleObject.log"
}

write-verbose "Creating PS Object"
$PSCode = [powershell]::Create().AddScript($(Get-Content $Path -raw))
$PSCode.AddParameter($ParameterToForward,$SingleObject)
$PSCode.AddParameter("ExecutingFrom", $ExecutingFrom) | out-null

write-verbose "Executing From $ExecutingFrom"

#Foward verbose to code
if ($VerbosePreference -eq "Continue") {
    write-verbose "Verbosity enabled"
    $PSCode.AddParameter("Verbose") | out-null
}

#Foward TranscriptPath, if specified
if ($TranscriptPath -ne $null) {
    $PSCode.AddParameter("TranscriptPath",$TranscriptPath)
}

write-verbose "Invoking PSCode"
#$PSCode.BeginInvoke()
$PSCode.Invoke()

#clean up
if ($TranscriptPath -ne $null) {
    Stop-Transcript
}

#required to kill the current PS Process
[Environment]::Exit(0)