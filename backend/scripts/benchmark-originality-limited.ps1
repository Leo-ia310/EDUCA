# Windows equivalent for the offline benchmark: one half CPU and 512 MiB job memory.
# Does not run the API, contact Supabase, or alter limits of existing processes.
$ErrorActionPreference = 'Stop'
$backendDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputDirectory = [IO.Path]::GetFullPath((Join-Path $backendDirectory '../docs/performance/originality'))
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OriginalityJobLimits {
 [StructLayout(LayoutKind.Sequential)] public struct Basic {
  public long PerProcessUserTimeLimit,PerJobUserTimeLimit;
  public uint LimitFlags; public UIntPtr MinimumWorkingSetSize,MaximumWorkingSetSize;
  public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass,SchedulingClass;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong A,B,C,D,E,F; }
 [StructLayout(LayoutKind.Sequential)] public struct Extended {
  public Basic BasicLimitInformation; public Io IoInfo;
  public UIntPtr ProcessMemoryLimit,JobMemoryLimit,PeakProcessMemoryUsed,PeakJobMemoryUsed;
 }
 [StructLayout(LayoutKind.Sequential)] public struct Cpu { public uint ControlFlags,CpuRate; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateJobObject(IntPtr attributes,string name);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job,int type,IntPtr info,uint size);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
 public static void Set(IntPtr job,int kind,object value) {
  int size=Marshal.SizeOf(value); IntPtr ptr=Marshal.AllocHGlobal(size);
  try { Marshal.StructureToPtr(value,ptr,false); if(!SetInformationJobObject(job,kind,ptr,(uint)size))throw new System.ComponentModel.Win32Exception(); }
  finally { Marshal.FreeHGlobal(ptr); }
 }
}
'@
$jobHandle = [OriginalityJobLimits]::CreateJobObject([IntPtr]::Zero, $null)
if ($jobHandle -eq [IntPtr]::Zero) { throw 'Cannot create isolated benchmark job.' }
$benchmarkProcess = $null
$benchmarkProfileBefore = [Environment]::GetEnvironmentVariable('ORIGINALITY_BENCHMARK_PROFILE','Process')
try {
 $memory = New-Object OriginalityJobLimits+Extended
 $basic = New-Object OriginalityJobLimits+Basic
 $basic.LimitFlags = 0x2200 # JOB_MEMORY + KILL_ON_JOB_CLOSE
 $memory.BasicLimitInformation = $basic
 $memory.JobMemoryLimit = [UIntPtr](512MB)
 [OriginalityJobLimits]::Set($jobHandle,9,$memory)
 $cpuLimit = New-Object OriginalityJobLimits+Cpu
 $cpuLimit.ControlFlags = 5 # ENABLE + HARD_CAP
 $cpuLimit.CpuRate = [uint32][Math]::Floor(10000 * 0.5 / [Environment]::ProcessorCount)
 [OriginalityJobLimits]::Set($jobHandle,15,$cpuLimit)
 $nodeExecutable = (Get-Command node).Source
 $benchmarkScript = Join-Path $PSScriptRoot 'benchmark-originality.cjs'
 [Environment]::SetEnvironmentVariable('ORIGINALITY_BENCHMARK_PROFILE','limited','Process')
 $clock = [Diagnostics.Stopwatch]::StartNew()
 $benchmarkProcess = Start-Process -FilePath $nodeExecutable -ArgumentList @('--max-old-space-size=160', ('"' + $benchmarkScript + '"')) -WorkingDirectory $backendDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputDirectory 'limited-stdout.log') -RedirectStandardError (Join-Path $outputDirectory 'limited-stderr.log')
 if (-not [OriginalityJobLimits]::AssignProcessToJobObject($jobHandle,$benchmarkProcess.Handle)) { throw [ComponentModel.Win32Exception]::new() }
 # The caller can poll this script; this wait is bounded and the benchmark is offline.
 if (-not $benchmarkProcess.WaitForExit(60000)) { throw 'Limited benchmark exceeded 60 seconds.' }
 $benchmarkProcess.Refresh()
 if ($benchmarkProcess.ExitCode -ne 0) { throw 'Limited benchmark failed; inspect limited-stderr.log.' }
 $record = [ordered]@{
  date = [DateTime]::UtcNow.ToString('o'); mechanism = 'Windows Job Object';
  requestedCpus = 0.5; logicalCpus = [Environment]::ProcessorCount;
  cpuRateHardCap = $cpuLimit.CpuRate; jobMemoryLimitBytes = 512MB;
  elapsedMs = $clock.ElapsedMilliseconds; exitCode = $benchmarkProcess.ExitCode;
  scope = 'Offline Node algorithm/index fixture + extraction worker thread; not HTTP/PostgreSQL/Render.'
 }
 $record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputDirectory 'resource-limits.json') -Encoding utf8
 Get-Content -LiteralPath (Join-Path $outputDirectory 'limited-stdout.log')
} finally {
 [Environment]::SetEnvironmentVariable('ORIGINALITY_BENCHMARK_PROFILE',$benchmarkProfileBefore,'Process')
 # Closing the isolated job terminates only this benchmark if a limit/setup failed.
 [OriginalityJobLimits]::CloseHandle($jobHandle) | Out-Null
}
