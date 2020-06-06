function Get-TopProcess {
    Param($Top=5)
    Process {
        $Cores = (Get-WmiObject -class win32_processor -Property numberOfCores).numberOfCores;
        $LogicalProcessors = (Get-WmiObject –class Win32_processor -Property NumberOfLogicalProcessors).NumberOfLogicalProcessors;

        $system = Get-WmiObject win32_OperatingSystem
        $totalPhysicalMem = $system.TotalVisibleMemorySize
        $freePhysicalMem = $system.FreePhysicalMemory
        $usedPhysicalMem = $totalPhysicalMem - $freePhysicalMem
        $TotalMemoryPercent= [math]::Round(($usedPhysicalMem / $totalPhysicalMem) * 100,1)
        $results=@()
        $Process=@()
        for($i=1; $i -le 20; $i++){    
        $Proc=get-process -IncludeUserName | select ID, ProcessName,
            @{Name="Total_RAM";  Expression = {$_.WorkingSet64 / 1MB}},`
            @{Name='CPU_Usage'; Expression = { $TotalSec = (New-TimeSpan -Start $_.StartTime).TotalSeconds;  ($_.CPU * 100 / $TotalSec) /$LogicalProcessors }} |
            ? {$_.CPU_Usage -gt 0}
        $results += $Proc
        sleep -Seconds 0.5
        }
        $results | Group-Object -Property Id | ForEach-Object -Process {
            $Count=($_.Group.Count|Measure -sum).Sum
            $ProcessName = $_.Group.ProcessName
            $Id=$_.Group.Id
            $Total_RAM=((($_.Group.Total_RAM|Measure -sum).Sum)/$Count)
            $CPU_Usage=((($_.Group.CPU_Usage|Measure -sum).Sum)/$Count)

            $Process += [PSCustomObject]@{      
                Id = $Id[0]  
                ProcessName = $ProcessName[0]
                CPU_Usage = [Math]::Round($CPU_Usage,0)
                Total_RAM = [Math]::Round($Total_RAM,0)
            }
        }
  
        $TopProc=$null
        $Process | select Id,ProcessName, CPU_Usage,Total_RAM | sort CPU_Usage -Descending | select -First $Top | ForEach { 
            $TopProc = "{0}{1}(%{2})-" -f $TopProc, $_.ProcessName,$_.CPU_Usage
        }
        $TopProc.TrimEnd("-")
        $TotalProcessPercent=($Process | Measure-Object -Property CPU_Usage -Sum).Sum
        $TotalMemoryPercent
        $TotalProcessPercent
        $Resut = [PSCustomObject]@{
            ProcessList=$TopProc.TrimEnd("-")
            TotalMemoryPercent=$TotalMemoryPercent
            TotalProcessPercent=$TotalProcessPercent
        }
        Return $Resut
    }
}
while (1) {
Get-TopProcess
}
# get-process |gm
#(Get-WmiObject win32_processor).LoadPercentage
#@{Name="Time"; Expression={(get-date(get-date).ToUniversalTime() -uformat "%s")}},`
#Handles,WorkingSet, PeakPagedMemorySize,  PrivateMemorySize, VirtualMemorySize,`
#CPU, UserName, ProcessName, Path,
#@{Name="CommandLine"; Expression={ $Proc=$_.Id;(Get-WmiObject Win32_Process | ? {$_.ProcessId -EQ  $Proc}).CommandLine}},