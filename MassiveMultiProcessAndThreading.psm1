$here = Split-Path -Parent $MyInvocation.MyCommand.Path

#locate the helper functions
$Command = "$here\HelperFunctions\MultySub.ps1"
$Code = [ScriptBlock]::Create($(Get-Content $Command -raw))

class OoPSyncronizedHandles {
    $Process = {}
    $PSCode = {}

    OoPSyncronizedHandles($_Process, $_PSCode) {
        $this.Process = $_Process
        $this.PSCode = $_PSCode
    }

}

function Invoke-MultyProcess {
    [CmdletBinding()]
    param(
        [string]$Path = $(Throw 'Path is required'),

        <# the following get fowarded#>
        [System.Collections.ArrayList]$ObjectList = $(Throw 'ObjectList is required'),
        [int]$SleepTimer = 200,
        [int]$MaxResultTime = 3600
        #[string]$InputParam = $(Throw 'InputParam is required')

    )

    [System.Collections.ArrayList]$Processes = @()

    #note the starting time
    $StartTime = [DateTime]::Now
    write-verbose "Start time : $StartTime"

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
        $PSRunspace.AddParameter("ProcessIndex", $ProcessIndex) | out-null
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
        $SingleProc.Process.OpenAsync() | out-null
    }

    #now wait for all to be opened
    Write-Verbose "Waiting for processes to be ready. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
    foreach($SingleProc in $Processes) {
        while ($SingleProc.Process.RunspaceStateInfo.State -ne [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
            Write-Verbose "Still waiting for processes to be ready. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
            Start-Sleep -Milliseconds $SleepTimer       #wait for the ps seession to be created
        }
    }

    #finally start the processing
    Write-Verbose "Starting Execution. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
    foreach($SingleProc in $Processes) {
        $SingleProc.PSCode.BeginInvoke()  | out-null #async

    }


    #wait for it to complete, or wait for timeout ($MaxResultTime)
    do {
        Write-Verbose "Waiting for Execution completion. Current run time: $(([DateTime]::Now).Subtract($StartTime))"
        $StillRunning = $False

        foreach($SingleProc in $Processes) {
            if ($SingleProc.Process.RunspaceStateInfo.State -eq [System.Management.Automation.Runspaces.RunspaceState]::Opened) {
                $StillRunning = $true
                Start-Sleep -Milliseconds $SleepTimer
                break;
            }
        }
    } while ($StillRunning -eq $True -and $StartTime.AddSeconds($MaxResultTime) -ge [DateTime]::Now)

    Write-Verbose "Execution complete. Run time: $(([DateTime]::Now).Subtract($StartTime))"
}

export-modulemember -function Invoke-MultyProcess