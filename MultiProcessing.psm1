$here = Split-Path -Parent $MyInvocation.MyCommand.Path

#locate the helper functions
$Command = "$here\HelperFunctions\MultySub.ps1"
$Code = [ScriptBlock]::Create($(Get-Content $Command -raw))

class OoPSyncronizedHandles {
    $Process = {}
    $PSCode = {}

    OoPSyncronizedHandles($_Process,$_PSCode) {
        $this.Process = $_Process
        $this.PSCode = $_PSCode
    }

}

function Abort-Invoke {
    param(
        [System.Collections.ArrayList]$Processes
    )

    Write-Host ""
    Write-Warning "CTRL-C was used - Shutting down any running jobs before exiting the script."

    foreach($SingleProc in $Processes) {
        #send out a abort message!
        $SingleProc.PSCode.Stop()

        #close the object
        $SingleProc.Process.CloseAsync() | out-null
    }

    [Console]::TreatControlCAsInput = $False
    Exit
}

function Test-Abort {
    param(
        [System.Collections.ArrayList]$Processes
    )
    If ($Host.UI.RawUI.KeyAvailable -and ($Key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
        If ([Int]$Key.Character -eq 3) {
            Abort-Invoke $Processes #abort abort abort!
        }
        # Flush the key buffer again for the next loop.
        $Host.UI.RawUI.FlushInputBuffer()
    }
}

function Invoke-MultiProcessing {
    [CmdletBinding()]
    param(
        [string]$Path = $(Throw 'Path is required'),
        [string]$ParameterToForward = $(Throw 'ParameterToForward is required'),

        <# the following get fowarded#>
        [System.Collections.ArrayList]$ObjectList = $(Throw 'ObjectList is required'),
        [int]$SleepTimer = 200,
        [int]$MaxResultTime = 3600,
        [string]$TranscriptPath = $null
    )

    #ensure supplied path is valid
    if ((Test-Path $Path) -eq $false) {
        Throw 'Path is invalid'
    }

    #we good, carry on!
    [System.Collections.ArrayList]$Processes = @()

    #note the starting time
    $StartTime = [DateTime]::Now
    write-verbose "Start time : $StartTime"

    # Source: https://blogs.technet.microsoft.com/dsheehan/2018/10/27/powershell-taking-control-over-ctrl-c/
    # Change the default behavior of CTRL-C so that the script can intercept and use it versus just terminating the script.
    [Console]::TreatControlCAsInput = $True
    # Sleep for 1 second and then flush the key buffer so any previously pressed keys are discarded and the loop can monitor for the use of
    #   CTRL-C. The sleep command ensures the buffer flushes correctly.
    Start-Sleep -Seconds 1
    $Host.UI.RawUI.FlushInputBuffer()

    #setup all the processes
    $ProcessCount = ($ObjectList | Measure-Object).Count
    for ($ProcessIndex=0; $ProcessIndex -lt $ProcessCount; $ProcessIndex = $ProcessIndex + 1) {
        Write-Verbose "Creating process #$ProcessIndex"

        #create a Out Of Process PS Session, attache a file that runs multiple threads "multy sub"
        $OoPPS = [runspacefactory]::CreateOutOfProcessRunspace($null)
        $OoPPS.ThreadOptions = 1

        #load in the code
        $PSRunspace = [powershell]::Create().AddScript($Code)
        $PSRunspace.Runspace = $OoPPS #OoPPS is a runspace

        #add the required params
        $PSRunspace.AddParameter("Path", $Path) | out-null
        $PSRunspace.AddParameter("ParameterToForward", $ParameterToForward) | out-null
        $PSRunspace.AddParameter("ExecutingFrom", (get-location).path) | out-null
        $PSRunspace.AddParameter("TranscriptPath", $TranscriptPath) | out-null
        $PSRunspace.AddParameter("SingleObject", $ObjectList[$ProcessIndex]) | out-null


        if ($VerbosePreference -eq "Continue") {
            Write-Verbose "Propogating Verbose to Async Code"
            $PSRunspace.AddParameter("Verbose") | out-null
        }

        #add this to the list
        $Processes.Add([OoPSyncronizedHandles]::New($OoPPS, $PSRunspace)) | out-null
    }

    #start the opening of the proceses
    Write-Verbose "Starting Processes. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
    foreach($SingleProc in $Processes) {
        Test-Abort $Processes

        $SingleProc.Process.OpenAsync() | out-null
    }

    #now wait for all to be opened
    Write-Verbose "Waiting for processes to be ready. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
    foreach($SingleProc in $Processes) {
        while ($SingleProc.Process.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
            Test-Abort $Processes

            Write-Verbose "Still waiting for processes to be ready. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
            Start-Sleep -Milliseconds $SleepTimer       #wait for the ps seession to be created
        }
    }

    #finally start the processing
    Write-Verbose "Starting Execution. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
    foreach($SingleProc in $Processes) {
        Test-Abort $Processes

        $SingleProc.PSCode.BeginInvoke()  | out-null #async

    }


    #wait for it to complete, or wait for timeout ($MaxResultTime)
    do {
        Write-Verbose "Waiting for Execution completion. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
        $StillRunning = $False

        foreach($SingleProc in $Processes) {
            Test-Abort $Processes

            if ($SingleProc.Process.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                $StillRunning = $true
                Start-Sleep -Milliseconds $SleepTimer
                break;
            }
        }
    } while ($StillRunning -eq $True -and $StartTime.AddSeconds($MaxResultTime) -ge [DateTime]::Now)

    Write-Verbose "Execution complete. Run time: $(([DateTime]::Now).Subtract($StartTime))"
}

export-modulemember -function Invoke-MultiProcessing