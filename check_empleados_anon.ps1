$headers = @{
    "apikey" = "sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
    "Authorization" = "Bearer sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
}
$url = "https://awhuzekjpoapamijlvua.supabase.co/rest/v1/Empleados?select=*&limit=1"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers
    $response | ConvertTo-Json
} catch {
    $_.Exception.Message
}
