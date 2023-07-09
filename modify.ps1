#!/bin/pwsh

function Get-IsRoot {
    return ((id -u) -eq 0)
}

function Read-Settings {
    $settings = (Get-Content /usr/local/etc/xray/config.json) | ConvertFrom-Json
    return $settings, @{
        port        = $settings.inbounds[0].port
        dest        = $settings.inbounds[0].streamSettings.realitySettings.dest
        serverNames = $settings.inbounds[0].streamSettings.realitySettings.serverNames
    }
}

function Enter-Settings {
    $port = Read-Host -Prompt "输入监听端口 (默认: 443)"
    if ($port -eq "" -or $null -eq $port) {
        $port = 443
    }
    $port = [int]$port
    Write-Host "选择: $port"

    $dest = Read-Host -Prompt "输入伪装域名 (例: example.com:443)"
    if ($dest -eq "" -or $null -eq $dest) {
        Throw "伪装域名不能为空"
    }
    Write-Host "选择: $dest"

    $serverNames = Read-Host -Prompt "输入客户端可用的 ServerName 列表, 以英文逗号分隔"
    if ($serverNames -eq "" -or $null -eq $serverNames) {
        Throw "客户端可用的 ServerName 列表不能为空"
    }
    $serverNames = $serverNames.Split(",")

    return @{
        port        = $port
        dest        = $dest
        serverNames = $serverNames
    }
}

function Update-Settings {
    if (-not (Get-IsRoot)) {
        Throw "请使用 root 用户执行此脚本"
    }

    $settings, $conf = Read-Settings
    Write-Host "当前设置:"
    Write-Host "  监听端口: $($conf.port)"
    Write-Host "  伪装域名: $($conf.dest)"
    Write-Host "  ServerName 列表: $($conf.serverNames -join ",")"

    $newSettings = Enter-Settings
    Write-Host "新设置:"
    Write-Host "  监听端口: $($newSettings.port)"
    Write-Host "  伪装域名: $($newSettings.dest)"
    Write-Host "  ServerName 列表: $($newSettings.serverNames -join ",")"

    $settings.inbounds[0].port = $newSettings.port
    $settings.inbounds[0].streamSettings.realitySettings.dest = $newSettings.dest
    $settings.inbounds[0].streamSettings.realitySettings.serverNames = $newSettings.serverNames

    systemctl stop xray
    $settings | ConvertTo-Json -Depth 5 | Out-File /usr/local/etc/xray/config.json
    systemctl start xray

    Write-Host "设置已更新"
}

Update-Settings
