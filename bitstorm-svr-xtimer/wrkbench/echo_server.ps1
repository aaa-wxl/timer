# Lightweight echo HTTP server using .NET HttpListener (no disk I/O, no per-request logging)
# Usage: powershell -File echo_server.ps1 [port]
param([int]$Port = 9999)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:${Port}/")
$listener.Start()
Write-Host "echo server on :$Port" -ForegroundColor Green

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $req = $ctx.Request
        if ($req.HasEntityBody -and $req.ContentLength64 -gt 0) {
            $stream = $req.InputStream
            $bytes = New-Object byte[] $req.ContentLength64
            $total = 0
            while ($total -lt $bytes.Length) {
                $read = $stream.Read($bytes, $total, $bytes.Length - $total)
                if ($read -le 0) { break }
                $total += $read
            }
        }
        $resp = $ctx.Response
        $resp.StatusCode = 200
        $body = [System.Text.Encoding]::UTF8.GetBytes('ok')
        $resp.ContentLength64 = $body.Length
        $resp.OutputStream.Write($body, 0, $body.Length)
        $resp.OutputStream.Close()
    } catch {
        if ($ctx.Response) { try { $ctx.Response.Close() } catch {} }
    }
}
