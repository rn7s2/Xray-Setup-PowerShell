#!/usr/bin/pwsh

function Get-IsRoot {
    return ((id -u) -eq 0)
}

function Enter-Settings {
    $port = [int](Read-Host -Prompt "输入 Xray 本地监听地址 (例: 50402) [默认: 随机]")
    if ($port -eq "") {
        $port = Get-Random -Maximum 65535 -Minimum 14400
    }
    Write-Host "选择: $port"
    $domain = Read-Host -Prompt "输入已经正确解析的本机域名 (例: example.com)"
    if ($domain -eq "") {
        Throw "域名不能为空"
    }
    Write-Host "选择: $domain"
    $email = Read-Host -Prompt "输入域名 TLS 证书的电子邮件地址"
    if ($email -eq "") {
        Throw "电子邮件地址不能为空"
    }
    Write-Host "选择: $email"
    $camouflage = Read-Host -Prompt "输入伪装域名 (例: example.com)"
    if ($camouflage -eq "") {
        Throw "伪装域名不能为空"
    }
    Write-Host "选择: $camouflage"
    return @{
        port       = $port
        domain     = $domain
        email      = $email
        camouflage = $camouflage
    }
}

$GO_VERSION = "1.20.5"

function Install-Xray {
    systemctl stop xray

    Write-Host "开始安装 Xray..."
    curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install
    if ($LASTEXITCODE -ne 0) {
        Throw "Xray 安装失败"
    }
    systemctl stop xray

    Write-Host "准备 Go 环境..."
    $arch = uname -m
    Write-Host "架构: $arch"
    switch ($arch) {
        "x86_64" { $arch = "amd64" }
        "aarch64" { $arch = "arm64" }
        Default { Throw "不支持的架构: $arch" }
    }
    $compressedFile = "go$GO_VERSION.linux-$arch.tar.gz"
    $url = "https://go.dev/dl/$compressedFile"
    wget -c $url
    tar -C /usr/local -xzf "$compressedFile"
    $env:PATH = "/usr/local/go/bin:" + $env:PATH
    go version

    Write-Host "准备 Xray 源码..."
    $pwdBefore = $PWD
    git clone https://github.com/XTLS/Xray-core.git

    Write-Host "编译 Xray..."
    Set-Location Xray-core
    go mod download
    $env:CGO_ENABLED = 0
    go build -o xray -trimpath -ldflags "-s -w -buildid=" ./main
    mv xray /usr/local/bin/xray
    chmod +x /usr/local/bin/xray
    Write-Host "Xray 编译成功"

    Write-Host "执行清理工作..."
    Set-Location $pwdBefore
    rm -rf Xray-core
    rm "$compressedFile"
    Write-Host "Xray 安装成功"
}

function Install-Caddy {
    systemctl stop caddy

    Write-Host "开始安装 Caddy..."

    Write-Host "下载 Caddy..."
    $arch = uname -m
    Write-Host "架构: $arch"
    $url = "https://caddyserver.com/api/download?os=linux&arch="
    switch ($arch) {
        "x86_64" { $url += "amd64" }
        "aarch64" { $url += "arm64" }
        Default { Throw "不支持的架构: $arch" }
    }

    if (-not (Test-Path /usr/local/bin)) {
        mkdir -p /usr/local/bin
    }
    curl -o /usr/local/bin/caddy $url
    chmod +x /usr/local/bin/caddy
    
    groupadd --system caddy
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy
    
    cp ./caddy.service /etc/systemd/system/caddy.service
    systemctl daemon-reload

    Write-Host "Caddy 安装成功"
}

function New-x25519-KeyPair {
    $out = xray x25519 | Out-String
    $out.Split("`n") | ForEach-Object {
        if ($_ -match "Private key: (.*)") {
            $privateKey = $Matches[1]
        }
        if ($_ -match "Public key: (.*)") {
            $publicKey = $Matches[1]
        }
    }
    if ($privateKey -eq $null -or $publicKey -eq $null -or
        $privateKey -eq "" -or $publicKey -eq "") {
        Throw "生成密钥对失败"
    }
    return $privateKey, $publicKey
}

