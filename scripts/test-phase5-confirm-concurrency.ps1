$ErrorActionPreference = 'Stop'
$db = 'supabase_db_juridico-sync'
$office = '90000000-0000-4000-9000-000000000001'
$lawyer = '90000000-0000-4000-8000-000000000001'
$lawyer2 = '90000000-0000-4000-8000-000000000002'
$client = '90000000-0000-4000-b000-000000000001'
$partyA = '90000000-0000-4000-a000-000000000001'
$partyB = [guid]::NewGuid().ToString()
$relation = [guid]::NewGuid().ToString()
function Invoke-Psql([string]$sql) { $sql | docker exec -i $db psql -qAt -U postgres -d postgres }
Invoke-Psql "
insert into auth.users(id,email) values ('$lawyer','confirm-concurrency-lawyer@example.test'),('$lawyer2','confirm-concurrency-lawyer2@example.test') on conflict do nothing;
insert into public.office(id,name,is_active) values ('$office','Confirm Concurrency Office',true) on conflict do nothing;
insert into public.user_profile(id,office_id,name,role,is_owner,is_active) values ('$lawyer','$office','Confirm Lawyer','lawyer',true,true),('$lawyer2','$office','Confirm Lawyer 2','lawyer',false,true) on conflict(id) do nothing;
insert into public.party(id,office_id,party_type,display_name,normalized_name,created_by) values ('$partyA','$office','person','Confirm Client','confirm client','$lawyer'),('$partyB','$office','person','Confirm Related','confirm related','$lawyer') on conflict(id) do nothing;
insert into public.client(id,office_id,party_id,created_by) values ('$client','$office','$partyA','$lawyer') on conflict(id) do nothing;
delete from public.client_related_party where id='$relation';
insert into public.client_related_party(id,office_id,client_id,party_id,relation_type,created_by) values ('$relation','$office','$client','$partyB','representative','$lawyer');
"
$confirmSql = "begin; set local role authenticated; select set_config('request.jwt.claim.sub','$lawyer',true); select pg_sleep(0.2); select public.confirm_client_related_party('$relation'); commit;"
$rejectSql = "begin; set local role authenticated; select set_config('request.jwt.claim.sub','$lawyer2',true); select public.reject_client_related_party('$relation'); commit;"
$tempRoot = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { [System.IO.Path]::GetTempPath() }
$confirmFile = Join-Path $tempRoot 'phase5-confirm.sql'; $rejectFile = Join-Path $tempRoot 'phase5-reject.sql'
Set-Content -Path $confirmFile -Value $confirmSql -Encoding UTF8
Set-Content -Path $rejectFile -Value $rejectSql -Encoding UTF8
$confirmJob = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$confirmFile
Start-Sleep -Milliseconds 300
$rejectJob = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$rejectFile
Wait-Job $confirmJob,$rejectJob | Out-Null
$confirmOutput = Receive-Job $confirmJob
$rejectOutput = Receive-Job $rejectJob
$confirmRc = if($confirmJob.State -eq 'Completed'){0}else{1}
$rejectRc = if($rejectJob.State -eq 'Completed'){0}else{1}
Remove-Job $confirmJob,$rejectJob -Force
Remove-Item $confirmFile,$rejectFile -Force
$result = Invoke-Psql "select confirmation_status || '|' || coalesce(confirmed_by::text,'') || '|' || (select count(*) from public.audit_log where entity_id='$relation' and action in ('client_related_party.confirmed','client_related_party.rejected')) from public.client_related_party where id='$relation';"
$confirmText = $confirmOutput -join ' '
$rejectText = $rejectOutput -join ' '
$success = if($confirmText -notmatch 'ERROR' -and $confirmText -match $lawyer){1}else{0}
$rejected = if($rejectText -match 'ERROR:  invalid transition'){1}else{0}
$terminalAudits = if($result -match '^(confirmed|rejected)\|[0-9a-f-]+\|1$'){1}else{0}
Write-Output "attempts=2 success=$success rejected=$rejected terminal_audits=$terminalAudits"
Write-Output "confirm_process=$confirmRc reject_process=$rejectRc"
Write-Output "final=$result"
Write-Output "confirm_output=$confirmText"
Write-Output "reject_output=$rejectText"
if($success -ne 1 -or $rejected -ne 1 -or $terminalAudits -ne 1){ exit 1 }
