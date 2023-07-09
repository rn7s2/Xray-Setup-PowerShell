# Xray-Setup-PowerShell

在 Linux 服务器上部署 Xray 的 PowerShell 脚本

需要提前安装 pwsh, curl, git.

### 查看目标域名的 SAN

在 Edge 浏览器中打开目标域名, 按 F12 打开开发者工具, 选择 Security 选项卡，
然后按下 F5 刷新页面。在侧栏边中选择 Main origin (secure), 即可在
Certificate 中看到 SAN 信息（必要时请全部展开）。

如果 SAN 较多，可以复制出来使用以下 PowerShell 脚本来提取：

```powershell
# 请将 $sans 替换为实际的 SAN 列表
$sans = "www.example.com
example.com
a.example.com"

$result = @()
foreach ($san in $sans.Split("`n")) {
    $result += $san.Trim()
}

ConvertTo-Json $result
```