function Get-First-N-Primes {
    param (
        [Parameter(Mandatory = $true)]
        [int]
        $n
    )

    $primes = @()
    $i = 2

    while ($primes.Count -lt $n) {
        $isPrime = $true

        for ($j = 2; $j -lt $i; $j++) {
            if ($i % $j -eq 0) {
                $isPrime = $false
                break;
            }
        }

        if ($isPrime) {
            $primes += $i
        }
        $i++
    }

    return $primes
}

function ConvertTo-String-List {
    param (
        [Parameter(Mandatory = $true)]
        [int[]]
        $numbers
    )

    $list = @()
    foreach ($number in $numbers) {
        $list += $number.ToString("D2")
    }
    return $list
}

function New-Short-Id-List {
    param (
        [Parameter(Mandatory = $true)]
        [int]
        $n
    )
    return ConvertTo-String-List (Get-First-N-Primes $n)
}

function Initialize-Xray {
    param (
        [Parameter(Mandatory = $true)]
        $settings
    )

    $uuid = xray uuid
    $privateKey, $publicKey = New-x25519-KeyPair
    $config = @{
        inbounds = @(
            @{
                listen         = "127.0.0.1"
                port           = $settings["port"]
                protocol       = "vless"
                settings       = @{
                    clients    = @(
                        @{
                            id   = $uuid
                            flow = "xtls-rprx-vision"
                        }
                    )
                    decryption = "none"
                }
                streamSettings = @{
                    network         = "tcp"
                    security        = "reality"
                    realitySettings = @{
                        dest        = $settings["camouflage"] + ":443"
                        serverNames = @( $settings["camouflage"] )
                        privateKey  = $privateKey
                        shortIds    = New-Short-Id-List 4
                    }
                }
            }
        )
    }

    ConvertTo-Json $config -Depth 5 | Out-File /usr/local/etc/xray/config.json
    systemctl enable xray --now

    Write-Host "Xray 配置成功"
    return $uuid, $publicKey
}

function Initialize-Caddy {
    param (
        [Parameter(Mandatory = $true)]
        $settings
    )

    $config = ""
    $config += $settings["domain"] + " {`n"
    $email = $settings["email"]
    $config += "    tls $email`n"
    $config += "    reverse_proxy localhost:" + $settings["port"] + "`n"
    $config += "}`n"

    if (-not (Test-Path /usr/local/etc/caddy)) {
        mkdir -p /usr/local/etc/caddy
    }
    $config | Out-File /usr/local/etc/caddy/Caddyfile
    systemctl enable caddy --now

    Write-Host "Caddy 配置成功"
}

function New-VLESS-ShareLink {
    param (
        [Parameter(Mandatory = $true)]
        $settings,
        [Parameter(Mandatory = $true)]
        $uuid,
        [Parameter(Mandatory = $true)]
        $publicKey
    )

    $link = "vless://"
    $link += [uri]::EscapeUriString($uuid)
    $link += "@"
    $link += $settings["domain"]
    $link += ":443"
    $link += "?"
    $link += "encryption=none&type=tcp"
    $link += "&security=reality"
    $link += "&fp=chrome"
    $link += "&sni=" + [uri]::EscapeUriString($settings["camouflage"])
    $link += "&pbk=" + [uri]::EscapeUriString($publicKey)
    $link += "&sid=02"
    $link += "&flow=xtls-rprx-vision"
    $link += "&headerType=none"
    $link += "#" + [uri]::EscapeUriString("rn7s2-" + $settings["domain"])
    return $link
}

function Main {
    if (-not (Get-IsRoot)) {
        Throw "请使用 root 用户运行此脚本"
    }

    $settings = Enter-Settings
    Read-Host -Prompt "按 Enter 键开始安装"

    Install-Xray
    Install-Caddy

    $uuid, $publicKey = Initialize-Xray $settings
    Initialize-Caddy $settings
    
    $shareLink = New-VLESS-ShareLink $settings $uuid $publicKey
    Write-Host "VLESS 分享链接:`n$shareLink"
    $shareLink | Out-File sharelink.txt
    Write-Host "已将分享链接保存到 sharelink.txt"

    Write-Host "安装完成"
}

Main
