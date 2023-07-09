#!/usr/bin/pwsh

function Get-IsRoot {
    return ((id -u) -eq 0)
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

$GO_VERSION = "1.20.5"

function Install-Xray {
    systemctl stop xray

    Write-Host "开始安装 Xray..."
    curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install
    if ($LASTEXITCODE -ne 0) {
        Throw "Xray 安装失败"
    }
    systemctl stop xray
    chown root:root -R /var/log/xray

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

    "[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
Group=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target" | Out-File /etc/systemd/system/xray.service
    systemctl daemon-reload
    Write-Host "Xray 编译成功"

    Write-Host "执行清理工作..."
    Set-Location $pwdBefore
    rm -rf Xray-core
    rm "$compressedFile"
    Write-Host "Xray 安装成功"
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
        log       = @{
            loglevel = "warning"
            error    = "/var/log/xray/error.log"
        }
        routing   = @{
            domainStrategy = "IPIfNonMatch"
            rules          = @(
                @{
                    type        = "field"
                    ip          = @(
                        "geoip:cn"
                        "geoip:private"
                    )
                    outboundTag = "block"
                }
            )
        }
        outbounds = @(
            @{
                protocol = "freedom"
                tag      = "direct"
            }
            @{
                protocol = "blackhole"
                tag      = "block"
            }
        )
        inbounds  = @(
            @{
                listen         = "0.0.0.0"
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
                        dest        = $settings["dest"]
                        serverNames = $settings["serverNames"]
                        privateKey  = $privateKey
                        shortIds    = New-Short-Id-List 4
                    }
                }
            }
        )
    }

    if (-not (Test-Path /usr/local/etc/xray)) {
        mkdir /usr/local/etc/xray
    }
    ConvertTo-Json $config -Depth 5 | Out-File /usr/local/etc/xray/config.json
    systemctl enable xray --now

    Write-Host "Xray 配置成功"
    return $uuid, $publicKey
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

    $ip = (ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}' | Out-String).Trim()
    $link = "vless://"
    $link += [uri]::EscapeUriString($uuid)
    $link += "@"
    $link += $ip
    $link += ":" + $settings["port"]
    $link += "?"
    $link += "encryption=none&type=tcp"
    $link += "&security=reality"
    $link += "&fp=chrome"
    $link += "&sni=" + [uri]::EscapeUriString($settings["dest"].Split(":")[0])
    $link += "&pbk=" + [uri]::EscapeUriString($publicKey)
    $link += "&sid=02"
    $link += "&flow=xtls-rprx-vision"
    $link += "&headerType=none"
    $link += "#" + [uri]::EscapeUriString("rn7s2-" + $ip)
    return $link
}

function Main {
    if (-not (Get-IsRoot)) {
        Throw "请使用 root 用户运行此脚本"
    }

    $settings = Enter-Settings
    Read-Host -Prompt "按 Enter 键开始安装"

    Install-Xray

    $uuid, $publicKey = Initialize-Xray $settings    

    $shareLink = New-VLESS-ShareLink $settings $uuid $publicKey    
    Write-Host "VLESS 分享链接:`n$shareLink"

    $shareLink | Out-File sharelink.txt
    Write-Host "已将分享链接保存到 sharelink.txt"

    Write-Host "安装完成"
}

Main
