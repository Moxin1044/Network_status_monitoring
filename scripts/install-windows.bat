@echo off
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "APP_NAME=network_status_monitoring"
set "EXE_NAME=%APP_NAME%.exe"
set "INSTALL_DIR=C:\Program Files\NetworkStatusMonitoring"
set "SERVICE_NAME=NetworkStatusMonitor"
set "NSSM_URL=https://nssm.cc/release/nssm-2.24.zip"
set "SCRIPT_DIR=%~dp0"
set "MODE=%~1"

if /i "!MODE!"=="--uninstall" goto :uninstall
if /i "!MODE!"=="-u" goto :uninstall
if /i "!MODE!"=="--help" goto :help
if /i "!MODE!"=="-h" goto :help
goto :install

:help
echo.
echo   用法: %~nx0 [选项]
echo.
echo   选项:
echo     (无)          安装 Network Status Monitor
echo     --uninstall   卸载 Network Status Monitor
echo     --help        显示帮助信息
echo.
exit /b 0

:ensure_admin
net session >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo   [!] 此脚本需要管理员权限运行
    echo.
    echo   正在请求管理员权限...
    if "!MODE!"=="--uninstall" (
        powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" --uninstall' -Verb RunAs"
    ) else (
        powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    )
    exit /b
)
goto :eof

:uninstall
echo.
echo ┌─────────────────────────────────────────────────┐
echo │   Network Status Monitor - 卸载程序             │
echo └─────────────────────────────────────────────────┘
echo.

call :ensure_admin

set "FOUND=0"
if exist "%INSTALL_DIR%" set "FOUND=1"
if exist "%INSTALL_DIR%\%EXE_NAME%" set "FOUND=1"

where nssm >nul 2>&1
if %ERRORLEVEL% equ 0 (
    nssm status %SERVICE_NAME% >nul 2>&1
    if !ERRORLEVEL! equ 0 set "FOUND=1"
)
if not "!FOUND!"=="1" (
    if exist "%INSTALL_DIR%\nssm.exe" (
        "%INSTALL_DIR%\nssm.exe" status %SERVICE_NAME% >nul 2>&1
        if !ERRORLEVEL! equ 0 set "FOUND=1"
    )
)

schtasks /query /tn "%SERVICE_NAME%" >nul 2>&1
if %ERRORLEVEL% equ 0 set "FOUND=1"

if "!FOUND!"=="0" (
    echo   [✖] 未检测到 Network Status Monitor 的安装
    echo.
    pause
    exit /b 1
)

echo   步骤 1/5: 停止服务 / 任务
echo.

where nssm >nul 2>&1
if %ERRORLEVEL% neq 0 (
    if exist "%INSTALL_DIR%\nssm.exe" (
        set "PATH=%INSTALL_DIR%;%PATH%"
    )
)

nssm status %SERVICE_NAME% >nul 2>&1
if %ERRORLEVEL% equ 0 (
    nssm stop %SERVICE_NAME% >nul 2>&1
    echo   [✔] NSSM 服务已停止
) else (
    schtasks /end /tn "%SERVICE_NAME%" >nul 2>&1
    echo   [i] 任务计划已停止 (如存在)
)

echo.
echo   步骤 2/5: 移除服务 / 任务
echo.

nssm status %SERVICE_NAME% >nul 2>&1
if %ERRORLEVEL% equ 0 (
    nssm remove %SERVICE_NAME% confirm >nul 2>&1
    echo   [✔] NSSM 服务已移除
) else (
    schtasks /delete /tn "%SERVICE_NAME%" /f >nul 2>&1
    echo   [i] 任务计划已移除 (如存在)
)

echo.
echo   步骤 3/5: 移除安装目录
echo.

if exist "%INSTALL_DIR%" (
    if exist "%INSTALL_DIR%\config.yml" (
        set /p "keep_config=  是否保留配置文件 config.yml? (y/n): "
        if /i "!keep_config!"=="y" (
            copy /y "%INSTALL_DIR%\config.yml" "%TEMP%\network-status-monitoring-config.yml.bak" >nul 2>&1
            echo   [✔] 配置文件已备份到: %TEMP%\network-status-monitoring-config.yml.bak
        )
    )

    rd /s /q "%INSTALL_DIR%" 2>nul
    if exist "%INSTALL_DIR%" (
        echo   [!] 部分文件可能正在使用，将在重启后删除
        powershell -Command "Remove-Item -Path '%INSTALL_DIR%' -Recurse -Force" 2>nul
    )
    echo   [✔] 安装目录已移除
) else (
    echo   [i] 安装目录不存在，跳过
)

echo.
echo   步骤 4/5: 清理注册表残留
echo.

reg query "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    sc delete %SERVICE_NAME% >nul 2>&1
    echo   [✔] 已清理注册表服务残留
) else (
    echo   [i] 无注册表残留
)

