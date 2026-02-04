$headers = @{
    "apikey" = "sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
    "Authorization" = "Bearer sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
}
$url = "https://awhuzekjpoapamijlvua.supabase.co/rest/v1/Empleados?id=eq.77f2113b-3c6d-41db-b3b0-5656707eb949"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers
    $response | ConvertTo-Json
} catch {
    $_.Exception.Message
}
