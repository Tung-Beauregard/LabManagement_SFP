param([int]$Port = 8765, [string]$Root = (Split-Path -Parent $PSScriptRoot))
# Minimal static file server for local preview (no node / python needed).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\serve.ps1 [-Port 8765]
# Then open http://localhost:8765/ . Firebase Google sign-in needs an http origin, so file:// is not enough.
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "serving $Root on http://localhost:$Port/"
$types = @{ ".html"="text/html; charset=utf-8"; ".js"="text/javascript"; ".css"="text/css"; ".json"="application/json"; ".png"="image/png"; ".svg"="image/svg+xml" }
$rootFull = [IO.Path]::GetFullPath($Root)
while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
    if ([string]::IsNullOrEmpty($rel)) { $rel = "index.html" }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
    if ($full.StartsWith($rootFull) -and (Test-Path $full -PathType Leaf)) {
      $bytes = [IO.File]::ReadAllBytes($full)
      $ext = [IO.Path]::GetExtension($full).ToLower()
      $ctx.Response.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" })
      $ctx.Response.Headers.Add("Cache-Control", "no-store")
      if ($ctx.Request.HttpMethod -eq "HEAD") {
        $ctx.Response.ContentLength64 = 0
      } else {
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      }
      Write-Host "200 $($ctx.Request.HttpMethod) $rel"
    } else {
      $ctx.Response.StatusCode = 404
      Write-Host "404 $rel"
    }
  } catch {
    Write-Host "request failed: $($_.Exception.Message)"
  } finally {
    if ($ctx) { try { $ctx.Response.Close() } catch {} }
  }
}