echo.
echo   步骤 5/5: 最终确认
echo.

set "ANY_LEFT=0"
if exist "%INSTALL_DIR%" set "ANY_LEFT=1"

if "!ANY_LEFT!"=="0" (
    echo   [✔] 卸载清理完毕
) else (
    echo   [!] 部分文件未能删除，请手动清理: %INSTALL_DIR%
)

echo.
echo ┌─────────────────────────────────────────────────┐
echo │   卸载完成!                                      │
echo └─────────────────────────────────────────────────┘
echo.
if exist "%TEMP%\network-status-monitoring-config.yml.bak" (
    echo   配置备份:  %TEMP%\network-status-monitoring-config.yml.bak
    echo.
)
pause
exit /b 0

:install
echo.
echo ┌─────────────────────────────────────────────────┐
echo │   Network Status Monitor - Windows 安装程序     │
echo └─────────────────────────────────────────────────┘
echo.

call :ensure_admin

echo   步骤 1/6: 检查可执行文件
echo.

if not exist "%SCRIPT_DIR%%EXE_NAME%" (
    echo   [✖] 未找到可执行文件: %SCRIPT_DIR%%EXE_NAME%
    pause
    exit /b 1
)
echo   [✔] 可执行文件已就绪: %SCRIPT_DIR%%EXE_NAME%

echo.
echo   步骤 2/6: 安装文件
echo.

echo   [i] 安装目录: %INSTALL_DIR%

if exist "%INSTALL_DIR%\config.yml" (
    echo   [!] 检测到已有安装，将保留原有配置文件
    set "KEEP_CONFIG=1"
) else (
    set "KEEP_CONFIG=0"
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /y "%SCRIPT_DIR%%EXE_NAME%" "%INSTALL_DIR%\" >nul

if "!KEEP_CONFIG!"=="1" (
    echo   [i] 保留现有 config.yml
) else (
    if exist "%SCRIPT_DIR%config.yml" (
        copy /y "%SCRIPT_DIR%config.yml" "%INSTALL_DIR%\" >nul
    ) else (
        (
            echo feishu_webhook: "*"
            echo check_interval: 30
        ) > "%INSTALL_DIR%\config.yml"
        echo   [!] 未找到 config.yml，已生成默认配置
    )
)

echo   [✔] 文件已安装到 %INSTALL_DIR%
echo   [✔] 配置文件: %INSTALL_DIR%\config.yml

echo.
echo   步骤 3/6: 检查服务管理工具
echo.

set "USE_NSSM=0"
set "USE_TASKSCHED=0"

where nssm >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo   [✔] 已检测到 NSSM
    set "USE_NSSM=1"
) else (
    if exist "%INSTALL_DIR%\nssm.exe" (
        echo   [✔] 已检测到 NSSM (安装目录)
        set "USE_NSSM=1"
        set "PATH=%INSTALL_DIR%;%PATH%"
    ) else (
        echo   [i] 未检测到 NSSM
        echo.
        set /p "dl_nssm=  是否自动下载 NSSM 用于注册 Windows 服务? (y/n): "
        if /i "!dl_nssm!"=="y" (
            echo   [i] 正在下载 NSSM...
            powershell -Command "& {Invoke-WebRequest -Uri '%NSSM_URL%' -OutFile '%INSTALL_DIR%\nssm.zip'}" 2>nul
            if exist "%INSTALL_DIR%\nssm.zip" (
                powershell -Command "& {Expand-Archive -Path '%INSTALL_DIR%\nssm.zip' -DestinationPath '%INSTALL_DIR%\nssm_tmp' -Force}" 2>nul
                copy /y "%INSTALL_DIR%\nssm_tmp\nssm-2.24\win64\nssm.exe" "%INSTALL_DIR%\" >nul 2>&1
                if exist "%INSTALL_DIR%\nssm.exe" (
                    echo   [✔] NSSM 下载完成
                    set "USE_NSSM=1"
                    set "PATH=%INSTALL_DIR%;%PATH%"
                ) else (
                    copy /y "%INSTALL_DIR%\nssm_tmp\nssm-2.24\win32\nssm.exe" "%INSTALL_DIR%\" >nul 2>&1
                    if exist "%INSTALL_DIR%\nssm.exe" (
                        echo   [✔] NSSM 下载完成 ^(32-bit^)
                        set "USE_NSSM=1"
                        set "PATH=%INSTALL_DIR%;%PATH%"
                    )
                )
                rd /s /q "%INSTALL_DIR%\nssm_tmp" 2>nul
                del "%INSTALL_DIR%\nssm.zip" 2>nul
            )
        )

        if "!USE_NSSM!"=="0" (
            echo.
            echo   [i] 将使用 Windows 任务计划程序实现开机自启动
            set "USE_TASKSCHED=1"
        )
    )
)

echo.
echo   步骤 4/6: 注册服务 / 任务
echo.

