$ErrorActionPreference = 'Stop'

$container = docker ps --filter "label=com.supabase.cli.project=juridico-sync" --filter "name=supabase_db" --format "{{.Names}}"
if ([string]::IsNullOrWhiteSpace($container)) {
    $container = 'supabase_db_juridico-sync'
}

$userId = '50000000-0000-0000-0000-000000000001'
$officeId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'

$seed = @"
DELETE FROM public.rate_limit_bucket WHERE office_id = '$officeId' AND actor_user_id = '$userId';
INSERT INTO auth.users (id, email) VALUES ('$userId', 'concurrency-owner@test.local') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.office (id, name, is_active) VALUES ('$officeId', 'Concurrency Office', true) ON CONFLICT (id) DO UPDATE SET is_active = true;
INSERT INTO public.user_profile (id, office_id, name, role, is_owner, is_active) VALUES ('$userId', '$officeId', 'Concurrency Owner', 'lawyer', true, true) ON CONFLICT (id) DO UPDATE SET office_id = EXCLUDED.office_id, role = EXCLUDED.role, is_owner = true, is_active = true;
"@
docker exec $container psql -q -U postgres -d postgres -v ON_ERROR_STOP=1 -c $seed | Out-Null

$jobs = 1..6 | ForEach-Object {
  Start-Job -ScriptBlock {
    param($containerName, $targetUserId)
    $sql = "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims', json_build_object('sub', '$targetUserId', 'role', 'authenticated')::text, true); SELECT (public.consume_admin_rate_limit('admin.invite')).allowed; COMMIT;"
    docker exec $containerName psql -qAt -U postgres -d postgres -c $sql
  } -ArgumentList $container, $userId
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job -Force
$decisions = $results | Where-Object { $_ -eq 't' -or $_ -eq 'f' }
$allowed = @($decisions | Where-Object { $_ -eq 't' }).Count
$blocked = @($decisions | Where-Object { $_ -eq 'f' }).Count
$count = docker exec $container psql -qAt -U postgres -d postgres -c "SELECT request_count FROM public.rate_limit_bucket WHERE operation = 'admin.invite' AND office_id = '$officeId' AND actor_user_id = '$userId';"
$count = ($count | Select-Object -Last 1).Trim()
Write-Output "decisions=$($decisions -join ',') allowed=$allowed blocked=$blocked final_count=$count"
if ($allowed -ne 5 -or $blocked -ne 1 -or $count -ne '5') {
  throw 'Atomic rate limit assertion failed.'
}
