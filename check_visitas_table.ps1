$headers = @{
    "apikey" = "sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
    "Authorization" = "Bearer sb_publishable_G6dRjvRfALqwuYaG1kew7w_Xud8hTgb"
}
# Supabase doesn't easily allow listing schemas/tables via REST without specific permissions, 
# but we can try to query a table we know exists to confirm.
$url = "https://awhuzekjpoapamijlvua.supabase.co/rest/v1/visitas?select=*"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers
    "Table 'visitas' exists. Sample data (first 1):"
    $response | Select-Object -First 1 | ConvertTo-Json
} catch {
    "Error or table doesn't exist: " + $_.Exception.Message
}