if "!USE_NSSM!"=="1" (
    nssm status %SERVICE_NAME% >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo   [!] 服务已存在，将先移除
        nssm stop %SERVICE_NAME% >nul 2>&1
        nssm remove %SERVICE_NAME% confirm >nul 2>&1
    )

    nssm install %SERVICE_NAME% "%INSTALL_DIR%\%EXE_NAME%"
    nssm set %SERVICE_NAME% AppDirectory "%INSTALL_DIR%"
    nssm set %SERVICE_NAME% DisplayName "Network Status Monitor"
    nssm set %SERVICE_NAME% Description "监控内网和公网 IP 变动并推送飞书通知"
    nssm set %SERVICE_NAME% Start SERVICE_AUTO_START
    nssm set %SERVICE_NAME% AppStdout "%INSTALL_DIR%\service.log"
    nssm set %SERVICE_NAME% AppStderr "%INSTALL_DIR%\error.log"
    nssm set %SERVICE_NAME% AppRotateFiles 1
    nssm set %SERVICE_NAME% AppRotateBytes 10485760

    echo   [✔] Windows 服务已注册: %SERVICE_NAME%
) else if "!USE_TASKSCHED!"=="1" (
    schtasks /delete /tn "%SERVICE_NAME%" /f >nul 2>&1
    schtasks /create /tn "%SERVICE_NAME%" /tr "\"%INSTALL_DIR%\%EXE_NAME%\"" /sc onstart /ru SYSTEM /rl highest /f
    echo   [✔] 任务计划已创建: %SERVICE_NAME%
    echo   [i] 使用任务计划程序模式 (非标准 Windows 服务)
)

echo.
echo   步骤 5/6: 配置开机自启动
echo.

if "!USE_NSSM!"=="1" (
    set /p "enable_auto=  是否启用开机自启动? (y/n): "
    if /i "!enable_auto!"=="y" (
        nssm set %SERVICE_NAME% Start SERVICE_AUTO_START
        echo   [✔] 已启用开机自启动
    ) else (
        nssm set %SERVICE_NAME% Start SERVICE_DEMAND_START
        echo   [i] 未启用开机自启动
    )
) else if "!USE_TASKSCHED!"=="1" (
    set /p "enable_auto=  是否启用开机自启动? (y/n): "
    if /i "!enable_auto!"=="y" (
        schtasks /change /tn "%SERVICE_NAME%" /enable
        echo   [✔] 已启用开机自启动
    ) else (
        schtasks /change /tn "%SERVICE_NAME%" /disable
        echo   [i] 未启用开机自启动
    )
)

echo.
echo   步骤 6/6: 启动服务
echo.

set /p "start_now=  是否立即启动? (y/n): "
if /i "!start_now!"=="y" (
    if "!USE_NSSM!"=="1" (
        nssm start %SERVICE_NAME%
        timeout /t 2 >nul
        nssm status %SERVICE_NAME% | findstr /c:"RUNNING" >nul
        if !ERRORLEVEL! equ 0 (
            echo   [✔] 服务已成功启动!
        ) else (
            echo   [✖] 服务启动失败，请检查日志:
            type "%INSTALL_DIR%\error.log" 2>nul
        )
    ) else if "!USE_TASKSCHED!"=="1" (
        schtasks /run /tn "%SERVICE_NAME%"
        echo   [✔] 任务已启动
    )
) else (
    echo   [i] 未启动服务 (可稍后手动启动)
)

echo.
echo ┌─────────────────────────────────────────────────┐
echo │   安装完成!                                      │
echo └─────────────────────────────────────────────────┘
echo.

if "!USE_NSSM!"=="1" (
    echo   管理命令 ^(NSSM 服务模式^):
    echo.
    echo     启动服务    nssm start %SERVICE_NAME%
    echo     停止服务    nssm stop %SERVICE_NAME%
    echo     重启服务    nssm restart %SERVICE_NAME%
    echo     服务状态    nssm status %SERVICE_NAME%
    echo     编辑配置    nssm edit %SERVICE_NAME%
    echo     移除服务    nssm remove %SERVICE_NAME% confirm
    echo.
    echo     查看日志    type "%INSTALL_DIR%\service.log"
    echo     错误日志    type "%INSTALL_DIR%\error.log"
) else (
    echo   管理命令 ^(任务计划模式^):
    echo.
    echo     启动任务    schtasks /run /tn "%SERVICE_NAME%"
    echo     停止任务    schtasks /end /tn "%SERVICE_NAME%"
    echo     启用自启    schtasks /change /tn "%SERVICE_NAME%" /enable
    echo     禁用自启    schtasks /change /tn "%SERVICE_NAME%" /disable
    echo     删除任务    schtasks /delete /tn "%SERVICE_NAME%" /f
)

echo.
echo   配置文件:  %INSTALL_DIR%\config.yml
echo   卸载程序:  %~nx0 --uninstall
echo.
pause
