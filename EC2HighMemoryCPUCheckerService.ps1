############################################################################## 
## Paximum EC2 High CPU - Memory - Disk Alarm
## Created by Bora TERCAN  
## Date : 31.07.2019
## Version : 1.0
## Version : 1.1 disk alarm added 01.04.2020 
## Email: btercan@hotmail.com   
##############################################################################

$instanceid = Invoke-RestMethod 'http://169.254.169.254/latest/meta-data/instance-id'
$instanceLocalIP = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/local-ipv4
$TagName=(((Get-EC2Instance -InstanceId $instanceid).RunningInstance).Tag | Where-Object {$_.Key -like "Name"}).Value
function Measure-TopProcess {
    Param($results=@())
    Process {
        if ($results -eq $null) {
            $TopProc="-"
        } else {
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
        }
        Return $TopProc.TrimEnd("-")
    }
}
function Get-TopProcess {
    Param($Top=5,
    $LogicalProcessors = (Get-WmiObject –class Win32_processor -Property NumberOfLogicalProcessors).NumberOfLogicalProcessors)
    Process {
    $TopProc =$null
        $Proc=get-process -IncludeUserName | select ID, ProcessName,
            @{Name="Total_RAM";  Expression = {$_.WorkingSet64 / 1MB}},`
            @{Name='CPU_Usage'; Expression = { $TotalSec = (New-TimeSpan -Start $_.StartTime).TotalSeconds;  ($_.CPU * 100 / $TotalSec) /$LogicalProcessors }} |
            ? {$_.CPU_Usage -gt 0} | sort CPU_Usage -Descending | select -First $Top 
        Foreach ($P in $Proc) { 
            $TopProc = "{0}{1}(%{2})-" -f $TopProc, $P.ProcessName,[Math]::Round($P.CPU_Usage,1)
        }
        Write-Host $TopProc.TrimEnd("-")
        Return $Proc
    }
}
function Get-TopProcessOld1 {
    Param($Top=5)
    Process {
        $CpuCores = (Get-WMIObject Win32_ComputerSystem).NumberOfLogicalProcessors
        $TopProcess= ((Get-Counter "\Process(*)\% Processor Time" -ErrorAction SilentlyContinue).CounterSamples |Where-Object {$_.InstanceName -ne "_total"}| Select InstanceName, @{Name="CPU %";Expression={[Decimal]::Round(($_.CookedValue / $CpuCores), 2)}} | sort *CPU* -Descending | select -First $Top)
        $TopProc=$null
        ForEach ($Proc in $TopProcess) { $TopProc = "{0}{1}({2})-" -f $TopProc, $Proc.InstanceName, $Proc."CPU %" }
        return $TopProc.TrimEnd("-")
    }
}
while (1) {
    $TotalCPU = 0
    $TotalMemory = 0
    $AlarmStatus=""
    $AlarmIn60Sec=0
    $Logicaldisks=Get-WMIObject Win32_Logicaldisk
    $LogicaldiskSize=""
    $results=@()
    foreach ($Logicaldisk in $Logicaldisks) {
        $FreeSize=[math]::Round($Logicaldisk.Freespace/1MB)
        $LogicaldiskSize=$LogicaldiskSize+"({0}{1}GB)" -f $Logicaldisk.DeviceID, [math]::Round($FreeSize/1000,2)
        if ($FreeSize -lt 300) {
            $AlarmStatus="Disk"
            gci -File E:\log -Recurse | Where-Object {$_.LastWriteTime -le (((Get-Date).AddDays(-3).Date))} | remove-item -Force
            remove-item D:\app-* -Recurse -Force
        }
    }
    Write-Host $LogicaldiskSize
    $TotalCPU 
    for($j=1; $j -le 3; $j++){    
        $system = Get-WmiObject win32_OperatingSystem
        $totalPhysicalMem = $system.TotalVisibleMemorySize
        $freePhysicalMem = $system.FreePhysicalMemory
        $usedPhysicalMem = $totalPhysicalMem - $freePhysicalMem
        $Memory= [math]::Round(($usedPhysicalMem / $totalPhysicalMem) * 100,1)
        $CPU=0
    $TotalCPU = 0
        for($i=1; $i -le 20; $i++){    
            $CPULoad = Get-WmiObject win32_processor
            $CPU = $CPU + $CPULoad.LoadPercentage
            $Message_ = "{0}" -f ($CPULoad.LoadPercentage).ToString("#.#")
            if ($CPULoad.LoadPercentage -gt 98){$results += Get-TopProcess}
            Write-Host -f green "$i - $Message_"
        }
        $TotalCPU = $TotalCPU + $CPU
        $TotalMemory=$TotalMemory + $Memory
        $AvrgCPU = $TotalCPU / ($i -1)
        $AvrgMemory = $TotalMemory / $j
        $Time=get-date -UFormat %T
        Write-Host -f red "$j $i $TotalCPU AvgCPU    : $AvrgCPU"
        Write-Host -f red "$j  AvgMemory : $AvrgMemory"
        Write-Host -f Cyan "$j Time       : $Time"
        if ($AvrgCPU -gt 95) {$AlarmStatus="CPU"}
        if ($AvrgMemory -gt 95) {$AlarmStatus="Memory"}
        if ($AlarmStatus -ne "") {
            $AlarmIn60Sec=$AlarmIn60Sec + 1
            $TopProcess=Measure-TopProcess -results $results
            $results=@() 
            $AlarmMessage = "[PAX][High {0} Err][$TagName][$Time][Mem:%{1}/Cpu:%{2}[$TopProcess]/Disk{3}][InstanceID:{4}][LocalIP:{5}][Again:{6}]" -f $AlarmStatus, $AvrgMemory.ToString("#.#"), $AvrgCPU.ToString("#.#"), $LogicaldiskSize, $instanceid, $instanceLocalIP, $AlarmIn60Sec
            write-host "Alarm -> $AlarmMessage" -f Red
            $AlarmStatus=""                            
        }
    }
        $TopProcess=Measure-TopProcess -results $results
        $Message = "[PAX][High {0} Err][$TagName][$Time][Mem:%{1}/Cpu:%{2}[$TopProcess]/Disk{3}][InstanceID:{4}][LocalIP:{5}][Again:{6}]" -f $AlarmStatus, $AvrgMemory.ToString("#.#"), $AvrgCPU.ToString("#.#"), $LogicaldiskSize, $instanceid, $instanceLocalIP, $AlarmIn60Sec

    write-host $Message -ForegroundColor Yellow
    $Message > "$PSScriptRoot\EC2HighMemoryCPUCheckerService.log"
    if ($AlarmMessage -ne "") {
        Publish-SNSMessage -TopicArn arn:aws:sns:eu-west-1:topic -Message $AlarmMessage        
        $AlarmMessage=""  
    }
}