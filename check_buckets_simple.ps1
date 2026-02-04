$headers = @{
    "apikey" = "sb_secret_C-Z-MttzHCPnOR1y2Py4rw_VSsTvV_w"
    "Authorization" = "Bearer sb_secret_C-Z-MttzHCPnOR1y2Py4rw_VSsTvV_w"
}
$url = "https://awhuzekjpoapamijlvua.supabase.co/storage/v1/bucket"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers
    $response.id -join ", "
} catch {
    $_.Exception.Message
}
