<#
.SYNOPSIS
    video-editing-skills 前置环境检查脚本（硬件 + Python）

.DESCRIPTION
    阶段 1 - 硬件检查（满足任一条件）：
      条件 A - Intel 白名单独显：Arc A770（16GB）/ Arc B580（12GB），CPU 型号不限
      条件 B - Intel iGPU 平台：MTL / LNL / ARL / PTL CPU + Intel iGPU + 内存 > 16 GB

    阶段 2 - Python >= 3.10 检查：
      仅检查宿主 Python 是否可用，不再执行系统级自动安装。
      项目本地 .venv、requirements、ffmpeg、模型的准备统一放到阶段 1：准备。

    两阶段全部通过 → exit 0；任一失败 → exit 1

.NOTES
    扩展独显白名单：在 $DGPU_WHITELIST 数组中追加型号编号即可。
#>

# ============================================================
# 配置项
# ============================================================

# 独显白名单：只写型号编号（如 "B580"），不写 "Arc B580"
# 实际显卡名含 (TM)，如 "Intel(R) Arc(TM) B580 Graphics"，全名匹配会失败
$DGPU_WHITELIST = @("A770", "B580", "B50" ,"B60")
$dGpuPattern    = $DGPU_WHITELIST -join "|"

$PYTHON_MIN_MAJOR = 3
$PYTHON_MIN_MINOR = 10

# ============================================================
# 工具函数
# ============================================================

function Find-PythonMin {
    <#
    .SYNOPSIS 在 PATH 中查找 Python >= $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR，返回可用命令字符串；未找到返回 $null
    #>
    foreach ($cmd in @("python", "python3")) {
        try {
            $ver = "$(& $cmd --version 2>&1)"
            if ($ver -match "Python (\d+)\.(\d+)\.(\d+)") {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2]
                if ($maj -gt $PYTHON_MIN_MAJOR -or ($maj -eq $PYTHON_MIN_MAJOR -and $min -ge $PYTHON_MIN_MINOR)) {
                    return $cmd
                }
            }
        } catch {}
    }
    # py launcher 方式（Windows Python Launcher）
    foreach ($pyver in @("3.13","3.12","3.11","3.10")) {
        try {
            $ver = "$(& py -$pyver --version 2>&1)"
            if ($ver -match "Python (\d+)\.(\d+)\.(\d+)") {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2]
                if ($maj -gt $PYTHON_MIN_MAJOR -or ($maj -eq $PYTHON_MIN_MAJOR -and $min -ge $PYTHON_MIN_MINOR)) {
                    return "py -$pyver"
                }
            }
        } catch {}
    }
    return $null
}

function Get-PythonVersion([string]$cmd) {
    try {
        if ($cmd.StartsWith("py -")) {
            $parts = $cmd.Split(" ", 2)
            $pyArg = $parts[1]
            return "$(& py $pyArg --version 2>&1)".Trim()
        }
        return "$(& $cmd --version 2>&1)".Trim()
    } catch { return "unknown" }
}

# ============================================================
# 阶段 1：硬件检查
# ============================================================
Write-Host ""
Write-Host "=== 阶段 1：Intel 硬件平台检查 ============================="

$cpu        = (Get-WmiObject Win32_Processor).Name
$allGpus    = Get-WmiObject Win32_VideoController
$totalMemGB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)

# 独显：名称匹配白名单
$dgpu = $allGpus |
    Where-Object { $_.Name -match "Intel" -and $_.Name -match $dGpuPattern } |
    Select-Object -First 1

# iGPU：Intel 集成显卡，排除白名单独显
$igpu = $allGpus |
    Where-Object {
        $_.Name -match "Intel" -and
        $_.Name -match "UHD|Iris|Xe|Arc" -and
        $_.Name -notmatch $dGpuPattern
    } |
    Select-Object -First 1

# CPU 平台代号（WMI 名称含 (TM)，如 "Intel(R) Core(TM) Ultra 7 155H"）
$platform = $null
if     ($cpu -match "Ultra \d+\s+1\d{2}")                                            { $platform = "MTL" }
elseif ($cpu -match "Ultra \d+\s+2\d{2}V")                                           { $platform = "LNL" }
elseif ($cpu -match "Ultra \d+\s+2\d{2}" -and $cpu -notmatch "Ultra \d+\s+2\d{2}V") { $platform = "ARL" }
elseif ($cpu -match "Ultra \d+\s+3\d{2}")                                            { $platform = "PTL" }

$hwPass = $false

if ($dgpu) {
    # 条件 A：有白名单独显，CPU 不限
    Write-Host "✅ [PASS] 条件 A - Intel 独显（白名单）：$($dgpu.Name)"
    Write-Host "ℹ️  [INFO] 独显路线：跳过 CPU 平台与内存检查"
    $hwPass = $true
} else {
    # 条件 B：MTL/LNL/ARL/PTL + iGPU + 内存 > 16 GB
    Write-Host "ℹ️  [INFO] 未检测到白名单独显，检查条件 B（iGPU 平台）..."
    $condB = $true

    if ($platform) {
        Write-Host "✅ [PASS] CPU 平台：$platform（$cpu）"
    } else {
        Write-Host "❌ [FAIL] CPU 不支持：$cpu"
        Write-Host "         需要 Intel MTL/LNL/ARL/PTL，或配备白名单独显（$($DGPU_WHITELIST -join ' / ')）"
        $condB = $false
    }
    if ($igpu) {
        Write-Host "✅ [PASS] Intel iGPU：$($igpu.Name)"
    } else {
        Write-Host "❌ [FAIL] 未检测到 Intel iGPU"
        $condB = $false
    }
    if ($totalMemGB -gt 16) {
        Write-Host "✅ [PASS] 内存：${totalMemGB} GB"
    } else {
        Write-Host "❌ [FAIL] 内存不足：${totalMemGB} GB（需 > 16 GB）"
        $condB = $false
    }
    $hwPass = $condB
}

if (-not $hwPass) {
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "❌ 硬件检查未通过，禁止执行后续技能。"
    Write-Host ""
    Write-Host "   支持条件 A：Intel 白名单独显（$($DGPU_WHITELIST -join ' / ')）"
    Write-Host "   支持条件 B：Intel MTL/LNL/ARL/PTL CPU + Intel iGPU + 内存 > 16 GB"
    exit 1
}

Write-Host "============================================================"
Write-Host "✅ 阶段 1 通过"

# ============================================================
# 阶段 2：Python >= 3.10 检查
# ============================================================
Write-Host ""
Write-Host "=== 阶段 2：Python >= 3.10 环境检查 ========================"

$pythonCmd = Find-PythonMin

if ($pythonCmd) {
    $verStr = Get-PythonVersion $pythonCmd
    Write-Host "✅ [PASS] Python >= $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR：$verStr（命令：$pythonCmd）"
} else {
    Write-Host "❌ [FAIL] 未找到 Python >= $PYTHON_MIN_MAJOR.$PYTHON_MIN_MINOR。"
    Write-Host ""
    Write-Host "   请先手动安装 Python 3.10+，然后再执行阶段 1：准备。"
    Write-Host "   阶段 1 会统一创建 <SKILL_DIR>\\.venv 并安装 requirements / ffmpeg / 模型。"
    exit 1
}

Write-Host "============================================================"
Write-Host ""
Write-Host "✅ 所有检查通过（硬件 + 宿主 Python），可执行阶段 1：准备。"
exit 0
