# Xray-Setup-PowerShell

在 Linux 服务器上部署 VLESS-XTLS-uTLS-REALITY 的 PowerShell 脚本

### 前置要求

需要提前安装 `pwsh`, `curl`, `wget`, `git`, `tar`.

PowerShell on Linux 的安装方法可以在微软文档找到: \
[https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3)

### 使用方法

在 root 权限下执行以下命令：

```
# git clone https://github.com/rn7s2/Xray-Setup-PowerShell.git
# cd Xray-Setup-PowerShell
# pwsh ./setup.ps1
```

按照提示输入配置信息，即可完成 Xray 的安装。

### `dest` 和 `serverNames` 的说明

`dest` 和 `serverNames` 是实现 向中间人呈现指定 SNI 的全程真实 TLS 的重要配置项。

XTLS 官方社区有一个很有用的工具 [https://github.com/XTLS/ReaLITLScanner](`https://github.com/XTLS/ReaLITLScanner`)，你可以尝试使用这个工具来扫描各个目标网站，选出那些支持 TLS 1.3 + HTTP/2 的服务器，然后将它作为 `dest` 和 `serverNames` 填入配置文件中。
